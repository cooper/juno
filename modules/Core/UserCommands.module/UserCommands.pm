# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "Core::UserCommands"
# @version:         ircd->VERSION
# @package:         "M::Core::UserCommands"
# @description:     "the core set of user commands"
#
# @depends.modules: ['Base::UserCommands', 'Base::Capabilities']
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Core::UserCommands;

use warnings;
use strict;
use 5.010;

use Scalar::Util qw(blessed);
use utils qw(col match cut_to_limit conf v notice gnotice simplify ref_to_list irc_match);

our ($api, $mod, $me, $pool, $conf, $VERSION);

our %user_commands = (
    CONNECT => {
        code   => \&sconnect,
        desc   => 'connect to a server',
        params => '-oper(connect) *'
    },
    LUSERS => {
        code   => \&lusers,
        desc   => 'view connection count statistics'
    },
    REHASH => {
        code   => \&rehash,
        desc   => 'reload the server configuration',
        params => '-oper(rehash) *(opt)'
    },
    KILL => {
        code   => \&ukill,
        desc   => 'forcibly remove a user from the server',
        params => 'user :rest' # oper flags handled later
    },
    KICK => {
        code   => \&kick,
        desc   => 'forcibly remove a user from a channel',
        params => 'channel(inchan) user :rest(opt)',
        fntsy  => 1
    },
    LIST => {
        code   => \&list,
        desc   => 'view information of channels on the server'
    },
    MODELIST => {
        code   => \&modelist,
        desc   => 'view entries of a channel mode list',
        params => 'channel(inchan) *',
        fntsy  => 1
    },
    VERSION => {
        code   => \&version,
        desc   => 'view server version information',
        params => 'server_mask(opt)'
    },
    LINKS => {
        code   => \&links,
        desc   => 'display server links',
        params => '*(opt) *(opt)'
    },
    SQUIT => {
        code   => \&squit,
        desc   => 'disconnect a server',
        params => '-oper(squit) *'
    },
    ECHO => {
        code   => \&echo,
        desc   => 'echos a message',
        params => 'channel *'
    },
    TOPIC => {
        code   => \&topic,
        desc   => 'view or set the topic of a channel',
        params => 'channel *(opt)',
        fntsy  => 1
    },
    WHO => {
        code   => \&who,
        desc   => 'familiarize your client with users matching a pattern',
        params => '*(opt) *(opt)',
        fntsy  => 1
    },
    PART => {
        code   => \&part,
        desc   => 'leave a channel',
        params => 'channel(inchan) *(opt)',
        fntsy  => 1
    },
    QUIT => {
        code   => \&quit,
        desc   => 'disconnect from the server',
        params => '*(opt)'
    },
    AWAY => {
        code   => \&away,
        desc   => 'mark yourself as away or return from being away',
        params => '*(opt)',
    },
    ISON => {
        code   => \&ison,
        desc   => 'check if users are online',
        params => '...'
    },
    WHOIS => {
        code   => \&whois,
        desc   => 'display information on a user',
        params => '* *(opt)'
    },
    NAMES => {
        code   => \&names,
        desc   => 'view the user list of a channel',
        fntsy  => 1,
        params => '*(opt)'
    },
    OPER => {
        code   => \&oper,
        desc   => 'gain privileges of an IRC operator',
        params => '* *'
    },
    MAP => {
        code   => \&smap,
        desc   => 'view a list of servers connected to the network'
    },
    JOIN => {
        code   => \&_join,
        desc   => 'join a channel',
        params => '* *(opt)'
    },
    PRIVMSG => {
        code   => \&privmsgnotice,
        desc   => 'send a message to a user or channel',
        params => '-message -command * :rest'
    },
    NOTICE => {
        code   => \&privmsgnotice,
        desc   => 'send a notice to a user or channel',
        params => '-message -command * :rest'
    },
    MODE => {
        code   => \&mode,
        desc   => 'view or change user and channel modes',
        fntsy  => 1,
        params => '* ...(opt)'
    },
    INFO => {
        code   => \&info,
        desc   => 'display ircd license and credits'
    },
    MOTD => {
        code   => \&motd,
        desc   => 'display the message of the day',
        params => 'server_mask(opt)'
    },
    NICK => {
        code   => \&nick,
        desc   => 'change your nickname',
        params => '*'
    },
    ADMIN => {
        code   => \&admin,
        desc   => 'server administrative information',
        params => 'server_mask(opt)'
    },
    TIME => {
        code   => \&_time,
        desc   => 'server time',
        params => 'server_mask(opt)'
    },
    USERHOST => {
        code   => \&userhost,
        desc   => 'user hostmask query',
        params => '@rest'
    },
    PING => {
        code    => \&ping,
        desc    => 'check connection status',
        params  => '*'
    }
);

sub init {

    &add_join_callbacks;
    &add_whois_callbacks;

    # capabilities that idk where else to put! :^)
    $mod->register_capability('cap-notify');
    $mod->register_capability('away-notify');
    $mod->register_capability('chghost');
    $mod->register_capability('account-notify');
    $mod->register_capability('extended-join');

    return 1;
}

