# Copyright (c) 2009-13, Mitchell Cooper
package API::Module::Core::UserCommands;
 
use warnings;
use strict;

use Scalar::Util qw(blessed);

use utils qw(col log2 lceq lconf match cut_to_limit conf v);

our $VERSION = $API::Module::Core::VERSION;

my %ucommands = (
    PING => {
        params => 1,
        code   => \&ping,
        desc   => 'ping the server'
    },
    USER => {
        code   => \&fake_user,
        desc   => 'fake user command'
    },
    MOTD => {
        code   => \&motd,
        desc   => 'display the message of the day'
    },
    NICK => {
        params => 1,
        code   => \&nick,
        desc   => 'change your nickname'
    },
    PONG => {
        code   => sub { },
        desc   => 'reply to a ping'
    },
    INFO => {
        code   => \&info,
        desc   => 'display ircd license and credits'
    },
    MODE => {
        params => 1,
        code   => \&mode,
        desc   => 'view or change user and channel modes',
        fntsy  => 1
    },
    PRIVMSG => {
        params => 2,
        code   => \&privmsgnotice,
        desc   => 'send a message to a user or channel'
    },
    NOTICE => {
        params => 2,
        code   => \&privmsgnotice,
        desc   => 'send a notice to a user or channel'
    },
    MAP => {
        code   => \&cmap,
        desc   => 'view a list of servers connected to the network'
    },
    JOIN => {
        params => 1,
        code   => \&cjoin,
        desc   => 'join a channel'
    },
    NAMES => {
        params => 1,
        code   => \&names,
        desc   => 'view the user list of a channel',
        fntsy  => 1
    },
    OPER => {
        params => 2,
        code   => \&oper,
        desc   => 'gain privileges of an IRC operator'

    },
    WHOIS => {
        params => 1,
        code   => \&whois,
        desc   => 'display information on a user'
    },
    ISON => {
        params => 1,
        code   => \&ison,
        desc   => 'check if users are online'
    },
    COMMANDS => {
        code   => \&commands,
        desc   => 'view a list of available commands'
    },
    AWAY => {
        code   => \&away,
        desc   => 'mark yourself as away or return from being away'
    },
    QUIT => {
        code   => \&quit,
        desc   => 'disconnect from the server'
    },
    PART => {
        params => 1,
        code   => \&part,
        desc   => 'leave a channel',
        fntsy  => 1
    },
    CONNECT => {
        params => '-oper(connect) any',
        code   => \&sconnect,
        desc   => 'connect to a server'
    },
    WHO => {
        params => 1,
        code   => \&who,
        desc   => 'familiarize your client with users matching a pattern',
        fntsy  => 1
    },
    TOPIC => {
        params => 1,
        code   => \&topic,
        desc   => 'view or set the topic of a channel',
        fntsy  => 1
    },
    LUSERS => {
        code   => \&lusers,
        desc   => 'view connection count statistics'
    },
    MODLOAD => {
        code   => \&modload,
        desc   => 'load an IRCd extension',
        params => '-oper(modules) any'
    },
    MODUNLOAD => {
        code   => \&modunload,
        desc   => 'unload an IRCd extension',
        params => '-oper(modules) any'
    },
    MODRELOAD => {
        code   => \&modreload,
        desc   => 'reload an IRCd extension',
        params => '-oper(modules) any'
    },
    REHASH => {
        code   => \&rehash,
        desc   => 'reload the server configuration',
        params => '-oper(rehash)'
    },
    KILL => {
        code   => \&ukill,
        desc   => 'forcibly remove a user from the server',
        params => 'user :rest' # oper flags handled later
    },
    MODULES => {
        code   => \&modules,
        desc   => 'view loaded IRCd modules'
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
        params => 'channel(inchan) any',
        fntsy  => 1
    },
    EVAL => {
        code   => \&seval,
        desc   => 'evaluate a line of Perl code',
        params => '-oper(eval) :rest'
    },
    VERSION => {
        code   => \&version,
        desc   => 'view server version information',
        params => 'server(opt)'
    },
    SQUIT => {
        code   => \&squit,
        desc   => 'disconnect a server',
        params => '-oper(squit) server'
    }
);

