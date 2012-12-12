# Copyright (c) 2012, Mitchell Cooper
package ext::core_scommands;
 
use warnings;
use strict;
 
use utils qw(col log2 lceq lconf match cut_to_limit conf gv);

my %scommands = (
    SID => {
        params  => [qw(server dummy any ts any any any :rest)],
        code    => \&sid,
        forward => 1
    },
    UID => {
        params  => [qw(server dummy any ts any any any any any any :rest)],
        code    => \&uid,
        forward => 1
    },
    QUIT => {
        params  => [qw(source dummy :rest)],
        code    => \&quit,
        forward => 1
    },
    NICK => {
        params  => [qw(user dummy any)],
        code    => \&nick,
        forward => 1
    },
    BURST => {
        params  => [qw(server)],
        code    => \&burst,
        forward => 1
    },
    ENDBURST => {
        params  => [qw(server)],
        code    => \&endburst,
        forward => 1
    },
    ADDUMODE => {
        params  => [qw(server dummy any any)],
        code    => \&addumode,
        forward => 1
    },
    UMODE => {
        params  => [qw(user dummy any)],
        code    => \&umode,
        forward => 1
    },
    PRIVMSG => {
        params  => [qw(source any any :rest)],
        code    => \&privmsgnotice,
        forward => 0 # we have to do this manually
    },
    NOTICE => {
        params  => [qw(source any any :rest)],
        code    => \&privmsgnotice,
        forward => 0 # we have to do this manually
    },
    JOIN => {
        params  => [qw(user dummy any ts)],
        code    => \&sjoin,
        forward => 1
    },
    OPER => {
        params  => [qw(user dummy @rest)],
        code    => \&oper,
        forward => 1
    },
    AWAY => {
        params  => [qw(user dummy :rest)],
        code    => \&away,
        forward => 1
    },
    RETURN => {
        params  => [qw(user)],
        code    => \&return_away,
        forward => 1
    },
    ADDCMODE => {
        params  => [qw(server dummy any any any)],
        code    => \&addcmode,
        forward => 1
    },
    CMODE => {
        params  => [qw(source dummy channel ts server :rest)],
        code    => \&cmode,
        forward => 1
    },
    PART => {
        params  => [qw(user dummy channel ts :rest)],
        code    => \&part,
        forward => 1
    },
    TOPIC => {
        params  => [qw(source dummy channel ts ts :rest)],
        code    => \&topic,
        forward => 1
    },
    TOPICBURST => {
        params  => [qw(source dummy channel ts any ts :rest)],
        code    => \&topicburst,
        forward => 1
    },
    KILL => {
        params  => [qw(user dummy user :rest)],
        code    => \&skill,
        forward => 1
    },
    
    # compact

    AUM => {
        params  => [qw(server dummy @rest)],
        code    => \&aum,
        forward => 1
    },
    ACM => {
        params  => [qw(server dummy @rest)],
        code    => \&acm,
        forward => 1
    },
    CUM => {
        params  => [qw(server dummy any ts any :rest)],
        code    => \&cum,
        forward => 1
    }
);

our $mod = API::Module->new(
    name        => 'core_scommands',
    version     => '1.0',
    description => 'the core set of server commands',
    requires    => ['server_commands'],
    initialize  => \&init
);
 
sub init {

    # register server commands
    $mod->register_server_command(
        name       => $_,
        parameters => $scommands{$_}{params}  || undef,
        code       => $scommands{$_}{code},
        forward    => $scommands{$_}{forward}
    ) || return foreach keys %scommands;

    undef %scommands;

    return 1
}

###################
# SERVER COMMANDS #
###################