sub motd {
    my ($user, $event, $server) = @_;

    # this does not apply to me; forward it.
    if ($server && $server != $me) {
        $server->{location}->fire_command(motd => $user, $server);
        return 1;
    }

    my @motd_lines;

    # note: as of 5.95, MOTD is typically not stored in RAM.
    # instead, it is read from the disk each time it is requested.

    # first, check if an MOTD is present in v.
    if (defined v('MOTD') && ref v('MOTD') eq 'ARRAY') {
        @motd_lines = @{ v('MOTD') };
    }

    # it is not in RAM. we will try to read from file.
    elsif (open my $motd, conf('file', 'motd')) {
        @motd_lines = map { chomp; $_ } my @lines = <$motd>;
        close $motd;
    }

    # if there are no MOTD lines, we have no MOTD.
    if (!scalar @motd_lines) {
        $user->numeric('ERR_NOMOTD');
        return;
    }

    # yay, we found an MOTD. let's send it.
    $user->numeric('RPL_MOTDSTART', $me->{name});
    $user->numeric('RPL_MOTD', $_) foreach @motd_lines;
    $user->numeric('RPL_ENDOFMOTD');

    return 1;
}

# change nickname
sub nick {
    my ($user, $event, $newnick) = @_;
    my $me = lc $user->{nick} eq lc $newnick;

    if ($newnick eq '0') {
        $newnick = $user->{uid};
    }
    else {

        # check for valid nick.
        if (!utils::validnick($newnick)) {
            $user->numeric(ERR_ERRONEUSNICKNAME => $newnick);
            return;
        }

        # check for existing nick.
        my $in_use = $pool->nick_in_use($newnick);
        if ($in_use && $in_use != $user) {
            $user->numeric(ERR_NICKNAMEINUSE => $newnick);
            return;
        }

    }

    # ignore stupid nick changes.
    return if $user->{nick} eq $newnick;

    # tell ppl.
    $user->send_to_channels("NICK $newnick");

    # change it.
    $user->change_nick($newnick, time);
    $pool->fire_command_all(nickchange => $user);

}

sub info {
    # TODO: does not support remote
    my ($LNAME, $NAME, $VERSION) = (v('LNAME'), v('NAME'), v('VERSION'));
    my $user = shift;
    my $info = <<"END";

\2***\2 this is \2$LNAME\2 $NAME version \2$VERSION ***\2

Copyright (c) 2010-16, the $NAME developers

This program is free software.
You are free to modify and redistribute it under the terms of
the three-clause "New" BSD license (see LICENSE in source.)

$NAME wouldn't be here if it weren't for the people who have
contributed time, effort, care, and love to the project.

\2Developers\2
    Mitchell Cooper, \"cooper\" <mitchell\@notroll.net> https://github.com/cooper
    Matt Barksdale, \"matthew\" <matt\@arinity.org> https://github.com/mattwb65
    Hakkin Lain, \"Hakkin\" <hakkin\@notroll.net> https://github.com/Hakkin
    James Lu, \"GL\" <GLolol\@overdrivenetworks.com> https://github.com/GLolol
    Kyle Paranoid, \"mac-mini\" <mac-mini\@mac-mini.org> https://github.com/mac-mini
    Daniel Leining, \"daniel\" <daniel\@the-beach.co> https://github.com/blasphemy
    Matthew Carey, \"swarley\" <matthew.b.carey\@gmail.com> https://github.com/swarley
    Alyx Wolcott, \"alyx\" <contact\@alyxw.me> https://github.com/alyx
    Carl Harris, \"Kitty\" <kitty\@xdk2.net> https://github.com/xKitty
    Clay Freeman, \"clayfreeman\" <clay\@irishninjas.com> https://github.com/clayfreeman
    Brandon Rodriguez, \"beyond\" <beyond\@mailtrap.org>
    Nick Dalsheimer, \"AstroTurf\" <astronomerturf\@gmail.com>
    Corey Chex, \"Corey\" <corey\@notroll.net>

If you have any questions or concerns, feel free to email the above
developers directly or contact NoTrollPlzNet at <contact\@notroll.net>.

Proudly brought to you by \2\x0302No\x0313Troll\x0304Plz\x0309Net\x0f
http://notroll.net

END
    $user->numeric('RPL_INFO', $_) foreach split /\n/, $info;
    $user->numeric('RPL_ENDOFINFO');
    return 1
}