our $mod = API::Module->new(
    name        => 'UserCommands',
    version     => $VERSION,
    description => 'the core set of user commands',
    requires    => ['UserCommands'],
    initialize  => \&init
);

my $me = v('SERVER');

sub init {

    # register user commands
    $mod->register_user_command(
        name        => $_,
        description => $ucommands{$_}{desc},
        parameters  => $ucommands{$_}{params},
        code        => $ucommands{$_}{code},
        fantasy     => $ucommands{$_}{fntsy}
    ) || return foreach keys %ucommands;

    undef %ucommands;

    return 1
}


# handlers

sub ping {
    my ($user, $data, @s) = @_;
    $user->sendme('PONG '.v('SERVER', 'name').' :'.col($s[1]))
}

sub fake_user {
    my $user = shift;
    $user->numeric('ERR_ALREADYREGISTRED');
}

sub motd {
    # TODO: <server> parameter
    my $user = shift;
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
    $user->numeric('RPL_MOTDSTART', v('SERVER', 'name'));
    $user->numeric('RPL_MOTD', $_) foreach @motd_lines;
    $user->numeric('RPL_ENDOFMOTD');
    
    return 1
}

# change nickname
sub nick {
    my ($user, $data, @args) = @_;
    my $newnick = col($args[1]);
    my $me      = lc $user->{nick} eq lc $newnick;

    if ($newnick eq '0') {
        $newnick = $user->{uid};
    }
    else {
    
        # check for valid nick
        if (!utils::validnick($newnick)) {
            $user->numeric('ERR_ERRONEUSNICKNAME', $newnick);
            return;
        }

        # check for existing nick
        my $in_use = $::pool->lookup_user_nick($newnick);
        if ($in_use && $in_use != $user) {
            $user->numeric('ERR_NICKNAMEINUSE', $newnick);
            return;
        }
        
    }

    # ignore stupid nick changes
    return if $user->{nick} eq $newnick;

    # tell ppl
    $user->send_to_channels("NICK $newnick");

    # change it
    $user->change_nick($newnick);
    $::pool->fire_command_all(nickchange => $user);
}

