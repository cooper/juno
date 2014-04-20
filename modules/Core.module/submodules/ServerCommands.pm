# Copyright (c) 2009-14, Mitchell Cooper
package API::Module::Core::ServerCommands;
 
use warnings;
use strict;
 
use utils qw(col log2 lceq match cut_to_limit conf v notice);

our $VERSION = $API::Module::Core::VERSION;

my %scommands = (
    SID => {
        params  => 'server dummy any ts any any any :rest',
        code    => \&sid,
        forward => 1
    },
    UID => {
        params  => 'server dummy any ts any any any any any any :rest',
        code    => \&uid,
        forward => 1
    },
    QUIT => {
        params  => 'source dummy :rest',
        code    => \&quit
      # forward => handled manually
    },
    NICK => {
        params  => 'user dummy any',
        code    => \&nick,
        forward => 1
    },
    BURST => {
        params  => 'server',
        code    => \&burst,
        forward => 1
    },
    ENDBURST => {
        params  => 'server',
        code    => \&endburst,
        forward => 1
    },
    ADDUMODE => {
        params  => 'server dummy any any',
        code    => \&addumode,
        forward => 1
    },
    UMODE => {
        params  => 'user dummy any',
        code    => \&umode,
        forward => 1
    },
    PRIVMSG => {
        params  => 'any any any :rest',
        code    => \&privmsgnotice,
      # forward => handled manually
    },
    NOTICE => {
        params  => 'any any any :rest',
        code    => \&privmsgnotice,
      # forward => handled manually
    },
    JOIN => {
        params  => 'user dummy any ts',
        code    => \&sjoin,
        forward => 1
    },
    OPER => {
        params  => 'user dummy @rest',
        code    => \&oper,
        forward => 1
    },
    AWAY => {
        params  => 'user dummy :rest',
        code    => \&away,
        forward => 1
    },
    RETURN => {
        params  => 'user',
        code    => \&return_away,
        forward => 1
    },
    ADDCMODE => {
        params  => 'server dummy any any any',
        code    => \&addcmode,
        forward => 1
    },
    CMODE => {
        params  => 'source dummy channel ts server :rest',
        code    => \&cmode,
        forward => 1
    },
    PART => {
        params  => 'user dummy channel ts :rest',
        code    => \&part,
        forward => 1
    },
    TOPIC => {
        params  => 'source dummy channel ts ts :rest',
        code    => \&topic,
        forward => 1
    },
    TOPICBURST => {
        params  => 'source dummy channel ts any ts :rest',
        code    => \&topicburst,
        forward => 1
    },
    KILL => {
        params  => 'user dummy user :rest',
        code    => \&skill,
        forward => 1
    },
    
    # compact

    AUM => {
        params  => 'server dummy @rest',
        code    => \&aum,
        forward => 1
    },
    ACM => {
        params  => 'server dummy @rest',
        code    => \&acm,
        forward => 1
    },
    CUM => {
        params  => 'server dummy any ts any :rest',
        code    => \&cum,
        forward => 1
    },
    KICK => {
        params  => 'source dummy channel user :rest',
        code    => \&kick,
        forward => 1
    }
);

our $mod = API::Module->new(
    name        => 'ServerCommands',
    version     => $VERSION,
    description => 'the core set of server commands',
    requires    => ['ServerCommands'],
    initialize  => \&init
);
 