sub mode {
    my ($user, $event, $t_name, @rest) = @_;
    my $modestr = join ' ', @rest;

    # is it the user himself?
    if (lc $user->{nick} eq lc $t_name) {

        # mode change.
        if (length $modestr) {
            $user->do_mode_string($modestr);
            return 1;
        }

        # mode view.
        else {
            $user->numeric('RPL_UMODEIS', $user->mode_string);
            return 1;
        }
    }

    # is it a channel, then?
    if (my $channel = $pool->lookup_channel($t_name)) {

        # viewing.
        if (!length $modestr) {
            $channel->modes($user);
            return 1;
        }

        # setting.
        $channel->do_mode_string($user->{server}, $user, $modestr);
        return 1;

    }

    # hmm.. maybe it's another user
    if ($pool->lookup_user_nick($t_name)) {
        $user->numeric('ERR_USERSDONTMATCH');
        return;
    }

    # no such nick/channel
    $user->numeric(ERR_NOSUCHNICK => $t_name);
    return;
}

sub privmsgnotice {
    my ($user, $event, $msg, $command, $t_name, $message) = @_;
    $msg->{message} = $message;

    # no text to send.
    if (!length $message) {
        $user->numeric('ERR_NOTEXTTOSEND');
        return;
    }

    # is it a user?
    my $tuser = $pool->lookup_user_nick($t_name);
    if ($tuser) {

        # TODO: here check for user modes preventing
        # the user from sending the message.

        # tell them of away if set
        if ($command eq 'PRIVMSG' && length $user->{away}) {
            $user->numeric('RPL_AWAY', $tuser->{nick}, $tuser->{away});
        }

        # if it's a local user, send it to them.
        if ($tuser->is_local) {
            $tuser->sendfrom($user->full, "$command $$tuser{nick} :$message");
        }

        # send it to the server holding this user.
        else {
            $tuser->{location}->fire_command(privmsgnotice => $command, $user, $tuser, $message);
        }

        $msg->{target} = $tuser;
        return 1;
    }

    # must be a channel.
    my $channel = $pool->lookup_channel($t_name);
    if ($channel) {
        $channel->handle_privmsgnotice($command, $user, $message);
        $msg->{target} = $channel;
        return 1;
    }

    # no such nick/channel.
    $user->numeric(ERR_NOSUCHNICK => $t_name);
    return;

}

sub smap {
    my $user  = shift;
    my $total = scalar $pool->actual_users;

    my ($indent, $do, %done) = 0;
    $do = sub {
        my $server = shift;
        return if $done{$server};

        my $spaces = ' ' x $indent;
        my $users  = scalar $server->actual_users;
        my $per    = sprintf '%.f', $users / $total * 100;

        $user->numeric(RPL_MAP => $spaces, $server->{name}, $users, $per);

        # increase indent and do children.
        $indent += 4;
        $do->($_) foreach $server->children;
        $indent -= 4;

        $done{$server} = 1;
    };
    $do->($me);

    my $average = int($total / scalar(keys %done) + 0.5);
    $user->numeric(RPL_MAP2 => $total, scalar(keys %done), $average);
    $user->numeric('RPL_MAPEND');

}

sub add_join_callbacks {
    my $JOIN_OK;

    # check if user is in channel already.
    $pool->on('user.can_join' => sub {
        my ($event, $channel) = @_;
        my $user = $event->object;

        # already in the channel
        $event->stop('in_channel')
            if $channel->has_user($user);

    }, name => 'in.channel', priority => 30);

    # check if the user has reached his limit.
    $pool->on('user.can_join' => sub {
        my ($event, $channel) = @_;
        my $user = $event->object;

        # hasn't reached the limit.
        return $JOIN_OK
            unless $user->channels >= conf('limit', 'channel');

        # limit reached.
        $user->numeric(ERR_TOOMANYCHANNELS => $channel->name);
        $event->stop('max_channels');

    }, name => 'max.channels', priority => 25);

    # check for a ban.
    $pool->on('user.can_join' => sub {
        my ($event, $channel) = @_;
        my $user = $event->object;

        my $banned = $channel->list_matches('ban',    $user);
        my $exempt = $channel->list_matches('except', $user);

        # sorry, banned.
        if ($banned && !$exempt) {
            $user->numeric(ERR_BANNEDFROMCHAN => $channel->name);
            $event->stop('banned');
        }

    }, name => 'is.banned', priority => 10);

}

sub _join {
    my ($user, $event, $given, $channel_key) = @_;

    # part all channels.
    if ($given eq '0') {
        $user->do_part_all();
        $pool->fire_command_all(part_all => $user);
        return 1;
    }

    # comma-separated list.
    foreach my $chname (split ',', $given) {

        # make sure it's a valid name.
        if (!utils::validchan($chname)) {
            $user->numeric(ERR_NOSUCHCHANNEL => $chname);
            next;
        }

        # if the channel exists, just join.
        my ($channel, $new) = $pool->lookup_or_create_channel($chname);
        $channel->attempt_local_join($user, $new, $channel_key);

    }

    return 1;
}

sub names {
    my ($user, $event, $given) = @_;

    # we aren't currently supporting NAMES without a parameter
    if (!defined $given) {
        $user->numeric(RPL_LOAD2HI => 'NAMES');
        $user->numeric(RPL_ENDOFNAMES => '*');
        return;
    }

    foreach my $chname (split ',', $given) {
        # nonexistent channels return no error,
        # and RPL_ENDOFNAMES is sent no matter what
        my $channel = $pool->lookup_channel($chname);
        $channel->names($user, 1) if $channel;
        $user->numeric(RPL_ENDOFNAMES => $channel ? $channel->name : $chname);
    }

    return 1;
}