sub sid {
    # server dummy any    ts any  any   any  :rest
    # :sid   SID   newsid ts name proto ircd :desc
    my ($server, $data, @args) = @_;

    my $ref        = {};
    $ref->{$_}     = shift @args foreach qw[parent sid time name proto ircd desc];
    $ref->{source} = $server->{sid};

    # do not allow SID or server name collisions
    if (server::lookup_by_id($ref->{sid}) || server::lookup_by_name($ref->{name})) {
        log2("duplicate SID $$ref{sid} or server name $$ref{name}; dropping $$server{name}");
        $server->{conn}->done('attempted to introduce existing server');
        return
    }

    # create a new server
    my $serv = server->new($ref);
    return 1
}

sub uid {
    # server dummy any ts any   any  any   any  any   any :rest
    # :sid   UID   uid ts modes nick ident host cloak ip  :realname
    my ($server, $data, @args) = @_;

    my $ref          = {};
    $ref->{$_}       = shift @args foreach qw[server uid time modes nick ident host cloak ip real];
    $ref->{source}   = $server->{sid};
    $ref->{location} = $server;

    # uid collision?
    if (user::lookup_by_id($ref->{uid})) {
        # can't tolerate this.
        # the server is either not a juno server or is bugged/mentally unstable.
        log2("duplicate UID $$ref{uid}; dropping $$server{name}");
        $server->{conn}->done('UID collision') if exists $server->{conn};
    }

    # nick collision?
    my $used = user::lookup_by_nick($ref->{nick});
    if ($used) {
        log2("nick collision! $$ref{nick}");
        if ($ref->{time} > $used->{time}) {
            # I lose
            $ref->{nick} = $ref->{uid}
        }
        elsif ($ref->{time} < $used->{time}) {
            # you lose
            $used->channel::mine::send_all_user("NICK $$used{uid}");
            $used->change_nick($used->{uid});
        }
        else {
            # we both lose
            $ref->{nick} = $ref->{uid};
            $used->channel::mine::send_all_user("NICK $$used{uid}");
            $used->change_nick($used->{uid});
        }
    }

    # create a new user
    my $user = user->new($ref);

    # set modes
    $user->handle_mode_string($ref->{modes}, 1);

    return 1

}

sub quit {
    # source  dummy  :rest
    # :source QUIT   :reason
    my ($server, $data, $source, $reason) = @_;

    # delete the server or user
    $source->quit($reason);
}

# handle a nickchange
sub nick {
    # user dummy any
    # :uid NICK  newnick
    my ($server, $data, $user, $newnick) = @_;

    # tell ppl
    $user->channel::mine::send_all_user("NICK $newnick");
    $user->change_nick($newnick);
}

sub burst {
    # server dummy
    # :sid   BURST
    my ($server, $data, $serv) = @_;
    $serv->{is_burst} = 1;
    log2("$$serv{name} is bursting information");
}

sub endburst {
    # server dummy
    # :sid   ENDBURST
    my ($server, $data, $serv) = @_;
    delete $serv->{is_burst};
    $serv->{sent_burst} = 1;
    log2("end of burst from $$serv{name}");
}

sub addumode {
    # server dummy    any  any
    # :sid   ADDUMODE name letter
    my ($server, $data, $serv) = (shift, shift, shift);
    $serv->add_umode(shift, shift);
}

sub umode {
    # user dummy any
    # :uid UMODE modestring
    my ($server, $data, $user, $str) = @_;
    $user->handle_mode_string($str, 1);
}

sub privmsgnotice {
    # user any            any    :rest
    # :uid PRIVMSG|NOTICE target :message
    my ($server, $data, $user, $command, $target, $message) = @_;

    # is it a user?
    my $tuser = user::lookup_by_id($target);
    if ($tuser) {
        # if it's mine, send it
        if ($tuser->is_local) {
            $tuser->sendfrom($user->full, "$command $$tuser{nick} :$message");
            return 1
        }
        # otherwise pass this on...
        server::mine::fire_command($tuser->{location}, privmsgnotice => $command, $user, $tuser, $message);
        return 1
    }

    # must be a channel
    my $channel = channel::lookup_by_name($target);
    if ($channel) {
        # tell local users
        $channel->channel::mine::send_all(':'.$user->full." $command $$channel{name} :$message", $user);

        # then tell local servers if necessary
        my %sent;
        foreach my $usr (values %user::user) {
            next if $server == $usr->{location};
            next if $usr->is_local;
            next if $sent{$usr->{location}};
            $sent{$usr->{location}} = 1;
            server::mine::fire_command($usr->{location}, privmsgnotice => $command, $user, $channel, $message);
        }

        return 1
    }
}

