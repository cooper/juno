# Copyright (c) 2009-16, Mitchell Cooper
#
# @name:            "Core::UserCommands"
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
use List::Util qw(first);
use utils qw(
    col match cut_to_limit conf v notice gnotice
    simplify ref_to_list irc_match irc_lc broadcast
);

our ($api, $mod, $me, $pool, $conf);

our %user_commands = (
    CONNECT => {
        code   => \&_connect,
        desc   => 'connect to a server',
        params => '-oper(connect) * *(opt) *(opt)'
    },
    LUSERS => {
        code   => \&lusers,
        params => '*(opt) server_mask(semiopt)',
        desc   => 'view detailed user statistics'
    },
    USERS => {
        code   => \&users,
        params => 'server_mask(semiopt)',
        desc   => 'view user statistics'
    },
    REHASH => {
        code   => \&rehash,
        desc   => 'rehash the server configuration',
        params => '-oper(rehash) *(opt)'
    },
    KILL => {
        code   => \&_kill,
        desc   => 'forcibly remove a user from the server',
        params => '-oper(kill) user :' # oper flags handled later
    },
    KICK => {
        code   => \&kick,
        desc   => 'forcibly remove a user from a channel',
        params => 'channel(inchan) user :(opt)'
    },
    LIST => {
        code   => \&list,
        desc   => 'view the channel directory'
    },
    MODELIST => {
        code   => \&modelist,
        desc   => 'view entries of a channel mode list',
        params => 'channel(inchan) *'
    },
    VERSION => {
        code   => \&version,
        desc   => 'view server version information',
        params => 'server_mask(semiopt)'
    },
    LINKS => {
        code   => \&links,
        desc   => 'display server links',
        params => '*(opt) *(opt)'
    },
    SQUIT => {
        code   => \&squit,
        desc   => 'disconnect a server',
        params => '-oper(squit) * *(opt)'
    },
    ECHO => {
        code   => \&echo,
        desc   => 'echoes a message',
        params => 'channel *'
    },
    TOPIC => {
        code   => \&topic,
        desc   => 'view or set the topic of a channel',
        params => 'channel *(opt)'
    },
    WHO => {
        code   => \&who,
        desc   => 'familiarize your client with users matching a pattern',
        params => '*(opt) *(opt)'
    },
    PART => {
        code   => \&part,
        desc   => 'leave a channel',
        params => 'channel(inchan) *(opt)'
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
        desc   => 'display information about a user',
        params => '* *(opt)'
    },
    NAMES => {
        code   => \&names,
        desc   => 'view the user list of a channel',
        params => '*(opt)'
    },
    OPER => {
        code   => \&oper,
        desc   => 'gain IRC operator privileges',
        params => '* *'
    },
    MAP => {
        code   => \&_map,
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
        params => '-message -command * :'
    },
    NOTICE => {
        code   => \&privmsgnotice,
        desc   => 'send a notice to a user or channel',
        params => '-message -command * :'
    },
    MODE => {
        code   => \&mode,
        desc   => 'view or change user and channel modes',
        params => '* ...(opt)'
    },
    INFO => {
        code   => \&info,
        desc   => 'display ircd license and credits',
        params => 'server_mask(semiopt)'
    },
    MOTD => {
        code   => \&motd,
        desc   => 'display the message of the day',
        params => 'server_mask(semiopt)'
    },
    NICK => {
        code   => \&nick,
        desc   => 'change your nickname',
        params => '*'
    },
    ADMIN => {
        code   => \&admin,
        desc   => 'display server administrative information',
        params => 'server_mask(semiopt)'
    },
    TIME => {
        code   => \&_time,
        desc   => 'display server time',
        params => 'server_mask(semiopt)'
    },
    USERHOST => {
        code   => \&userhost,
        desc   => 'user hostmask query',
        params => '...'
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
    $mod->register_capability('away-notify');
    $mod->register_capability('chghost');
    $mod->register_capability('account-notify');
    $mod->register_capability('extended-join');
    $mod->register_capability('userhost-in-names');

    return 1;
}

# view the messsage of the day
sub motd {
    my ($user, $event, $server) = @_;

    # this does not apply to me; forward it.
    if ($server && $server != $me) {
        $server->{location}->fire_command(motd => $user, $server);
        return 1;
    }

    my @motd_lines;

    # try to read from file.
    if (open my $motd, conf('file', 'motd')) {
        @motd_lines = map { chomp; $_ } <$motd>;
        close $motd;
    }

    # if there are no MOTD lines, we have no MOTD.
    if (!scalar @motd_lines) {
        $user->numeric('ERR_NOMOTD');
        return;
    }

    # yay, we found an MOTD. let's send it.
    $user->numeric(RPL_MOTDSTART => $me->{name});
    $user->numeric(RPL_MOTD      => $_) for @motd_lines;
    $user->numeric(RPL_ENDOFMOTD => );

    return 1;
}

# change nickname
sub nick {
    my ($user, $event, $new_nick) = @_;

    # NICK 0 switches to the UID
    if ($new_nick eq '0' && conf('users', 'allow_uid_nick')) {
        $new_nick = $user->{uid};
    }

    # any other nick
    else {

        # check for valid nick.
        if (!utils::validnick($new_nick)) {
            $user->numeric(ERR_ERRONEUSNICKNAME => $new_nick);
            return;
        }

        # check for existing nick.
        my $in_use = $pool->nick_in_use($new_nick);
        if ($in_use && $in_use != $user) {
            $user->numeric(ERR_NICKNAMEINUSE => $new_nick);
            return;
        }
    }

    # ignore stupid nick changes
    return if $user->{nick} eq $new_nick;

    # change it
    $user->send_to_channels("NICK $new_nick");
    $user->change_nick($new_nick, time);
    broadcast(nick_change => $user);
}

# view IRCd information
# remote-safe
sub info {
    my ($user, $event, $server) = @_;

    # this does not apply to me; forward it.
    if ($server && $server != $me) {
        $server->{location}->fire_command(info => $user, $server);
        return 1;
    }

    # TODO: (#148) does not support remote
    my ($LNAME, $NAME, $VERSION) = map v($_), qw(LNAME NAME VERSION);
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
    $user->numeric(RPL_INFO      => $_) for split /\n/, $info;
    $user->numeric(RPL_ENDOFINFO => );
    return 1;
}

# view/change user or channel modes
sub mode {
    my ($user, $event, $t_name, @rest) = @_;
    my $mode_str = join ' ', @rest;

    # is it the user himself?
    if (irc_lc($user->{nick}) eq irc_lc($t_name)) {

        # mode change.
        return $user->do_mode_string($mode_str)
            if length $mode_str;

        # mode view.
        $user->numeric(RPL_UMODEIS => $user->mode_string);
        return 1;
    }

    # is it a channel, then?
    if (my $channel = $pool->lookup_channel($t_name)) {

        # viewing.
        return $channel->send_modes($user)
            if !length $mode_str;

        # truncate modes.
        my $str_modes = shift @rest;
        my $max_modes = conf('channels', 'client_max_modes_simple');
        if (length $str_modes > $max_modes) { # gotta be AT LEAST this long
            my $new = '';
            for (split //, $str_modes) {
                next if /[^\w]/;
                last if length $new == $max_modes;
                $new .= $_;
            }
            $str_modes = $new;
        }

        # truncate parameters.
        my $max_parameters = conf('channels', 'client_max_mode_params') - 1;
        $max_parameters = $#rest if $#rest < $max_parameters;
        $mode_str = join ' ', $str_modes, @rest[0 .. $max_parameters];

        # do the modes.
        return $channel->do_mode_string($user->server, $user, $mode_str);
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

# PRIVMSG or NOTICE
sub privmsgnotice {
    my ($user, $event, $msg, $command, $t_name, $message) = @_;

    # this may be used by modules hooking onto user.message_PRIVMSG.
    # it is used by Fantasy currently.
    $msg->{message} = $message;

    # no text to send
    if (!length $message) {
        $user->numeric('ERR_NOTEXTTOSEND');
        return;
    }

    # lookup user/channel
    my $target =
        $pool->lookup_user_nick($t_name) ||
        $pool->lookup_channel($t_name);

    # found
    if ($target) {
        $target->do_privmsgnotice($command, $user, $message);
        $msg->{target} = $target;
        return 1;
    }

    # no such nick/channel
    $user->numeric(ERR_NOSUCHNICK => $t_name);
    return;
}

# view server list
sub _map {
    my $user  = shift;
    my $total = scalar $pool->real_users;

    my ($do, %done) = 0;
    $do = sub {
        my ($indent, $server) = @_;
        return if $done{$server}++;
        my $users = scalar $server->real_users;

        # do this server
        $user->numeric(RPL_MAP =>
            ' ' x $indent,
            $server->name,
            $users,
            sprintf('%.f', $users / $total * 100)
        );

        # increase indent and do children
        $do->($indent + 4, $_) for $server->children;

    };
    $do->(0, $me);

    my $average = int($total / scalar(keys %done) + 0.5);
    $user->numeric(RPL_MAP_TOTAL => $total, scalar(keys %done), $average);
    $user->numeric(RPL_MAPEND    => );
}

# default callbacks for can_join.
sub add_join_callbacks {
    my $JOIN_OK;

    # check if user is in channel already.
    $pool->on('user.can_join' => sub {
        my ($user, $event, $channel) = @_;

        # not in the channel.
        return $JOIN_OK
            if !$channel->has_user($user);

        # already there.
        $event->stop('in_channel');

    },
        name     => 'in.channel',
        priority => 30,
        with_eo  => 1
    );

    # check if the user has reached his limit.
    $pool->on('user.can_join' => sub {
        my ($user, $event, $channel) = @_;

        # hasn't reached the limit.
        return $JOIN_OK
            unless $user->channels >= conf('limit', 'channel');

        # limit reached.
        $event->{error_reply} =
            [ ERR_TOOMANYCHANNELS => $channel->name ];
        $event->stop('max_channels');

    },
        name     => 'max.channels',
        priority => 25,
        with_eo  => 1
    );

    # check for a ban.
    $pool->on('user.can_join' => sub {
        my ($user, $event, $channel) = @_;

        # not banned.
        return $JOIN_OK
            if !$channel->user_is_banned($user);

        # sorry, banned.
        $event->{error_reply} = [ ERR_BANNEDFROMCHAN => $channel->name ];
        $event->stop('banned');

    },
        name     => 'is.banned',
        priority => 10,
        with_eo  => 1
    );
}

# join a channel
sub _join {
    my ($user, $event, $given, $channel_key) = @_;

    # JOIN 0 = part all channels.
    if ($given eq '0') {
        $user->do_part_all();
        broadcast(part_all => $user);
        return 1;
    }

    # comma-separated list.
    foreach my $ch_name (split /,/, $given) {

        # make sure it's a valid name.
        if (!utils::validchan($ch_name)) {
            $user->numeric(ERR_NOSUCHCHANNEL => $ch_name);
            next;
        }

        # attempt to join.
        my ($channel, $new) = $pool->lookup_or_create_channel($ch_name);
        $channel->attempt_local_join($user, $new, $channel_key);
    }

    return 1;
}

# view user list
sub names {
    my ($user, $event, $given) = @_;

    # we aren't currently supporting NAMES without a parameter
    if (!defined $given) {
        $user->numeric(RPL_LOAD2HI => 'NAMES');
        $user->numeric(RPL_ENDOFNAMES => '*');
        return;
    }

    foreach my $ch_name (split /,/, $given) {
        # nonexistent channels return no error,
        # and RPL_ENDOFNAMES is sent no matter what
        my $channel = $pool->lookup_channel($ch_name);
        $channel->send_names($user, 1) if $channel;
        $user->numeric(RPL_ENDOFNAMES => $channel ? $channel->name : $ch_name);
    }

    return 1;
}

# obtain oper privileges
sub oper {
    my ($user, $event, $oper_name, $oper_password) = @_;

    # find the account.
    my %oper = $conf->hash_of_block([ 'oper', $oper_name ]);

    # make sure required options are present.
    my @required = qw(password encryption);
    foreach (@required) {
        next if length $oper{$_};
        $user->numeric('ERR_NOOPERHOST');
        return;
    }

    # oper is limited to specific host(s).
    if (defined $oper{host}) {
        my @hosts = ref_to_list($oper{host});

        # sorry, no host matched.
        if (not first { match($user, $_) } @hosts) {
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
        my $class_name = shift;
        my %class = $conf->hash_of_block([ 'operclass', $class_name ]);

        # add flags in this block.
        push @flags,   ref_to_list($class{flags});
        push @notices, ref_to_list($class{notices});

        # add parent classes' flags too.
        $add_class->($_) for ref_to_list($class{extends});
    };
    $add_class->($oper{class})
        if defined $oper{class};

    # add the flags
    @flags = $user->add_flags(@flags);
    $user->add_notices(@notices);
    $user->update_flags;

    # the last-opered-as name.
    # this should NOT be used to check if a user is an IRCop.
    $user->{oper} = $oper_name;

    # tell other servers
    broadcast(oper => $user, @flags);

    return 1;
}

# default callbacks for whois_query.
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
            my $e = $channel->fire(show_in_whois => $quser, $ruser);
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
                my $idle = time - ($user->conn->{last_command} || 0);
                return ($idle, $user->{time});
            },

        # Account name.
        RPL_WHOISACCOUNT =>
            sub { shift->{account} },
            sub { shift->{account}{name} },

        # Bot user mode.
        RPL_WHOISBOT =>
            sub { shift->is_mode('bot') },
            undef,

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

# WHOIS query
# remote-safe
sub whois {
    my ($user, $event, $t_server, $t_nick) = @_;

    # server parameter.
    my ($server, $quser, $query);
    if (length $t_nick) {
        $query = $t_nick;
        $quser = $pool->lookup_user_nick($t_nick);

        # the server parameter might be the nickname
        $server = irc_lc($t_server) eq irc_lc($t_nick) ?
            $quser->server : $pool->lookup_server_mask($t_server);
    }

    # no server parameter.
    else {
        $server = $me;
        $query  = $t_server;
        $quser  = $pool->lookup_user_nick($t_server);
    }

    # server exists?
    if (!$server) {
        $user->numeric(ERR_NOSUCHSERVER => $t_server);
        return;
    }

    # user exists?
    if (!$quser) {
        $user->numeric(ERR_NOSUCHNICK => $query);
        return;
    }

    # this does not apply to me; forward it.
    my $location = $server->{location};
    if ($location != $me) {
        $location->fire_command(whois => $user, $quser, $server);
        return 1;
    }

    # do the query.
    # NOTE: these handlers must not assume $quser to be local.
    $user->fire(whois_query => $quser);

    return 1;
}

# check for online users
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

# set away status
sub away {
    my ($user, $event, $reason) = @_;
    my $ok = $user->do_away($reason);

    # status 1 = set away, 2 = unset away
    broadcast(away        => $user) if $ok && $ok == 1;
    broadcast(return_away => $user) if $ok && $ok == 2;

    return 1;
}

# disconnect from the server
sub quit {
    my ($user, $event, $reason) = @_;
    $reason //= 'leaving';
    return $user->conn->done("~ $reason");
}

# leave a channel
sub part {
    my ($user, $event, $channel, $reason) = @_;

    # tell channel's users and servers.
    $channel->do_part($user, $reason);
    broadcast(part => $user, $channel, $reason);

    return 1;
}

# connect to a server
# remote-safe
sub _connect {
    my ($user, $event, $connect_mask, $port_maybe, $target_mask) = @_;

    # we don't support the port parameter,
    # but we need to ignore it if it was specified.
    if (!defined $target_mask) {
        $target_mask = $port_maybe;
    }

    # a target server was specified, so it must handle this request.
    if (length $target_mask) {
        my $target_server = $pool->lookup_server_mask($target_mask);

        # nothing matches.
        if (!$target_server) {
            $user->numeric(ERR_NOSUCHSERVER => $connect_mask);
            return;
        }

        # I am not supposed to handle this. forward it on.
        if ($target_server != $me) {

            # gotta have gconnect for a remote connect.
            if (!$user->has_flag('gconnect')) {
                $user->numeric(ERR_NOPRIVILEGES => 'gconnect');
                return;
            }

            $target_server->fire_command(
                connect => $user, $connect_mask, $target_server);
            return 1;
        }

    }

    # Safe point - we know we're handling the connect.

    # find connect blocks that match
    my @server_names = grep irc_match($_, $connect_mask),
        $conf->names_of_block('connect');

    # no servers match
    if (!@server_names) {

        # it's possible this server exists but there's no local connect block
        if (my $exists = $pool->lookup_server_mask($connect_mask)) {
            my $s_name = $exists->name;
            $user->server_notice(connect => "$s_name: Server exists");
            return;
        }

        $user->numeric(ERR_NOSUCHSERVER => $connect_mask);
        return;
    }

    # connect to first matching server
    foreach my $s_name (@server_names) {

        # instant error from linkage
        if (my $e = server::linkage::connect_server($s_name)) {
            $user->server_notice(connect => "$s_name: $e");
            next;
        }

        # OK, this one had no immediate error. we choose it!
        gnotice($user, connect => $user->notice_info, $me->name, $s_name);
        last;

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
# TODO: (#95) clean this up
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
          $quser->is_mode('invisible')             &&
          !$pool->channel_in_common($user, $quser) &&
          !$user->has_flag('see_invisible');

        # rfc2812:
        # If the "o" parameter is passed only operators are returned according
        # to the <mask> supplied.
        next if ($args[2] && index($args[2], 'o') != -1 && !$quser->is_mode('ircop'));

        # found a match
        $who_flags = (length $quser->{away}  ? 'G' : 'H') .
                     ($quser->is_mode('bot') ? 'B' : '' ) .
                     $who_flags . ($quser->is_mode('ircop') ? '*' : q||);
        $user->numeric(RPL_WHOREPLY =>
            $match_pattern, $quser->{ident}, $quser->{host}, $quser->{server}{name},
            $quser->{nick}, $who_flags, $user->hops_to($quser), $quser->{real}
        );
    }

    $user->numeric(RPL_ENDOFWHO => $query);
    return 1;
}

# view/set a channel topic
sub topic {
    my ($user, $event, $channel, $new_topic) = @_;

    # setting topic.
    if (length $new_topic) {
        my $can = (!$channel->is_mode('protect_topic')) ?
            1 : $channel->user_has_basic_status($user);

        # not permitted.
        if (!$can) {
            $user->numeric(ERR_CHANOPRIVSNEEDED => $channel->name);
            return;
        }

        # set the topic and broadcast it.
        my $time = time;
        # ($source, $topic, $setby, $time, $check_text)
        $channel->do_topic($user, $new_topic, $user->full, $time);
        broadcast(topic => $user, $channel, $time, $new_topic);

        return 1;
    }

    # viewing topic.
    my $topic = $channel->topic;

    # no topic set.
    if (!$topic) {
        $user->numeric(RPL_NOTOPIC => $channel->name);
        return;
    }

    $user->numeric(RPL_TOPIC        => $channel->name, $topic->{topic});
    $user->numeric(RPL_TOPICWHOTIME =>
        $channel->name, $topic->{setby}, $topic->{time});
    return 1;
}

# view detailed user statistics
# remote-safe
sub lusers {
    my ($user, $event, undef, $server) = @_;

    # this does not apply to me; forward it.
    if ($server && $server != $me) {
        $server->{location}->fire_command(lusers => $user, $server);
        return 1;
    }

    # get unknown count
    my $unknown = scalar grep !$_->{type}, $pool->connections;

    # get server count
    my $servers   = scalar $pool->servers;
    my $l_servers = scalar grep { $_->conn } $pool->servers;

    # get x users, x invisible, and total global
    my @real_users = $pool->real_users;
    my ($g_not_invisible, $g_invisible) = (0, 0);
    foreach my $user (@real_users) {
        $g_invisible++, next if $user->is_mode('invisible');
        $g_not_invisible++;
    }
    my $g_users = $g_not_invisible + $g_invisible;

    # get local users
    my $l_users = scalar grep $_->is_local, @real_users;

    # get connection count and max connection count
    my $conn     = v('connection_count');
    my $conn_max = v('max_connection_count');

    # get oper count and channel count
    my $opers = scalar grep $_->is_mode('ircop'), @real_users;
    my $chans = scalar $pool->channels;

    # get max global and max local
    my $m_global = v('max_global_user_count');
    my $m_local  = v('max_local_user_count');

    # send numerics
    $user->numeric(RPL_LUSERCLIENT   =>
        $g_not_invisible, $g_invisible, $servers);
    $user->numeric(RPL_LUSEROP       => $opers);
    $user->numeric(RPL_LUSERUNKNOWN  => $unknown);
    $user->numeric(RPL_LUSERCHANNELS => $chans);
    $user->numeric(RPL_LUSERME       => $l_users, $l_servers);
    $user->numeric(RPL_LOCALUSERS    =>
        $l_users, $m_local, $l_users, $m_local);
    $user->numeric(RPL_GLOBALUSERS   =>
        $g_users, $m_global, $g_users, $m_global);
    $user->numeric(RPL_STATSCONN     => $conn_max, $m_local, $conn);
}

# view user statistics
# remote-safe
sub users {
    my ($user, $event, $server) = @_;

    # this does not apply to me; forward it.
    if ($server && $server != $me) {
        $server->{location}->fire_command(users => $user, $server);
        return 1;
    }

    # get x users, x invisible, and total global
    my @real_users = $pool->real_users;
    my ($g_not_invisible, $g_invisible) = (0, 0);
    foreach my $user (@real_users) {
        $g_invisible++, next if $user->is_mode('invisible');
        $g_not_invisible++;
    }
    my $g_users = $g_not_invisible + $g_invisible;

    # get local users
    my $l_users = scalar grep $_->is_local, @real_users;

    # get max global and max local
    my $m_global = v('max_global_user_count');
    my $m_local  = v('max_local_user_count');

    $user->numeric(RPL_LOCALUSERS  =>
        $l_users, $m_local, $l_users, $m_local);
    $user->numeric(RPL_GLOBALUSERS =>
        $g_users, $m_global, $g_users, $m_global);
}

# rehash the configuration
# remote-safe
sub rehash {
    my ($user, $event, $server_mask_maybe) = @_;

    # server mask parameter
    if (length $server_mask_maybe) {
        my @servers = $pool->lookup_server_mask($server_mask_maybe);

        # no privs.
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
    return ircd::rehash($user);
}

# disconnect a user
sub _kill {
    my ($user, $event, $tuser, $reason) = @_;

    # make sure they have gkill flag
    if (!$tuser->is_local && !$user->has_flag('gkill')) {
        $user->numeric(ERR_NOPRIVILEGES => 'gkill');
        return;
    }

    # kill
    $tuser->get_killed_by($user, $reason);
    broadcast(kill => $user, $tuser, $reason);

    $user->server_notice('kill', "$$tuser{nick} has been killed");
    return 1;
}

# forcibly remove a user from a channel.
# KICK #channel1,#channel2 user1,user2 :reason
sub kick {
    # KICK             #channel        nickname :reason
    # dummy            channel(inchan) user     :(opt)
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
    my ($t_level, $s_level) = map $channel->user_get_highest_level($_),
        $t_user, $user;
    if ($t_level > $s_level) {
        $user->numeric(ERR_CHANOPRIVSNEEDED => $channel->name);
        return;
    }

    # determine the reason.
    $reason //= $user->{nick};

    # tell the local users of the channel.
    $channel->user_get_kicked($t_user, $user, $reason);

    # tell the other servers.
    broadcast(kick => $user, $channel, $t_user, $reason);

    return 1;
}

# view channel directory
sub list {
    my $user = shift;
    $user->numeric('RPL_LISTSTART');

    # send for each channel in no particular order.
    foreach my $channel ($pool->channels) {

        # this event can be stopped to prevent a channel from
        # being displayed in LIST.
        next if $channel->fire(show_in_list => $user)->stopper;

        # 322 RPL_LIST "<channel> <# visible> :<topic>"
        my $number_of_users = scalar $channel->users;
        $user->numeric(RPL_LIST =>
            $channel->name,
            scalar $channel->users,
            $channel->topic ? $channel->topic->{topic} : ''
        );
    }

    # TODO: (#27) implement list for specific channels.

    $user->numeric('RPL_LISTEND');
    return 1;
}

# view a channel mode list
# this will probably be removed soon
sub modelist {
    my ($user, $event, $channel, $list) = @_;

    # one-character list name indicates a channel mode.
    if (length $list == 1) {
        $list = $me->cmode_name($list);
        if (!defined $list) {
            $user->server_notice('No such mode');
            return;
        }
    }

    # no items in the list.
    my @items = $channel->list_elements($list);
    if (!@items) {
        $user->server_notice('The list is empty');
        return;
    }

    $user->server_notice(modelist => "$$channel{name} \2$list\2 list");

    foreach my $item (@items) {
        $item = $item->name
            if blessed $item && $item->can('name');
        $user->server_notice("| $item");
    }

    $user->server_notice(modelist => "End of \2$list\2 list");
    return 1;
}

# view IRCd version info
# remote-safe
sub version {
    my ($user, $event, $server) = @_;
    $server ||= $me;

    # if the server isn't me, forward it.
    if ($server != $me) {
        $server->{location}->fire_command(version => $user, $server);
        return 1;
    }

    $user->numeric(RPL_VERSION =>
        v('TNAME'),                 # ircd name and major version name
        $ircd::VERSION,             # current version
        $server->{name},            # server name
        $::VERSION,                 # version at start
        $ircd::VERSION              # current version
    );
    $user->numeric('RPL_ISUPPORT') if $user->is_local;
}

# disconnect an uplink
# remote-safe
sub squit {
    my ($user, $event, $squit_mask, $reason) =  @_;
    $reason //= 'SQUIT command';

    # find matching servers
    my @servers = $pool->lookup_server_mask($squit_mask);
    my $amnt = 0;

    # if there is a pending timer, cancel it.
    foreach my $server_name (keys %ircd::link_timers) {
        next unless irc_match($server_name, $squit_mask);
        if (server::linkage::cancel_connection($server_name)) {
            notice($user, connect_cancel => $user->notice_info, $server_name);
            $amnt++;
        }
    }

    # no connected servers match.
    if (!@servers) {
        $user->numeric(ERR_NOSUCHSERVER => $squit_mask) unless $amnt;
        return;
    }

    # disconnect from each matching server
    $amnt = 0;
    foreach my $server (@servers) {

        # it's me!
        if ($server == $me) {
            next if @servers != 1;
            $user->server_notice(squit => "Can't disconnect the local server");
            return;
        }

        # direct connection. use ->done().
        if (my $conn = $server->conn) {
            $conn->{dont_reconnect}++;
            $conn->done($reason);
        }

        # remote server. use ->quit().
        else {
            if (!$user->has_flag('gsquit')) {
                $user->numeric(ERR_NOPRIVILEGES => 'gsquit');
                next;
            }
            $server->quit($reason);
            broadcast(quit => $server, $reason, $user);
        }

        $amnt++;
        notice($user, squit =>
            $user->notice_info,
            $server->{name}, $server->{parent}{name}
        );
    }

    my $s = $amnt == 1 ? '' : 's';
    $user->server_notice(squit => "$amnt server$s disconnected");
    return 1;
}

# view server uplinks
# remote-safe
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

# do a PRIVMSG and send it back to the user
sub echo {
    my ($user, undef, $channel, $message) = @_;
    my $continue = $channel->do_privmsgnotice(PRIVMSG => $user, $message);
    $user->sendfrom($user->full, "PRIVMSG $$channel{name} :$message")
        if $continue;
}


# remote-safe
sub admin {
    my ($user, $event, $server) = @_;

    # this does not apply to me; forward it.
    if ($server && $server != $me) {
        $server->{location}->fire_command(admin => $user, $server);
        return 1;
    }


    # note: the RFC says RPL_ADMINME should send <server> :<info>, but most
    # IRCds (including charybdis) only send the <info> parameter with the server
    # name in it, so we will too.

    $user->numeric(RPL_ADMINME    => $me->name             );
    $user->numeric(RPL_ADMINLOC1  => conf('admin', 'line1'));
    $user->numeric(RPL_ADMINLOC2  => conf('admin', 'line2'));
    $user->numeric(RPL_ADMINEMAIL => conf('admin', 'email'));

    return 1;
}

# view server time
# remote-safe
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

# user hostmask query
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

# check connection status
sub ping {
    my ($user, $event, $given) = @_;
    $user->sendme("PONG $$me{name} :$given");
}

$mod