sub oper {
    my ($user, $event, $oper_name, $oper_password) = @_;

    # find the account.
    my %oper = $conf->hash_of_block(['oper', $oper_name]);

    # make sure required options are present.
    my @required = qw(password encryption);
    foreach (@required) {
        next if defined $oper{$_};
        $user->numeric('ERR_NOOPERHOST');
        return;
    }

    # oper is limited to specific host(s).
    if (defined $oper{host}) {
        my $win;
        my @hosts = ref $oper{host} eq 'ARRAY' ? @{ $oper{host} } : $oper{host};
        foreach my $host (@hosts) {
            $win = 1, last if match($user, $host);
        }

        # sorry, no host matched.
        if (!$win) {
            $user->numeric('ERR_NOOPERHOST');
            return;
        }

    }

    # so now let's check if the password is right.
    $oper_password = utils::crypt($oper_password, $oper{encryption});
    if ($oper_password ne $oper{password}) {
        $user->numeric('ERR_NOOPERHOST');
        return;
    }

    # flags in their own oper block.
    my @flags   = ref_to_list($oper{flags});
    my @notices = ref_to_list($oper{notices});

    # flags in their oper class block.
    my $add_class;
    $add_class = sub {
        my $oper_class = shift;
        my %class = $conf->hash_of_block(['operclass', $oper_class]);

        # add flags in this block.
        push @flags,   ref_to_list($class{flags});
        push @notices, ref_to_list($class{notices});

        # add parent's flags too.
        $add_class->($class{extends}) if defined $class{extends};

    };
    $add_class->($oper{class}) if defined $oper{class};

    # remove duplicate flags.
    @flags   = simplify(@flags);
    @notices = simplify(@notices);

    # add the flags.
    $user->add_flags(@flags);
    $user->add_notices(@notices);
    $user->{oper} = $oper_name;
    $pool->fire_command_all(oper => $user, @flags);

    # okay, we should have a complete list of flags now.
    my @all_flags   = ref_to_list($user->{flags});
    my @all_notices = ref_to_list($user->{notice_flags});
    $user->server_notice("You now have flags: @all_flags")     if @all_flags;
    $user->server_notice("You now have notices: @all_notices") if @all_notices;
    L(
        "$$user{nick}!$$user{ident}\@$$user{host} has opered as " .
        "$oper_name and was granted flags: @flags"
    );

    # set ircop.
    $user->do_mode_string('+'.$user->{server}->umode_letter('ircop'), 1);
    $user->numeric('RPL_YOUREOPER');

    return 1;
}

sub add_whois_callbacks {

    # whether to show RPL_WHOISCHANNELS.
    my %channels;
    my $show_channels = sub {
        my ($quser, $ruser) = @_;

        # $quser = the one being queried
        # $ruser = the one requesting the info

        # some channels may be skipped using event stopper.
        my @channels;
        foreach my $channel ($quser->channels) {

            # don't show channels for services
            next if $quser->is_mode('service');

            # some callback said not to include this channel
            my $e = $channel->fire_event(show_in_whois => $quser, $ruser);
            next if $e->stopper;

            push @channels, $channel;
        }

        $channels{$quser} = \@channels;
        return scalar @channels;
    };

    my ($p, $ALWAYS_SHOW) = 1000;
    my @whois_replies = (

        # Mask info.
        RPL_WHOISUSER =>
            $ALWAYS_SHOW,
            sub { @{ +shift }{ qw(ident cloak real) } },

        # Channels. See above for exclusions.
        RPL_WHOISCHANNELS =>
            $show_channels,
            sub {
                my ($quser, $ruser) = @_;
                my @all_chans = @{ delete $channels{$quser} || [] };
                return join ' ', map {
                    $_->prefixes($quser).$_->{name}
                } @all_chans;
            },

        # Server the user is on.
        RPL_WHOISSERVER =>
            $ALWAYS_SHOW,
            sub {
                my $server  = shift->{server};
                return @$server{ qw(name desc ) };
            },

        # User is using a secure connection.
        RPL_WHOISSECURE =>
             sub { shift->is_mode('ssl') },
             undef,

        # User is an IRC operator.
        RPL_WHOISOPERATOR =>
            sub { shift->is_mode('ircop') },
            sub {
                my $user = shift;
                return $user->is_mode('service') ? 'a network service'      :
                       $user->is_mode('admin')   ? 'a server administrator' :
                       'an IRC operator'                                    ;
            },

        # User is away.
        RPL_AWAY =>
            sub { length shift->{away} },
            sub { shift->{away} },

        # User modes.
        RPL_WHOISMODES =>
            sub { shift->mode_string },
            sub { shift->mode_string },

        # Real host. See issue #72.
        RPL_WHOISHOST =>
            sub {
                my ($quser, $ruser) = @_;
                return 1 if $quser == $ruser; # always show to himself
                return $ruser->has_flag('see_hosts');
            },
            sub { @{ +shift }{ qw(host ip) } },

        # Idle time. Local only.
        RPL_WHOISIDLE =>
            sub { shift->is_local },
            sub {
                my $user = shift;
                my $idle = time - ($user->{conn}{last_command} || 0);
                return ($idle, $user->{create_time});
            },

        # Account name.
        RPL_WHOISACCOUNT =>
            sub { shift->{account} },
            sub { shift->{account}{name} },

        # END OF WHOIS.
        RPL_ENDOFWHOIS =>
            $ALWAYS_SHOW,
            undef

    );

    # add each callback
    while (my ($constant, $conditional_sub, $argument_sub) =
    splice @whois_replies, 0, 3) { $p -= 5;
        $pool->on('user.whois_query' => sub {
            my ($ruser, $event, $quser) = @_;

            # conditional sub.
            $conditional_sub->($quser, $ruser) or return
                if $conditional_sub;

            # argument sub.
            my @args = $argument_sub->($quser, $ruser)
                if $argument_sub;

            $ruser->numeric($constant => $quser->{nick}, @args);
        }, name => $constant, priority => $p, with_eo => 1);
    }

}