sub sjoin {
    # user dummy any     ts
    # :uid JOIN  channel time
    my ($server, $data, $user, $chname, $time) = @_;
    my $channel = channel::lookup_by_name($chname);

    # channel doesn't exist; make a new one
    if (!$channel) {
        $channel = channel->new({
            name => $chname,
            time => $time
        });
    }

    # take lower time if necessary, and add the user to the channel.
    $channel->channel::mine::take_lower_time($time);
    $channel->cjoin($user, $time) unless $channel->has_user($user);

    # for each user in the channel, send a JOIN message.
    $channel->channel::mine::send_all(q(:).$user->full." JOIN $$channel{name}");
    
}

# add user flags
sub oper {
    # user dummy @rest
    # :uid OPER  flag flag flag
    my ($server, $data, $user, @flags) = @_;
    $user->add_flags(@flags);
}

sub away {
    # user dummy :rest
    # :uid AWAY  :reason
    my ($server, $data, $user, $reason) = @_;
    $user->set_away($reason);
}

sub return_away {
    # user dummy
    # :uid RETURN
    my ($server, $data, $user) = @_;
    $user->unset_away();
}

# add a channel mode
sub addcmode {
    # server dummy    any  any    any
    # :sid   ADDCMODE name letter type
    my ($server, $data, $serv, @args) = @_;
    $serv->add_cmode(@args);
}

# set a mode on a channel
sub cmode {
    # source  dummy channel ts   server      :rest
    # :source CMODE channel time perspective :modestr
    my ($server, $data, $source, $channel, $time, $perspective, $modestr) = @_;

    # ignore if time is older and take lower time
    return if $time > $channel->{time};
    $channel->channel::mine::take_lower_time($time);

    my ($user_result, $server_result) = $channel->handle_mode_string(
        $perspective, $source, $modestr, 1, 1
    );
    return 1 if !$user_result || $user_result =~ m/^(\+|\-)$/;

    # convert it to our view
    $user_result  = $perspective->convert_cmode_string(gv('SERVER'), $user_result);
    my $from      = $source->isa('user') ? $source->full : $source->isa('server') ? $source->{name} : 'MagicalFairyPrincess';
    $channel->channel::mine::send_all(":$from MODE $$channel{name} $user_result");
}

sub part {
    # user dummy channel ts   :rest
    # :uid PART  channel time :reason
    my ($server, $data, $user, $channel, $time, $reason) = @_;

    # take the lower time
    $channel->channel::mine::take_lower_time($time);

    # ?!?!!?!
    if (!$channel->has_user($user)) {
        log2("attempting to remove $$user{nick} from $$channel{name} but that user isn't on that channel");
        return
    }

    # remove the user and tell the local channel users
    $channel->remove($user);
    $reason = defined $reason ? " :$reason" : q();
    $channel->channel::mine::send_all(':'.$user->full." PART $$channel{name}$reason");
    return 1
}

# add user mode, compact AUM
sub aum {
    # server dummy @rest
    # :sid   AUM   name:letter name:letter
    my ($server, $data, $serv) = (shift, shift, shift);
    foreach my $str (@_) {
        my ($name, $letter) = split /:/, $str;
        next unless defined $letter; # just in case..
        $serv->add_umode($name, $letter)
    }
    return 1
}