sub info {
    my ($NAME, $VERSION) = (v('LNAME'), v('VERSION'));
    my $user = shift;
    my $info = <<"END";

\2***\2 this is \2$NAME\2 version \2$VERSION\2.\2 ***\2
 
Copyright (c) 2010-14, the $NAME developers
 
This program is free software.
You are free to modify and redistribute it under the terms of
the three-clause "New" BSD license (see LICENSE in source.)
 
$NAME wouldn't be here if it weren't for the people who have
contributed time, effort, love, and care to the project.
 
\2Developers\2
    Mitchell Cooper, \"cooper\" <mitchell\@notroll.net> https://github.com/cooper
    Kyle Paranoid, \"mac-mini\" <mac-mini\@mac-mini.org> https://github.com/mac-mini
    Daniel Leining, \"daniel\" <daniel\@the-beach.co> https://github.com/blasphemy
    Hakkin Lain, \"Hakkin\" <hakkin\@notroll.net> https://github.com/hakkin
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
    my ($user, $data, @args) = @_;

    # is it the user himself?
    if (lceq $user->{nick} => $args[1]) {

        # mode change
        if (defined $args[2]) {
            $user->do_mode_string($args[2]);
            return 1;
        }

        # mode view
        else {
            $user->numeric('RPL_UMODEIS', $user->mode_string);
            return 1;
        }
    }

    # is it a channel, then?
    if (my $channel = $::pool->lookup_channel($args[1])) {

        # viewing
        if (!defined $args[2]) {
            $channel->modes($user);
            return 1;
        }

        # setting
        my $modestr = join ' ', @args[2..$#args];
        $channel->do_mode_string($user->{server}, $user, $modestr);
        return 1;
        
    }

    # hmm.. maybe it's another user
    if ($::pool->lookup_user_nick($args[1])) {
        $user->numeric('ERR_USERSDONTMATCH');
        return
    }

    # no such nick/channel
    $user->numeric('ERR_NOSUCHNICK', $args[1]);
    return
}

sub privmsgnotice {
    my ($user, $data, @args) = @_;

    # we can't  use @args because it splits by whitespace
    $data       =~ s/^:(.+)\s//;
    my @m       = split ' ', $data, 3;
    my $message = col($m[2]);
    my $command = uc $m[0];

    # no text to send
    if ($message eq '') {
        $user->numeric('ERR_NOTEXTTOSEND');
        return
    }

    # is it a user?
    my $tuser = $::pool->lookup_user_nick($args[1]);
    if ($tuser) {

        # TODO here check for user modes preventing
        # the user from sending the message

        # tell them of away if set
        if ($command eq 'PRIVMSG' && exists $user->{away}) {
            $user->numeric('RPL_AWAY', $tuser->{nick}, $tuser->{away});
        }

        # if it's a local user, send it to them
        if ($tuser->is_local) {
            $tuser->sendfrom($user->full, "$command $$tuser{nick} :$message");
        }

        # send it to the server holding this user
        else {
            $tuser->{location}->fire_command(privmsgnotice => $command, $user, $tuser, $message);
        }
        return 1;
    }

    # must be a channel
    my $channel = $::pool->lookup_channel($args[1]);
    if ($channel) {
        $channel->handle_privmsgnotice($command, $user, $message);
        return 1;
    }

    # no such nick/channel
    $user->numeric('ERR_NOSUCHNICK', $args[1]);
    return;
    
}

sub cmap {
    # TODO: this will be much prettier later!
    my $user  = shift;
    my $total = scalar $::pool->users;
    my $users = scalar grep { $_->{server} == $me } $::pool->users;
    my $per   = int $users / $total * 100;

    $user->numeric('RPL_MAP', "- \2$$me{sid}\2 $$me{name} ($$me{ircd}): $users [$per\%]");

    my $avg;
    foreach my $server ($::pool->servers) {
        next if $server == $me;
        $users = scalar grep { $_->{server} == $server } $::pool->users;
        $per   = int $users / $total * 100;
        $avg  += $users;
        $user->numeric('RPL_MAP', "    - \2$$server{sid}\2 $$server{name} ($$server{ircd}): $users [$per\%]");
    }

    my @servers = $::pool->servers;
    my $average = int($avg / scalar @servers + 0.5);
    
    $user->numeric('RPL_MAP', "- Total of $total users, average $average users per server");
    $user->numeric('RPL_MAPEND');
}

sub cjoin {
    my ($user, $data, @args) = @_;
    foreach my $chname (split ',', $args[1]) {
        my $new = 0;

        # make sure it's a valid name
        if (!utils::validchan($chname)) {
            $user->numeric('ERR_NOSUCHCHANNEL', $chname);
            next
        }

        # if the channel exists, just join
        my $channel = $::pool->lookup_channel($chname);
        my $time    = time;

        # otherwise create a new one
        if (!$channel) {
            $new     = 1;
            $channel = $::pool->new_channel(
                name   => $chname,
                'time' => $time
            );
        }

        return if $channel->has_user($user);
        my $sstr;

        # check for ban.
        my $banned = $channel->list_matches('ban',    $user);
        my $exempt = $channel->list_matches('except', $user);
        
        # yep, banned.
        if ($banned && !$exempt) {
            $user->numeric('ERR_BANNEDFROMCHAN', $channel->{name});
            return
        }

        # new channel. join internally (without telling the user) & set auto modes.
        # note: we can't use do_mode_string() here because CMODE must come after SJOIN.
        if ($new) {
            $channel->cjoin($user, $time); # early join
            my $str = conf('channels', 'automodes') || '';
            $str =~ s/\+user/$$user{uid}/g;
            (undef, $sstr) = $channel->handle_mode_string($me, $me, $str, 1, 1);
        }

        # tell servers that the user joined and the automatic modes were set.
        $::pool->fire_command_all(sjoin => $user, $channel, $time);
        $::pool->fire_command_all(cmode => $me, $channel, $time, $me->{sid}, $sstr) if $sstr;

        # do the actual local join.
        $channel->localjoin($user, $time, 1);
        
    }
}

sub names {
    my ($user, $data, @args) = @_;
    foreach my $chname (split ',', $args[1]) {
        # nonexistent channels return no error,
        # and RPL_ENDOFNAMES is sent no matter what
        my $channel = $::pool->lookup_channel($chname);
        $channel->names($user) if $channel;
        $user->numeric('RPL_ENDOFNAMES', $channel ? $channel->{name} : $chname);
    }
}

sub oper {
    my ($user, $data, @args) = @_;
    my $password = lconf('oper', $args[1], 'password');
    my $supplied = $args[2];

    # no password?!
    if (not defined $password) {
        $user->numeric('ERR_NOOPERHOST');
        return
    }

    # if they have specific addresses specified, make sure they match

    if (defined( my $addr = lconf('oper', $args[1], 'host') )) {
        my $win = 0;

        # a reference of several addresses
        if (ref $addr eq 'ARRAY') {
            match: foreach my $host (@$addr) {
                if (match($user, $host)) {
                    $win = 1;
                    last match
                }
            }
        }

        # must just be a string of 1 address
        else {
            if (match($user, $addr)) {
                $win = 1
            }
        }

        # nothing matched :(
        if (!$win) {
            $user->numeric('ERR_NOOPERHOST');
            return
        }
    }

    my $crypt = lconf('oper', $args[1], 'encryption');

    # so now let's check if the password is right
    $supplied = utils::crypt($supplied, $crypt);

    # incorrect
    if ($supplied ne $password) {
        $user->numeric('ERR_NOOPERHOST');
        return
    }

    # or keep going!
    # let's find all of their oper flags now

    my @flags;

    # flags in their oper block
    if (defined ( my $flagref = lconf('oper', $args[1], 'flags') )) {
        if (ref $flagref ne 'ARRAY') {
            log2("'flags' specified for oper block $args[1], but it is not an array reference.");
        }
        else {
            push @flags, @$flagref
        }
    }

    # flags in their oper class block
    my $add_class = sub {
        my $add_class = shift;
        my $operclass = shift;

        # if it has flags, add them
        if (defined ( my $flagref = lconf('operclass', $operclass, 'flags') )) {
            if (ref $flagref ne 'ARRAY') {
                log2("'flags' specified for oper class block $operclass, but it is not an array reference.");
            }
            else {
                push @flags, @$flagref
            }
        }

        # add parent too
        if (defined ( my $parent = lconf('operclass', $operclass, 'extends') )) {
            $add_class->($add_class, $parent);
        }
    };

    if (defined ( my $operclass = lconf('oper', $args[1], 'class') )) {
        $add_class->($add_class, $operclass);
    }

    my %h = map { $_ => 1 } @flags;
    @flags = keys %h; # should remove duplicates
    $user->add_flags(@flags);
    $::pool->fire_command_all(oper => $user, @flags);

    # okay, we should have a complete list of flags now.
    log2("$$user{nick}!$$user{ident}\@$$user{host} has opered as $args[1] and was granted flags: @flags");
    $user->server_notice('You now have flags: '.join(' ', @{ $user->{flags} }));

    # set ircop, send MODE to the user, and tell other servers.
    $user->do_mode_string('+'.$user->{server}->umode_letter('ircop'), 1);
    
    $user->numeric('RPL_YOUREOPER');
    return 1;
}

sub whois {

    my ($user, $data, @args) = @_;

    # this is the way inspircd does it so I can too
    my $query = $args[2] ? $args[2] : $args[1];
    my $quser = $::pool->lookup_user_nick($query);

    # exists?
    if (!$quser) {
        $user->numeric('ERR_NOSUCHNICK', $query);
        return
    }

    # nick, ident, host
    $user->numeric('RPL_WHOISUSER', $quser->{nick}, $quser->{ident}, $quser->{host}, $quser->{real});

    # channels
    my @channels = map { $_->{name} } grep { $_->has_user($quser) } $::pool->channels;
    $user->numeric('RPL_WHOISCHANNELS', $quser->{nick}, join(' ', @channels)) if @channels;

    # server 
    $user->numeric('RPL_WHOISSERVER', $quser->{nick}, $quser->{server}{name}, $quser->{server}{desc});

    # IRC operator
    $user->numeric('RPL_WHOISOPERATOR', $quser->{nick}) if $quser->is_mode('ircop');

    # is away
    $user->numeric('RPL_AWAY', $quser->{nick}, $quser->{away}) if exists $quser->{away};

    # using modes
    my $modes = $quser->mode_string;
    $user->numeric('RPL_WHOISMODES', $quser->{nick}, $modes) if $modes && $modes ne '+';

    # connecting from
    $user->numeric('RPL_WHOISHOST', $quser->{nick}, $quser->{host}, $quser->{ip});

    # TODO 137 idle

    $user->numeric('RPL_ENDOFWHOIS', $quser->{nick});
    return 1
}

sub ison {
    my ($user, $data, @args) = @_;
    my @found;

    # for each nick, lookup and add if exists
    foreach my $nick (@args[1..$#args]) {
        my $user = $::pool->lookup_user_nick(col($nick));
        push @found, $user->{nick} if $user;
    }

    $user->numeric('RPL_ISON', join(' ', @found));
}

sub commands {
    my $user = shift;

    # get the width
    my $i = 0;
    foreach my $command (keys %user::mine::commands) {
        $i = length $command if length $command > $i
    }

    $i++;
    $user->server_notice('*** List of available commands');

    # send a notice for each command
    foreach my $command (keys %user::mine::commands) {
        foreach my $source (keys %{ $user::mine::commands{$command} }) {
            $user->server_notice(sprintf "\2%-${i}s\2 %-${i}s", $command,
                q(:).$user::mine::commands{$command}{$source}{desc}, $source)
        }
    }

    $user->server_notice('*** End of command list');

}

sub away {
    my ($user, $data, @args) = @_;

    # setting away
    if (defined $args[1]) {
        my $reason = cut_to_limit('away', col((split /\s+/, $data, 2)[1]));
        $user->set_away($reason);
        $::pool->fire_command_all(away => $user);
        $user->numeric('RPL_NOWAWAY');
        return 1
    }

    # unsetting
    return unless exists $user->{away};
    $user->unset_away;
    $::pool->fire_command_all(return_away => $user);
    $user->numeric('RPL_UNAWAY');
}

sub quit {
    my ($user, $data, @args) = @_;
    my $reason = 'leaving';

    # get the reason if they specified one
    if (defined $args[1]) {
        $reason = col((split /\s+/,  $data, 2)[1])
    }

    $user->{conn}->done("~ $reason");
}

sub part {
    my ($user, $data, @args) = @_;
    my @m = split /\s+/, $data, 3;
    my $reason = defined $args[2] ? col($m[2]) : q();

    foreach my $chname (split ',', $args[1]) {
        my $channel = $::pool->lookup_channel($chname);

        # channel doesn't exist
        if (!$channel) {
            $user->numeric('ERR_NOSUCHCHANNEL', $chname);
            return
        }

        # user isn't on channel
        if (!$channel->has_user($user)) {
            $user->numeric('ERR_NOTONCHANNEL', $channel->{name});
            return
        }

        # remove the user and tell the other channel's users and servers
        my $ureason = defined $reason ? " :$reason" : q();
        $channel->sendfrom_all($user->full, " PART $$channel{name}$ureason");
        $::pool->fire_command_all(part => $user, $channel, $channel->{time}, $reason);
        $channel->remove($user);

    }
}

sub sconnect {
    my ($user, $data, $sname) = @_;

    # make sure the server exists
    if (!$ircd::conf->has_block(['connect', $sname])) {
        $user->server_notice('CONNECT', 'no such server '.$sname);
        return;
    }

    # make sure it's not already connected
    if ($::pool->lookup_server_name($sname)) {
        $user->server_notice('CONNECT', "$sname is already connected.");
        return;
    }

    if (!server::linkage::connect_server($sname)) {
        $user->server_notice('CONNECT', 'couldn\'t connect to '.$sname);
    }
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
    my ($user, $data, @args) = @_;
    my $query                = $args[1];
    my $match_pattern        = '*';
    my %matches;

    # match all, like the above note says
    if ($query eq '0') {
        foreach my $quser ($::pool->users) {
            $matches{ $quser->{uid} } = $quser
        }
        # I used UIDs so there are no duplicates
    }

    # match an exact channel name
    elsif (my $channel = $::pool->lookup_channel($query)) {
        $match_pattern = $channel->{name};
        foreach my $quser (@{ $channel->{users} }) {
            $matches{ $quser->{uid} } = $quser;
            $quser->{who_flags}       = $channel->prefix($quser);
        }
    }

    # match a pattern
    else {
        foreach my $quser ($::pool->users) {
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
          !$::pool->channel_in_common($user, $quser) &&
          !$user->has_flag('see_invisible');

        # rfc2812:
        # If the "o" parameter is passed only operators are returned according
        # to the <mask> supplied.
        next if (defined $args[2] && $args[2] =~ m/o/ && !$quser->is_mode('ircop'));

        # found a match
        $who_flags = (defined $quser->{away} ? 'G' : 'H') . $who_flags . ($quser->is_mode('ircop') ? '*' : q||);
        $user->numeric('RPL_WHOREPLY', $match_pattern, $quser->{ident}, $quser->{host}, $quser->{server}{name}, $quser->{nick}, $who_flags, $quser->{real});
    }

    $user->numeric('RPL_ENDOFWHO', $query);
    return 1
}

sub topic {
    my ($user, $data, @args) = @_;
    $args[1] =~ s/,(.*)//; # XXX: comma separated list won't work here!
    my $channel = $::pool->lookup_channel($args[1]);

    # existent channel?
    if (!$channel) {
        $user->numeric(ERR_NOSUCHCHANNEL => $args[1]);
        return
    }

    # setting topic
    if (defined $args[2]) {
        my $can = (!$channel->is_mode('protect_topic')) ? 1 : $channel->user_has_basic_status($user) ? 1 : 0;

        # not permitted
        if (!$can) {
            $user->numeric(ERR_CHANOPRIVSNEEDED => $channel->{name});
            return
        }

        my $topic = cut_to_limit('topic', col((split /\s+/, $data, 3)[2]));
        $channel->sendfrom_all($user->full, " TOPIC $$channel{name} :$topic");
        $::pool->fire_command_all(topic => $user, $channel, time, $topic);

        # set it
        if (length $topic) {
            $channel->{topic} = {
                setby => $user->full,
                time  => time,
                topic => $topic
            };
        }
        else {
            delete $channel->{topic}
        }

    }

    # viewing topic
    else {

        # topic set
        my $topic = $channel->topic;
        if ($topic) {
            $user->numeric(RPL_TOPIC        => $channel->{name}, $topic->{topic});
            $user->numeric(RPL_TOPICWHOTIME => $channel->{name}, $topic->{setby}, $topic->{time});
        }

        # no topic set
        else {
            $user->numeric(RPL_NOTOPIC => $channel->{name});
            return
        }
    }

    return 1
}

sub lusers {
    my ($user, $data, @args) = @_;

    # get server count
    my $servers   = scalar keys %server::server;
    my $l_servers = scalar grep { $_->is_local } $::pool->servers;

    # get x users, x invisible, and total global
    my ($g_not_invisible, $g_invisible) = (0, 0);
    foreach my $user ($::pool->users) {
        $g_invisible++, next if $user->is_mode('invisible');
        $g_not_invisible++
    }
    my $g_users = $g_not_invisible + $g_invisible;

    # get local users
    my $l_users  = scalar grep { $_->is_local } $::pool->users;

    # get connection count and max connection count
    my $conn     = v('connection_count');
    my $conn_max = v('max_connection_count');

    # get oper count and channel count
    my $opers = scalar grep { $_->is_mode('ircop') } $::pool->users;
    my $chans = scalar keys %channel::channel;

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

sub modload {
    my ($user, $data, $mod_name) = @_;
    $user->server_notice("Loading module \2$mod_name\2.");

    # attempt.
    my $result = $::API->load_module($mod_name, "$mod_name.pm");

    # failure.
    if (!$result) {
        $user->server_notice('Module failed to load. See server log for information.');
        return;
    }

    # success.
    else {
        $user->server_notice('Module loaded successfully.');
        return 1;
    }
    
}

sub modunload {
    my ($user, $data, $mod_name) = @_;
    $user->server_notice("Unloading module \2$mod_name\2.");

    # attempt.
    my $result = $::API->unload_module($mod_name, "$mod_name.pm");
    
    # failure.
    if (!$result) {
        $user->server_notice('Module failed to unload. See server log for information.');
        return;
    }

    # success.
    else {
        $user->server_notice('Module unloaded successfully.');
        return 1;
    }
    
}

sub modreload {
    my ($user, $data, $mod_name) = @_;
    $user->server_notice("Reloading module \2$mod_name\2.");
    
    # simply handle the other two commands.
    my $modload = \&modload;
    modunload ($user, undef, $mod_name) or return;
    $modload->($user, undef, $mod_name) or return;
    
    return 1;
}

sub rehash {
    my $user = shift;

    # rehash.
    $user->numeric(RPL_REHASHING => $::conf->{conffile});
    if ($::conf->parse_config) {
        $user->server_notice('rehash', 'Configuration loaded successfully');
        return 1;
    }

    # error.
    $user->server_notice('rehash', 'There was an error parsing the configuration');
    return;
    
}

sub ukill {
    my ($user, $data, $tuser, $reason) = @_;

    # local user.
    if ($tuser->is_local) {

        # make sure they have kill flag
        if (!$user->has_flag('kill')) {
            $user->numeric(ERR_NOPRIVILEGES => 'kill');
            return;
        }

        $tuser->{conn}->done("Killed by $$user{nick}: $reason");
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

        $tuser->{location}->fire_command(kill => $user, $tuser, $reason);
    }

    $user->server_notice('kill', "$$tuser{nick} has been killed");
    return 1
}

sub modules {
    my $user = shift;
    $user->server_notice(modules => 'Loaded IRCd modules list');
    
    # code for each module.
    my (%done, $code);
    $code = sub {
        my $_mod = shift;
        $code->($_mod->{parent}) if $_mod->{parent};

        # did this already.
        my $name = $_mod->full_name;
        return if $done{$name};
        
        $user->server_notice("\2$name\2 $$_mod{version}");
        $user->server_notice("    $$_mod{description}");
        foreach my $type (qw|
            user_commands server_commands channel_modes user_modes
            outgoing_commands user_numerics matchers
        |) {
        
            # find items in this category.
            next unless $_mod->{$type};
            my @a = @{ $_mod->{$type} } or next;
            
            # transform those into a human-readable form.
            my $mytype = $type;
            $mytype =~ s/_/ /g;
            $mytype = ucfirst $mytype;
            
            # only allow 50 bytes per line.
            $user->server_notice("    $mytype");
            while (@a) {
                my ($line, @b) = '';
                while (@a) {
                    push @b, my $c = lc shift @a;
                    my $line_maybe = '            - '.join(', ', @b);
                    last if length $line_maybe >= 60;
                    $line = $line_maybe;
                }
                $user->server_notice($line);
            }
            
        }
        
        $done{$name} = 1;
    };
    
    # do the core modules first.
    $code->($mod->{parent});
    $code->($_) foreach
        sort { $a->full_name cmp $b->full_name }
        grep { $_->{parent} && $_->{parent} == $mod->{parent} }
        @{ $::API->{loaded} };
    
    # do each other module.
    $code->($_) foreach
        sort { $a->full_name cmp $b->full_name }
        @{ $::API->{loaded} };
    
    $user->server_notice(modules => 'End of IRCd modules list');
    return 1
}

# forcibly remove a user from a channel.
# KICK #channel1,#channel2 user1,user2 :reason
sub kick {
    # KICK            #channel        nickname :reason
    # dummy           channel(inchan) user     :rest(opt)
    my ($user, $data, $channel,       $t_user, $reason) = @_;
    
    # check if the user has basic status in the channel.
    if (!$channel->user_has_basic_status($user)) {
        $user->numeric(ERR_CHANOPRIVSNEEDED => $channel->{name});
        return;
    }
    
    # if the user has a lower status level than the target, he can't kick him.
    if ($channel->user_get_highest_level($t_user) > $channel->user_get_highest_level($user)) {
        $user->numeric(ERR_CHANOPRIVSNEEDED => $channel->{name});
        return;
    }
    
    # determine the reason.
    my $reason_string = defined $reason ? $reason : $user->{nick};
    
    # tell the local users of the channel.
    $channel->sendfrom_all($user->full, " KICK $$channel{name} $$t_user{nick} :$reason_string");
    
    # remove the user from the channel.
    $channel->remove_user($t_user);

    # tell the other servers.
    $::pool->fire_command_all(kick => $user, $channel, $t_user, $reason_string);

    return 1;
}

sub list {
    my $user = shift;
    
    #:ashburn.va.mac-mini.org 321 k Channel :Users  Name
    $user->numeric('RPL_LISTSTART');

    # send for each channel in no particular order.
    foreach my $channel ($::pool->channels) {
       # 322 RPL_LIST "<channel> <# visible> :<topic>"
        my $number_of_users = scalar @{ $channel->{users} };
        my $channel_topic   = $channel->topic ? $channel->topic->{topic} : '';
        $user->numeric(RPL_LIST => $channel->{name}, $number_of_users, $channel_topic);
    }

    # TODO: implement list for specific channels.
    # TODO: +s and +p
    
    $user->numeric('RPL_LISTEND');
    return 1;
}

sub modelist {
    my ($user, $data, $channel, $list) = @_;
    
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

sub seval {
    my ($user, $data, $code) = @_;
    
    # evaluate.
    my $result = eval $code;

    # send the result to the user.
    my $i = 0;
    $user->server_notice($i++ ? "eval ($i)" : 'eval', $_)
      foreach split "\n", $result // ($@ || "\2undef\2");
    
    return 1;
}

sub version {
    my ($user, $data, $server) = (shift, shift, shift || $me);
    $user->numeric(RPL_VERSION =>
        v('NAME'),               # all
        $ircd::VERSION,          # of
        $server->{name},         # this
        $::VERSION,          # is
        $ircd::VERSION,          # wrong for nonlocal servers.
        $VERSION                 # TODO: send this info over protocol.
    );
    $user->numeric('RPL_ISUPPORT') if $server->is_local;
}

sub squit {
    my ($user, $data, $server) =  @_;
    
    # no direct connection. might be local server or a
    # psuedoserver or a server reached through another server.
    if (!$server->{conn}) {
        $user->server_notice('squit', 'server is not connected');
        return;
    }
    
    $server->{conn}->done('SQUIT command');
    $user->server_notice('squit', "$$server{name} disconnected");
}

$mod