# may be called remotely.
sub whois {
    my ($user, $event, @args) = @_;

    # server parameter.
    my ($server, $quser, $query);
    if (length $args[1]) {
        $query  = $args[1];
        $quser  = $pool->lookup_user_nick($query);
        $server = lc $args[0] eq lc $args[1] ?
            $quser->{server} : $pool->lookup_server_mask($args[0]);
    }

    # no server parameter.
    else {
        $server = $me;
        $query  = $args[0];
        $quser  = $pool->lookup_user_nick($query);
    }

    # server exists?
    if (!$server) {
        $user->numeric(ERR_NOSUCHSERVER => $args[0]);
        return;
    }

    # user exists?
    if (!$quser) {
        $user->numeric(ERR_NOSUCHNICK => $query);
        return;
    }

    # this does not apply to me; forward it.
    # no reason to forward it if the target location isn't the user's location.
    if ($server != $me && $server->{location} == $quser->{location}) {
        $server->{location}->fire_command(whois => $user, $quser, $server);
        return 1;
    }

    # NOTE: these handlers must not assume $quser to be local.
    $user->fire(whois_query => $quser);

    return 1;
}

sub ison {
    my ($user, $event, @args) = @_;
    my @found;

    # for each nick, lookup and add if exists.
    foreach my $nick (@args) {
        my $user = $pool->lookup_user_nick(col($nick));
        push @found, $user->{nick} if $user;
    }

    $user->numeric(RPL_ISON => "@found");
}

sub away {
    my ($user, $event, $reason) = @_;
    my $ok = $user->do_away($reason);

    # status 1 = set away, 2 = unset away
    $pool->fire_command_all(away        => $user) if $ok && $ok == 1;
    $pool->fire_command_all(return_away => $user) if $ok && $ok == 2;

    return 1;
}

sub quit {
    my ($user, $event, $reason) = @_;
    $reason //= 'leaving';
    $user->{conn}->done("~ $reason");
}

sub part {
    my ($user, $event, $channel, $reason) = @_;

    # tell channel's users and servers.
    $channel->do_part($user, $reason);
    $pool->fire_command_all(part => $user, $channel, $reason);

    return 1;
}

sub sconnect {
    my ($user, $event, $smask) = @_;
    my @servers = grep irc_match($_, $smask), $conf->names_of_block('connect');
    foreach my $s_name (@servers) {
        if (my $e = server::linkage::connect_server($s_name)) {
            $user->server_notice(connect => "$s_name: $e");
            next;
        }
        $user->server_notice(connect => "Attempting to connect to $s_name");
    }
    return 1;
}

#########################################################################
#                           WHO query :(                                #
#-----------------------------------------------------------------------#
#                                                                       #
# I'll try to do what rfc2812 says this time.                           #
#                                                                       #
# The WHO command is used by a client to generate a query which returns #
# a list of information which 'matches' the <mask> parameter given by   #
# the client.  In the absence of the <mask> parameter, all visible      #
# (users who aren't invisible (user mode +i) and who don't have a       #
# common channel with the requesting client) are listed.  The same      #
# result can be achieved by using a <mask> of "0" or any wildcard which #
# will end up matching every visible user.                              #
#                                                                       #
# by the looks of it, we can match a username, nickname, real name,     #
# host, or server name.                                                 #
#########################################################################