# add channel mode, compact ACM
sub acm {
    # server dummy @rest
    # :sid   ACM   name:letter:type name:letter:type
    my ($server, $data, $serv) = (shift, shift, shift);
    foreach my $str (@_) {
        my ($name, $letter, $type) = split /:/, $str;
        next unless defined $type;
        $serv->add_cmode($name, $letter, $type)
    }
    return 1
}

# channel user membership, compact CUM
sub cum {
    # server dummy any     ts   any   :rest
    # :sid   CUM   channel time users :modestr
    my ($server, $data, $serv, $chname, $ts, $userstr, $modestr) = @_;

    # we cannot assume that this a new channel
    my $channel = channel::lookup_by_name($chname) || channel->new({ name => $chname, time => $ts});
    my $newtime = $channel->channel::mine::take_lower_time($ts);

    # lazy mode handling..
    # pretend to receive a CMODE.
    # revision: use cmode() directly otherwise fake CMODE messages will be forwarded to children.
    if ($newtime == $ts) { # won the time battle
        my $cdata   = ":$$serv{sid} CMODE $$channel{name} $$channel{time} $$serv{sid} :$modestr";
        cmode($server, $cdata, $serv, $channel, $channel->{time}, $serv, $modestr);
    }

    # no users
    return 1 if $userstr eq '-';

    USER: foreach my $str (split /,/, $userstr) {
        my ($uid, $modes) = split /!/, $str;
        my $user          = user::lookup_by_id($uid) or next USER;

        # join the new users
        unless ($channel->has_user($user)) {
            $channel->cjoin($user, $channel->{time});
            $channel->channel::mine::send_all(q(:).$user->full." JOIN $$channel{name}");
        }

        next USER unless $modes;      # the mode part is obviously optional..
        next USER if $newtime != $ts; # the time battle was lost

        # lazy mode setting
        # but I think it is a clever way of doing it.
        my $final_modestr = $modes.' '.(($uid.' ') x length $modes);
        my ($user_result, $server_result) = $channel->handle_mode_string($serv, $serv, $final_modestr, 1, 1);
        $user_result  = $serv->convert_cmode_string(gv('SERVER'), $user_result);
        $channel->channel::mine::send_all(":$$serv{name} MODE $$channel{name} $user_result");
    }
    return 1
}

sub topic {
    # source  dummy channel ts ts   :rest
    # :source TOPIC channel ts time :topic
    my ($server, $data, $source, $channel, $ts, $time, $topic) = @_;

    # check that channel exists
    return unless $channel;

    if ($channel->channel::mine::take_lower_time($ts) != $ts) {
        # bad channel time
        return
    }

    $channel->channel::mine::send_all(':'.$source->full." TOPIC $$channel{name} :$topic");

    # set it
    if (length $topic) {
        $channel->{topic} = {
            setby => $source->full,
            time  => $time,
            topic => $topic
        };
    }
    else {
        delete $channel->{topic}
    }

    return 1
}

sub topicburst {
    # source dummy      channel ts   any   ts   :rest
    # :sid   TOPICBURST channel ts   setby time :topic
    my ($server, $data, $source, $channel, $ts, $setby, $time, $topic) = @_;

    if ($channel->channel::mine::take_lower_time($ts) != $ts) {
        # bad channel time
        return
    }

    $channel->channel::mine::send_all(':'.$source->full." TOPIC $$channel{name} :$topic");

    # set it
    if (length $topic) {
        $channel->{topic} = {
            setby => $setby,
            time  => $time,
            topic => $topic
        };
    }
    else {
        delete $channel->{topic}
    }

    return 1
}

sub skill {
    # user  dummy user :rest
    # :uid  KILL  uid  :reason
    my ($server, $data, $user, $tuser, $reason) = @_;

    # we ignore any non-local users
    $tuser->{conn}->done("Killed: $reason [$$user{nick}]") if $tuser->is_local;

}

$mod