sub init {

    # register server commands
    $mod->register_server_command(
        name       => $_,
        parameters => $scommands{$_}{params},
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
    $ref->{source} = $server->{sid}; # source = sid we learned about the server from

    # do not allow SID or server name collisions
    if ($::pool->lookup_server($ref->{sid}) || $::pool->lookup_server_name($ref->{name})) {
        log2("duplicate SID $$ref{sid} or server name $$ref{name}; dropping $$server{name}");
        $server->{conn}->done('attempted to introduce existing server');
        return
    }

    # create a new server
    my $serv = $::pool->new_server(%$ref);
    return 1;
}

sub uid {
    # server dummy any ts any   any  any   any  any   any :rest
    # :sid   UID   uid ts modes nick ident host cloak ip  :realname
    my ($server, $data, @args) = @_;
    
    my $ref          = {};
    $ref->{$_}       = shift @args foreach qw[server uid time modes nick ident host cloak ip real];
    $ref->{source}   = $server->{sid}; # source = sid we learned about the user from
    $ref->{location} = $server;
    my $modestr      = delete $ref->{modes};
    # location = the server through which this server can access the user.
    # the location is not necessarily the same as the user's server.

    # uid collision?
    if ($::pool->lookup_user($ref->{uid})) {
        # can't tolerate this.
        # the server is either not a juno server or is bugged/mentally unstable.
        log2("duplicate UID $$ref{uid}; dropping $$server{name}");
        $server->{conn}->done('UID collision') if exists $server->{conn};
    }

    # nick collision?
    my $used = $::pool->lookup_user_nick($ref->{nick});
    if ($used) {
        log2("nick collision! $$ref{nick}");
        if ($ref->{time} > $used->{time}) {
            # I lose
            $ref->{nick} = $ref->{uid}
        }
        elsif ($ref->{time} < $used->{time}) {
            # you lose
            $used->send_to_channels("NICK $$used{uid}");
            $used->change_nick($used->{uid});
        }
        else {
            # we both lose
            $ref->{nick} = $ref->{uid};
            $used->send_to_channels("NICK $$used{uid}");
            $used->change_nick($used->{uid});
        }
    }

    # create a new user
    my $user = $::pool->new_user(%$ref);

    # set modes.
    $user->handle_mode_string($modestr, 1);

    return 1;
}

sub quit {
    # source  dummy  :rest
    # :source QUIT   :reason
    my ($server, $data, $source, $reason) = @_;
    return if $source == v('SERVER');
    
    # tell other servers.
    # note: must be done manually because it
    # should not be done if $source is this server
    $server->send_children($data);
    
    # delete the server or user
    $source->quit($reason);
    
}

# handle a nickchange
sub nick {
    # user dummy any
    # :uid NICK  newnick
    my ($server, $data, $user, $newnick) = @_;

    # tell ppl
    $user->send_to_channels("NICK $newnick");
    $user->change_nick($newnick);
}

sub burst {
    # server dummy
    # :sid   BURST
    my ($server, $data, $serv) = @_;
    $serv->{is_burst} = time;
    log2("$$serv{name} is bursting information");
    notice(server_burst => $server->{name}, $server->{sid});
}

sub endburst {
    # server dummy
    # :sid   ENDBURST
    my ($server, $data, $serv) = @_;
    my $time    = delete $serv->{is_burst};
    my $elapsed = time - $time;
    $serv->{sent_burst} = time;
    
    log2("end of burst from $$serv{name}");
    notice(server_endburst => $server->{name}, $server->{sid}, $elapsed);
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
    my ($server, $data, $sourcestr, $command, $target, $message) = @_;
    
    # find the source.
    # this must be done manually because the source matcher disconnects
    # servers for protocol error when receiving notices from server name
    # such as "lookup up your hostname," "found your hostname," etc.
    $sourcestr = col($sourcestr);
    my $source = $::pool->lookup_user($sourcestr) ||
                 $::pool->lookup_server($sourcestr) or return;

    # is it a user?
    my $tuser = $::pool->lookup_user($target);
    if ($tuser) {
    
        # if it's mine, send it
        if ($tuser->is_local) {
            $tuser->sendfrom($source->full, "$command $$tuser{nick} :$message");
            return 1;
        }
        
        # otherwise pass this on...
        $tuser->{location}->fire_command(privmsgnotice => $command, $source, $tuser, $message);
        
        return 1;
    }

    # must be a channel.
    my $channel = $::pool->lookup_channel($target);
    if ($channel) {
        $channel->handle_privmsgnotice($command, $source, $message);
        return 1;
    }
    
    return;
}

sub sjoin {
    # user dummy any     ts
    # :uid JOIN  channel time
    my ($server, $data, $user, $chname, $time) = @_;
    my $channel = $::pool->lookup_channel($chname);

    # channel doesn't exist; make a new one
    if (!$channel) {
        $channel = $::pool->new_channel(
            name => $chname,
            time => $time
        );
    }

    # take lower time if necessary, and add the user to the channel.
    $channel->take_lower_time($time);
    $channel->cjoin($user, $time) unless $channel->has_user($user);
    
    # for each user in the channel, send a JOIN message.
    $channel->sendfrom_all($user->full, "JOIN $$channel{name}");
   
    # fire after join event.
    $channel->fire_event(user_joined => $user);

    
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
    #                   source   channel   ts     server        :rest
    #                  :source   channel   time   perspective   :modestr
    my ($server, $data, $source, $channel, $time, $perspective, $modestr) = @_;

    # ignore if time is older and take lower time
    return if $time > $channel->{time};
    $channel->take_lower_time($time);
    
    # handle the mode string and send to local users.
    $channel->do_mode_string($perspective, $source, $modestr, 1, 1);
    
    return 1;
}

sub part {
    # user dummy channel ts   :rest
    # :uid PART  channel time :reason
    my ($server, $data, $user, $channel, $time, $reason) = @_;

    # take the lower time
    $channel->take_lower_time($time);

    # ?!?!!?!
    if (!$channel->has_user($user)) {
        log2("attempting to remove $$user{nick} from $$channel{name} but that user isn't on that channel");
        return
    }

    # remove the user and tell the local channel users
    notice(user_part => $user->notice_info, $channel->{name}, $reason // 'no reason');
    $channel->remove($user);
    $reason = defined $reason ? " :$reason" : '';
    $channel->sendfrom_all($user->full, "PART $$channel{name}$reason");
    
    return 1
}

# add user mode, compact AUM
sub aum {
    # server dummy @rest
    # :sid   AUM   name:letter name:letter
    my ($server, $data, $serv) = (shift, shift, shift);
    foreach my $str (@_) {
        my ($name, $letter) = split /:/, $str;
        next if !length $name || !length $letter;
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
        my ($name, $letter, $type) = split /:/, $str, 3;
        
        # ensure that all values are present.
        next if
            !length $name   ||
            !length $letter ||
            !length $type;
            
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
    my $channel = $::pool->lookup_channel($chname) || $::pool->new_channel(
        name => $chname,
        time => $ts
    );

    # store mode string before any possible changes.
    my @after_params;       # params after changes.
    my $after_modestr = ''; # mode string after changes.
    my $old_modestr   = $channel->mode_string_all($serv, 1); # all but status
    my $old_s_modestr = $channel->mode_string_status($serv); # status only
    
    # take the new time if it's less recent.
    my $old_time = $channel->{time};
    my $new_time = $channel->take_lower_time($ts, 1);

    # determine the user mode string.
    my ($uids_modes, @uids) = '';
    USER: foreach my $str (split /,/, $userstr) {
        last if $userstr eq '-';
        my ($uid, $modes) = split /!/, $str;
        my $user          = $::pool->lookup_user($uid) or next USER;

        # join the new users
        unless ($channel->has_user($user)) {
            $channel->cjoin($user, $channel->{time});
            $channel->sendfrom_all($user->full, "JOIN $$channel{name}");
            $channel->fire_event(user_joined => $user);
        }

        next USER unless $modes;      # the mode part is obviously optional..
        next USER if $new_time != $ts; # the time battle was lost.
        next USER if $user->is_local; # we know modes for local user already.

        $uids_modes .= $modes;
        push @uids, $uid for 1 .. length $modes;
        
    }
    
    # combine this with the other modes.
    my ($other_modes, @other_params) = split ' ', $modestr;
    my $command_modestr = join(' ', '+'.$other_modes.$uids_modes, @other_params, @uids);
    
    # the channel time is the same as in the command, so new modes are valid.
    if ($new_time == $ts) {
    
        # determine the difference between
        # $old_modestr     (all former modes except status)
        # $command_modestr (all new modes including status)
        my $difference = $serv->cmode_string_difference($old_modestr, $command_modestr, 1);
        
        # the command time took over, so we need to remove our current status modes.
        if ($new_time < $old_time) {
            substr($old_s_modestr, 0, 1) = '-';
            
            # separate each string into modes and params.
            my ($s_modes, @s_params) = split ' ', $old_s_modestr;
            my ($d_modes, @d_params) = split ' ', $difference;
            
            # combine.
            $s_modes  //= '';
            $d_modes  //= '';
            $difference = join(' ', join('', $d_modes, $s_modes), @d_params, @s_params);

        }
        
        # handle the mode string locally.
        $channel->do_mode_string_local($serv, $serv, $difference, 1, 1) if $difference;
        
    }
    
    return 1;
}

sub topic {
    # source  dummy channel ts ts   :rest
    # :source TOPIC channel ts time :topic
    my ($server, $data, $source, $channel, $ts, $time, $topic) = @_;

    # check that channel exists
    return unless $channel;

    if ($channel->take_lower_time($ts) != $ts) {
        # bad channel time
        return
    }

    # tell users.
    $channel->sendfrom_all($source->full, "TOPIC $$channel{name} :$topic");
    
    # set it
    if (length $topic) {
        $channel->{topic} = {
            setby  => $source->full,
            time   => $time,
            topic  => $topic,
            source => $server->{sid}
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

    if ($channel->take_lower_time($ts) != $ts) {
        # bad channel time
        return
    }

    # tell users.
    my $t = $channel->topic;
    if (!$t or $t && $t->{topic} ne $topic) {
        $channel->sendfrom_all($source->full, "TOPIC $$channel{name} :$topic");
    }
    
    # set it
    if (length $topic) {
        $channel->{topic} = {
            setby  => $setby,
            time   => $time,
            topic  => $topic,
            source => $server->{sid} # source = SID of server location where topic set
        };
    }
    else {
        delete $channel->{topic};
    }

    return 1;
}

sub skill {
    # user  dummy user :rest
    # :uid  KILL  uid  :reason
    my ($server, $data, $user, $tuser, $reason) = @_;

    # this ignores non-local users.
    $tuser->get_killed_by($user, $reason);

}

sub kick {
    # source dummy channel user :rest
    # :id    KICK  channel uid  :reason
    my ($server, $data, $source, $channel, $t_user, $reason) = @_;
    
    # fallback reason to source.
    $reason //= $source->name;
    
    # tell the local users of the channel.
    notice(user_part =>
        $t_user->notice_info,
        $channel->{name},
        "Kicked by $$source{nick}: $reason"
    ) if $source->isa('user');
    $channel->sendfrom_all($source->full, "KICK $$channel{name} $$t_user{nick} :$reason");
    
    # remove the user from the channel.
    $channel->remove_user($t_user);
    
    return 1;
}

$mod