sub who {
    my ($user, $event, @args) = @_;
    my $query                = $args[0];
    my $match_pattern        = '*';
    my %matches;

    # match all, like the above note says
    if ($query eq '0') {
        foreach my $quser ($pool->all_users) {
            $matches{ $quser->{uid} } = $quser
        }
        # I used UIDs so there are no duplicates
    }

    # match an exact channel name
    elsif (my $channel = $pool->lookup_channel($query)) {

        # multi-prefix support?
        my $prefixes = $user->has_cap('multi-prefix') ? 'prefixes' : 'prefix';

        $match_pattern = $channel->name;
        foreach my $quser ($channel->users) {
            $matches{ $quser->{uid} } = $quser;
            $quser->{who_flags}       = $channel->$prefixes($quser);
        }
    }

    # match a pattern
    else {
        foreach my $quser ($pool->all_users) {
            foreach my $pattern ($quser->{nick}, $quser->{ident}, $quser->{host},
              $quser->{real}, $quser->{server}{name}) {
                $matches{ $quser->{uid} } = $quser if match($pattern, $query);
            }
        }
        # this doesn't have to match anyone
    }

    # weed out invisibles
    foreach my $uid (keys %matches) {
        my $quser     = $matches{$uid};
        my $who_flags = delete $quser->{who_flags} || '';

        # weed out invisibles
        next if
          $quser->is_mode('invisible')                   &&
          !$pool->channel_in_common($user, $quser) &&
          !$user->has_flag('see_invisible');

        # rfc2812:
        # If the "o" parameter is passed only operators are returned according
        # to the <mask> supplied.
        next if ($args[2] && index($args[2], 'o') != -1 && !$quser->is_mode('ircop'));

        # found a match
        $who_flags = (length $quser->{away} ? 'G' : 'H') .
                     $who_flags . ($quser->is_mode('ircop') ? '*' : q||);
        $user->numeric(RPL_WHOREPLY =>
            $match_pattern, $quser->{ident}, $quser->{host}, $quser->{server}{name},
            $quser->{nick}, $who_flags, $user->hops_to($quser), $quser->{real}
        );
    }

    $user->numeric(RPL_ENDOFWHO => $query);
    return 1;
}

sub topic {
    my ($user, $event, $channel, $new_topic) = @_;

    # setting topic.
    if (defined $new_topic) {
        my $can = (!$channel->is_mode('protect_topic')) ?
            1 : $channel->user_has_basic_status($user);

        # not permitted.
        if (!$can) {
            $user->numeric(ERR_CHANOPRIVSNEEDED => $channel->name);
            return;
        }

        $channel->sendfrom_all($user->full, "TOPIC $$channel{name} :$new_topic");
        $pool->fire_command_all(topic => $user, $channel, time, $new_topic);

        # set it.
        if (length $new_topic) {
            $channel->{topic} = {
                setby => $user->full,
                time  => time,
                topic => $new_topic
            };
        }

        # delete it.
        else {
            delete $channel->{topic};
        }

    }

    # viewing topic
    else {

        # topic set.
        if (my $topic = $channel->topic) {
            $user->numeric(RPL_TOPIC        => $channel->name, $topic->{topic});
            $user->numeric(RPL_TOPICWHOTIME => $channel->name, $topic->{setby}, $topic->{time});
        }

        # no topic set.
        else {
            $user->numeric(RPL_NOTOPIC => $channel->name);
            return;
        }

    }

    return 1;
}

sub lusers {
    # TODO: does not support remote
    my $user = shift;
    my @actual_users = $pool->actual_users;

    # get server count
    my $servers   = scalar $pool->servers;
    my $l_servers = scalar grep { $_->{conn} } $pool->servers;

    # get x users, x invisible, and total global
    my ($g_not_invisible, $g_invisible) = (0, 0);
    foreach my $user (@actual_users) {
        $g_invisible++, next if $user->is_mode('invisible');
        $g_not_invisible++;
    }
    my $g_users = $g_not_invisible + $g_invisible;

    # get local users
    my $l_users = scalar grep { $_->is_local } @actual_users;

    # get connection count and max connection count
    my $conn     = v('connection_count');
    my $conn_max = v('max_connection_count');

    # get oper count and channel count
    my $opers = scalar grep { $_->is_mode('ircop') } @actual_users;
    my $chans = scalar $pool->channels;

    # get max global and max local
    my $m_global = v('max_global_user_count');
    my $m_local  = v('max_local_user_count');

    # send numerics
    $user->numeric(RPL_LUSERCLIENT   => $g_not_invisible, $g_invisible, $servers);
    $user->numeric(RPL_LUSEROP       => $opers);
    $user->numeric(RPL_LUSERCHANNELS => $chans);
    $user->numeric(RPL_LUSERME       => $l_users, $l_servers);
    $user->numeric(RPL_LOCALUSERS    => $l_users, $m_local, $l_users, $m_local);
    $user->numeric(RPL_GLOBALUSERS   => $g_users, $m_global, $g_users, $m_global);
    $user->numeric(RPL_STATSCONN     => $conn_max, $m_local, $conn);
}

sub rehash {
    my ($user, $event, $server_mask_maybe) = @_;

    # server mask parameter
    if (length $server_mask_maybe) {
        my @servers = $pool->lookup_server_mask($server_mask_maybe);

        # no priv.
        if (!$user->has_flag('grehash')) {
            $user->numeric(ERR_NOPRIVILEGES => 'grehash');
            return;
        }

        # no matches.
        if (!@servers) {
            $user->numeric(ERR_NOSUCHSERVER => $server_mask_maybe);
            return;
        }

        # use forward_global_command() to send it out.
        my $matched = server::protocol::forward_global_command(
            \@servers, ircd_rehash =>
            $user, $server_mask_maybe, undef,
            $server::protocol::INJECT_SERVERS
        ) if @servers;
        my %matched = $matched ? %$matched : ();

        # if $me is not in %done, we're not rehashing locally.
        return 1 if !$matched{$me};

    }

    # "is rehashing" -- does not specify success or failure
    gnotice(rehash => $user->notice_info);

    # rehash.
    $user->numeric(RPL_REHASHING => $ircd::conf->{conffile});
    ircd::rehash($user);

}

sub ukill {
    my ($user, $event, $tuser, $reason) = @_;

    # local user.
    if ($tuser->is_local) {

        # make sure they have kill flag
        if (!$user->has_flag('kill')) {
            $user->numeric(ERR_NOPRIVILEGES => 'kill');
            return;
        }

        # rip in peace.
        $tuser->loc_get_killed_by($user, $reason);
        $pool->fire_command_all(kill => $user, $tuser, $reason);

    }

    # tell other servers.
    # it will be sent throughout the entire system, but only the server who the user is
    # physically connected to will respond by removing the user. The other servers will
    # ->quit the user when that server sends a QUIT message. Because of this, it is possible
    # for kill messages to be ignored entirely. It all depends on the response of the server
    # the target user is connected to.
    else {

        # make sure they have gkill flag
        if (!$user->has_flag('gkill')) {
            $user->numeric(ERR_NOPRIVILEGES => 'gkill');
            return;
        }

        $pool->fire_command_all(kill => $user, $tuser, $reason);
        my $name = $user->name;
        $tuser->quit("Killed ($name ($reason))");
    }

    $user->server_notice('kill', "$$tuser{nick} has been killed");
    return 1
}

# forcibly remove a user from a channel.
# KICK #channel1,#channel2 user1,user2 :reason
sub kick {
    # KICK             #channel        nickname :reason
    # dummy            channel(inchan) user     :rest(opt)
    my ($user, $event, $channel,       $t_user, $reason) = @_;

    # target user is not in channel.
    if (!$channel->has_user($t_user)) {
        $user->numeric(ERR_USERNOTINCHANNEL => $channel->name, $t_user->{nick});
        return;
    }

    # check if the user has basic status in the channel.
    if (!$channel->user_has_basic_status($user)) {
        $user->numeric(ERR_CHANOPRIVSNEEDED => $channel->name);
        return;
    }

    # if the user has a lower status level than the target, he can't kick him.
    if ($channel->user_get_highest_level($t_user) > $channel->user_get_highest_level($user)) {
        $user->numeric(ERR_CHANOPRIVSNEEDED => $channel->name);
        return;
    }

    # determine the reason.
    $reason //= $user->{nick};

    # tell the local users of the channel.
    $channel->user_get_kicked($t_user, $user, $reason);

    # tell the other servers.
    $pool->fire_command_all(kick => $user, $channel, $t_user, $reason);

    return 1;
}

sub list {
    my $user = shift;

    #:ashburn.va.mac-mini.org 321 k Channel :Users  Name
    $user->numeric('RPL_LISTSTART');

    # send for each channel in no particular order.
    foreach my $channel ($pool->channels) {
        next if $channel->fire_event(show_in_list => $user)->stopper;
        # 322 RPL_LIST "<channel> <# visible> :<topic>"
        my $number_of_users = scalar $channel->users;
        my $channel_topic   = $channel->topic ? $channel->topic->{topic} : '';
        $user->numeric(RPL_LIST => $channel->name, $number_of_users, $channel_topic);
    }

    # TODO: implement list for specific channels.
    # TODO: +s and +p (partially done, stopper in place but modes need to be added)

    $user->numeric('RPL_LISTEND');
    return 1;
}

sub modelist {
    my ($user, $event, $channel, $list) = @_;

    # one-character list name indicates a channel mode.
    if (length $list == 1) {
        $list = $me->cmode_name($list);
        $user->server_notice('No such mode') and return unless defined $list;
    }

    # no items in the list.
    my @items = $channel->list_elements($list);
    if (!@items) {
        $user->server_notice('The list is empty');
        return;
    }

    $user->server_notice('modelist', "$$channel{name} \2$list\2 list");
    foreach my $item (@items) {
        $item = $item->{nick} if blessed $item && $item->isa('user');
        $user->server_notice("| $item");
    }
    $user->server_notice('modelist', "End of \2$list\2 list");

    return 1;
}

sub version {
    my ($user, $event, $server) = (shift, shift, shift || $me);

    # if the server isn't me, forward it.
    if ($server != $me) {
        $server->{location}->fire_command(version => $user, $server);
        return 1;
    }

    $user->numeric(RPL_VERSION =>
        v('SNAME').q(-).v('NAME'),  # ircd name and major version name
        $ircd::VERSION,             # current version
        $server->{name},            # server name
        $::VERSION,                 # version at start
        $ircd::VERSION              # current version
    );
    $user->numeric('RPL_ISUPPORT') if $server->is_local;
}

sub squit {
    my ($user, $event, $server_input_name) =  @_;
    my @servers = $pool->lookup_server_mask($server_input_name);

    # if there is a pending timer, cancel it.
    my $canceled_some;
    foreach my $server_name (keys %ircd::link_timers) {
        if (server::linkage::cancel_connection($server_name)) {
            $user->server_notice(squit => 'Canceled connection to '.$server_name);
            notice(server_connect_cancel => $user->notice_info, $server_name);
            $canceled_some = 1;
        }
    }

    # no connected servers match.
    if (!@servers) {
        $user->numeric(ERR_NOSUCHSERVER => $server_input_name) unless $canceled_some;
        return;
    }

    my $amnt = 0;
    foreach my $server (@servers) {

        # no direct connection. might be local server or a
        # psuedoserver or a server reached through another server.
        if (!$server->{conn}) {
            $user->server_notice(squit =>
                "$$server{name} is not connected directly; " .
                "use /SQUIT $$server{name} $$server{parent}{name} to " .
                "disconnect it from its parent"
            ) unless $server->{fake};
            next;
        }

        $amnt++;
        $server->{conn}->{dont_reconnect} = 1;
        $server->{conn}->done('SQUIT command');
        $user->server_notice(squit => "$$server{name} disconnected");
    }

    my $servers = $amnt == 1 ? 'server' : 'servers';
    $user->server_notice(squit => "$amnt $servers disconnected");
    return 1;
}

# note: this handler is used also for remote users.
sub links {
    my ($user, $event, $serv_mask, $query_mask) = @_;
    my $server = $me;

    # query mask but no server mask.
    if (defined $serv_mask && !defined $query_mask) {
        $query_mask = $serv_mask;
        undef $serv_mask;
    }

    # server mask provided.
    if (defined $serv_mask) {
        $server = $pool->lookup_server_mask($serv_mask);

        # no matches.
        if (!$server) {
            $user->numeric(ERR_NOSUCHSERVER => $serv_mask);
            return;
        }

    }

    # if it's not the local server, pass this on.
    if (!$server->is_local) {
        $server->{location}->fire_command(links => $user, $server, $query_mask);
        return 1;
    }

    # it's a request for this server.
    $query_mask //= '*';

    $user->numeric(RPL_LINKS =>
        $_->{name},
        $_->{parent}{name},
        $me->hops_to($_),
        $_->{desc}
    ) foreach $pool->lookup_server_mask($query_mask);

    $user->numeric(RPL_ENDOFLINKS => $query_mask);
    return 1;
}

sub echo {
    my ($user, undef, $channel, $message) = @_;
    my $continue = $channel->handle_privmsgnotice(PRIVMSG => $user, $message);;
    $user->sendfrom($user->full, "PRIVMSG $$channel{name} :$message") if $continue;
}

# note: this handler is used also for remote users.
sub admin {
    my ($user, $event, $server) = @_;

    # this does not apply to me; forward it.
    if ($server && $server != $me) {
        $server->{location}->fire_command(admin => $user, $server);
        return 1;
    }

    # it's for me.
    #
    # note: the RFC says RPL_ADMINME should send <server> :<info>, but most IRCds
    # (including charybdis) only send the <info> parameter with the server name in it.
    # so we will too.
    #
    $user->numeric(RPL_ADMINME    => $me->name             );
    $user->numeric(RPL_ADMINLOC1  => conf('admin', 'line1'));
    $user->numeric(RPL_ADMINLOC2  => conf('admin', 'line2'));
    $user->numeric(RPL_ADMINEMAIL => conf('admin', 'email'));

    return 1;
}

# note: this handler is used also for remote users.
sub _time {
    my ($user, $event, $server) = @_;

    # this does not apply to me; forward it.
    if ($server && $server != $me) {
        $server->{location}->fire_command(time => $user, $server);
        return 1;
    }

    # it's for me.
    $user->numeric(RPL_TIME => time);

    return 1;
}

sub userhost {
    my ($user, $event, @nicknames) = @_;
    my @strs;

    # non-matches should be ignored
    # if no matches are found, still send an empty reply
    foreach my $usr (map $pool->lookup_user_nick($_), @nicknames) {
        next unless $usr;
        my $oper = $usr->is_mode('ircop') ? '*' : '';
        my $away = exists $usr->{away}    ? '-' : '+';
        push @strs, $usr->{nick}."$oper=$away".$usr->full;
    }

    $user->numeric(RPL_USERHOST => join ' ', @strs);
}

sub ping {
    my ($user, $event, $given) = @_;
    $user->sendme("PONG $$me{name} :$given");
}

$mod
