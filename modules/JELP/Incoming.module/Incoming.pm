# Copyright (c) 2010-14, Mitchell Cooper
#
# @name:            "JELP::Incoming"
# @package:         "M::JELP::Incoming"
# @description:     "basic set of JELP command handlers"
#
# @depends.modules: "JELP::Base"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::JELP::Incoming;

use warnings;
use strict;
use 5.010;

use utils qw(col match cut_to_limit conf v notice);

our ($api, $mod, $pool, $me);

my %scommands = (
    SID => {
                   # :sid   SID      sid  time  name  proto_v  ircd_v  desc
        params  => '-source(server)  any  ts    any   any      any     :rest',
        code    => \&sid,
        forward => 1
    },
    UID => {
                   # :sid UID       uid  time modes nick ident host cloak ip    realname
        params  => '-source(server) any  ts   any   any  any   any  any   any   :rest',
        code    => \&uid,
        forward => 1
    },
    QUIT => {
                   # needs data for manual forwarding
                   #      :src QUIT :reason
        params  => '-data -source   :rest',
        code    => \&quit
      # forward => handled manually
    },
    NICK => {
                   # :uid NICK    newnick
        params  => '-source(user) any',
        code    => \&nick,
        forward => 1
    },
    BURST => {
                   # :sid BURST     time
        params  => '-source(server) ts',
        code    => \&burst,
        forward => 1
    },
    ENDBURST => {
                   # :sid ENDBURST  time
        params  => '-source(server) ts',
        code    => \&endburst,
        forward => 1
    },
    UMODE => {
                   # :uid UMODE   +modes
        params  => '-source(user) any',
        code    => \&umode,
        forward => 1
    },
    PRIVMSG => {
                   # :src   PRIVMSG  target :message
        params  => '-source -command any    :rest',
        code    => \&privmsgnotice,
      # forward => handled manually
    },
    NOTICE => {
                   # :src   NOTICE   target :message
        params  => '-source -command any    :rest',
        code    => \&privmsgnotice,
      # forward => handled manually
    },
    JOIN => {
                   # :uid JOIN    ch_name time
        params  => '-source(user) any     ts',
        code    => \&_join,
        forward => 1
    },
    OPER => {
                   # :uid OPER    flag1 flag2 ...
        params  => '-source(user) @rest',
        code    => \&oper,
        forward => 1
    },
    AWAY => {
                   # :uid AWAY    :reason
        params  => '-source(user) :rest',
        code    => \&away,
        forward => 1
    },
    RETURN => {
                   # :uid RETURN
        params  => '-source(user)',
        code    => \&return_away,
        forward => 1
    },
    CMODE => {
                   # :src   channel   time   perspective   :modestr
        params  => '-source channel   ts     server        :rest',
        code    => \&cmode,
        forward => 1
    },
    PART => {
                   # :uid PART    channel time :reason
        params  => '-source(user) channel ts   :rest',
        code    => \&part,
        forward => 1
    },
    TOPIC => {
                   # :src TOPIC     ch_time topic_time :topic 
        params  => '-source channel ts      ts         :rest',
        code    => \&topic,
        forward => 1
    },
    TOPICBURST => {
                   # :sid TOPICBURST channel ch_time setby topic_time :topic
        params  => '-source(server)  channel ts      any   ts         :rest',
        code    => \&topicburst,
        forward => 1
    },
    KILL => {
                   # :src KILL uid  :reason
        params  => '-source    user :rest',
        code    => \&skill,
        forward => 1
    },
    AUM => {
                   # :sid AUM       name1:letter1 name2:letter2 ...
        params  => '-source(server) @rest',
        code    => \&aum,
        forward => 1
    },
    ACM => {
                   # :sid ACM       name1:letter1:type1 name2:letter2:type2 ...
        params  => '-source(server) @rest',
        code    => \&acm,
        forward => 1
    },
    CUM => {
                   # :sid CUM       ch_name time user_list :mode_string
        params  => '-source(server) any     ts   any       :rest',
        code    => \&cum,
        forward => 1
    },
    KICK => {
                   # :src KICK channel uid  :reason
        params  => '-source    channel user :rest',
        code    => \&kick,
        forward => 1
    },
    NUM => {
                   # :sid NUM       uid  integer :message
        params  => '-source(server) user any     :rest',
        code    => \&num,
      # forward => handled manually
    },
    LINKS => {
                   # :uid LINKS    target_serv serv_mask query_mask
        params  => '-source(user)  server      any       any',
        code    => \&links,
      # forward => handled manually
    }
);
 
sub init {
    $mod->register_jelp_command(
        name       => $_,
        parameters => $scommands{$_}{params},
        code       => $scommands{$_}{code},
        forward    => $scommands{$_}{forward}
    ) || return foreach keys %scommands;

    undef %scommands;
    return 1;
}

###################
# SERVER COMMANDS #
###################

sub sid {
    # server any    ts any  any   any  :rest
    # :sid   SID   newsid ts name proto ircd :desc
    my ($server, $event, @args) = @_;

    my $ref          = {};
    $ref->{$_}       = shift @args foreach qw[parent sid time name proto ircd desc];
    $ref->{source}   = $server->{sid}; # source = sid we learned about the server from
    $ref->{location} = $server;

    # do not allow SID or server name collisions
    if ($pool->lookup_server($ref->{sid}) || $pool->lookup_server_name($ref->{name})) {
        L("duplicate SID $$ref{sid} or server name $$ref{name}; dropping $$server{name}");
        $server->{conn}->done('attempted to introduce existing server');
        return
    }

    # create a new server
    my $serv = $pool->new_server(%$ref);
    return 1;
}

sub uid {
    # server any ts any   any  any   any  any   any :rest
    # :sid   UID   uid ts modes nick ident host cloak ip  :realname
    my ($server, $event, @args) = @_;
    
    my $ref          = {};
    $ref->{$_}       = shift @args foreach qw[server uid time modes nick ident host cloak ip real];
    $ref->{source}   = $server->{sid}; # source = sid we learned about the user from
    $ref->{location} = $server;
    my $modestr      = delete $ref->{modes};
    # location = the server through which this server can access the user.
    # the location is not necessarily the same as the user's server.

    # uid collision?
    if ($pool->lookup_user($ref->{uid})) {
        # can't tolerate this.
        # the server is either not a juno server or is bugged/mentally unstable.
        L("duplicate UID $$ref{uid}; dropping $$server{name}");
        $server->{conn}->done('UID collision') if exists $server->{conn};
    }

    # nick collision?
    my $used = $pool->lookup_user_nick($ref->{nick});
    if ($used) {
        L("nick collision! $$ref{nick}");
        
        # I lose.
        if ($ref->{time} > $used->{time}) {
            $ref->{nick} = $ref->{uid};
        }
         
        # you lose.
        elsif ($ref->{time} < $used->{time}) {
            $used->send_to_channels("NICK $$used{uid}");
            $used->change_nick($used->{uid});
        }
        
        # we both lose.
        else {
            $ref->{nick} = $ref->{uid};
            $used->send_to_channels("NICK $$used{uid}");
            $used->change_nick($used->{uid});
        }
    }

    # create a new user
    my $user = $pool->new_user(%$ref);

    # set modes.
    $user->handle_mode_string($modestr, 1);

    return 1;
}

sub quit {
    # source   :rest
    # :source QUIT   :reason
    my ($server, $event, $data, $source, $reason) = @_;
    return if $source == $me;
    
    # tell other servers.
    # note: must be done manually because it
    # should not be done if $source is this server
    $server->send_children($data);
    
    # delete the server or user
    $source->quit($reason);
    
}

# handle a nickchange
sub nick {
    # user any
    # :uid NICK  newnick
    my ($server, $event, $user, $newnick) = @_;

    # tell ppl
    $user->send_to_channels("NICK $newnick");
    $user->change_nick($newnick);
}

sub burst {
    # server dummy
    # :sid   BURST
    my ($server, $event, $serv, $their_time) = @_;
    $serv->{is_burst} = time;
    L("$$serv{name} is bursting information");
    notice(server_burst => $serv->{name}, $serv->{sid});
}

sub endburst {
    # server dummy
    # :sid   ENDBURST
    my ($server, $event, $serv) = @_;
    my $time    = delete $serv->{is_burst};
    my $elapsed = time - $time;
    $serv->{sent_burst} = time;
    
    L("end of burst from $$serv{name}");
    notice(server_endburst => $serv->{name}, $serv->{sid}, $elapsed);
    
    # if we haven't sent our own burst yet, do so.
    $serv->send_burst if $serv->{conn} && !$serv->{i_sent_burst};
    
}

sub umode {
    # user any
    # :uid UMODE modestring
    my ($server, $event, $user, $str) = @_;
    $user->do_mode_string_local($str, 1);
}

sub privmsgnotice {
    #                   any         command        any      :rest
    #                   :source     PRIVMSG|NOTICE target   :message
    my ($server, $event, $source,   $command,      $target, $message) = @_;
    
    # is it a user?
    my $tuser = $pool->lookup_user($target);
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
    my $channel = $pool->lookup_channel($target);
    if ($channel) {
        $channel->handle_privmsgnotice($command, $source, $message);
        return 1;
    }
    
    return;
}

sub _join {
    # user any     ts
    # :uid JOIN  channel time
    my ($server, $event, $user, $chname, $time) = @_;
    my $channel = $pool->lookup_channel($chname);

    # channel doesn't exist; make a new one
    if (!$channel) {
        $channel = $pool->new_channel(
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
    # user @rest
    # :uid OPER  flag flag flag
    my ($server, $event, $user, @flags) = @_;
    my (@add, @remove);
    foreach my $flag (@flags) {
        my $first = \substr($flag, 0, 1);
        if ($$first eq '-') {
            $$first = '';
            push @remove, $flag;
            next;
        }
        push @add, $flag;
    }
    $user->add_flags(@add);
    $user->remove_flags(@remove);
}

sub away {
    # user :rest
    # :uid AWAY  :reason
    my ($server, $event, $user, $reason) = @_;
    $user->set_away($reason);
}

sub return_away {
    # user dummy
    # :uid RETURN
    my ($server, $event, $user) = @_;
    $user->unset_away();
}

# set a mode on a channel
sub cmode {
    #                   source   channel   ts     server        :rest
    #                  :source   channel   time   perspective   :modestr
    my ($server, $event, $source, $channel, $time, $perspective, $modestr) = @_;

    # ignore if time is older and take lower time
    return if $time > $channel->{time};
    $channel->take_lower_time($time);
    
    # handle the mode string and send to local users.
    $channel->do_mode_string($perspective, $source, $modestr, 1, 1);
    
    return 1;
}

sub part {
    # user channel ts   :rest
    # :uid PART  channel time :reason
    my ($server, $event, $user, $channel, $time, $reason) = @_;

    # take the lower time
    $channel->take_lower_time($time);

    # ?!?!!?!
    if (!$channel->has_user($user)) {
        L("attempting to remove $$user{nick} from $$channel{name} but that user isn't on that channel");
        return
    }

    # remove the user and tell the local channel users
    notice(user_part => $user->notice_info, $channel->name, $reason // 'no reason');
    $channel->remove($user);
    $reason = defined $reason ? " :$reason" : '';
    $channel->sendfrom_all($user->full, "PART $$channel{name}$reason");
    
    return 1
}

# add user mode, compact AUM
sub aum {
    # server @rest
    # :sid   AUM   name:letter name:letter
    my ($server, $event, $serv) = (shift, shift, shift);
    foreach my $str (@_) {
        my ($name, $letter) = split /:/, $str;
        next if !length $name || !length $letter;
        $serv->add_umode($name, $letter);
    }
    return 1;
}

# add channel mode, compact ACM
sub acm {
    # server @rest
    # :sid   ACM   name:letter:type name:letter:type
    my ($server, $event, $serv) = (shift, shift, shift);
    foreach my $str (@_) {
        my ($name, $letter, $type) = split /:/, $str, 3;
        
        # ensure that all values are present.
        next if
            !length $name   ||
            !length $letter ||
            !length $type;
            
        $serv->add_cmode($name, $letter, $type)
    }
    return 1;
}

# channel user membership, compact CUM
sub cum {
    # server any     ts   any   :rest
    # :sid   CUM   channel time users :modestr
    my ($server, $event, $serv, $chname, $ts, $userstr, $modestr) = @_;

    # we cannot assume that this a new channel
    my $channel = $pool->lookup_channel($chname) || $pool->new_channel(
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
        my $user          = $pool->lookup_user($uid) or next USER;

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
    # source  channel ts ts   :rest
    # :source TOPIC channel ts time :topic
    my ($server, $event, $source, $channel, $ts, $time, $topic) = @_;

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
    # source      channel ts   any   ts   :rest
    # :sid   TOPICBURST channel ts   setby time :topic
    my ($server, $event, $s_serv, $channel, $ts, $setby, $time, $topic) = @_;

    if ($channel->take_lower_time($ts) != $ts) {
        # bad channel time
        return
    }

    # tell users.
    my $t = $channel->topic;
    if (!$t or $t && $t->{topic} ne $topic) {
        $channel->sendfrom_all($s_serv->full, "TOPIC $$channel{name} :$topic");
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
    # user  user :rest
    # :uid  KILL  uid  :reason
    my ($server, $event, $source, $tuser, $reason) = @_;

    # this ignores non-local users.
    $tuser->get_killed_by($source, $reason);

}

sub kick {
    # source channel user :rest
    # :id    KICK  channel uid  :reason
    my ($server, $event, $source, $channel, $t_user, $reason) = @_;
    
    # fallback reason to source.
    $reason //= $source->name;
    
    # tell the local users of the channel.
    notice(user_part =>
        $t_user->notice_info,
        $channel->name,
        "Kicked by $$source{nick}: $reason"
    ) if $source->isa('user');
    $channel->sendfrom_all($source->full, "KICK $$channel{name} $$t_user{nick} :$reason");
    
    # remove the user from the channel.
    $channel->remove_user($t_user);
    
    return 1;
}

# remote numeric.
# server user any :rest
sub num {
    my ($server, $event, $source, $user, $num, $message) = @_;
    
    # local user.
    if ($user->is_local) {
        $user->sendfrom($source->full, "$num $$user{nick} $message");
    }
    
    # forward to next hop.
    else {
        $user->{location}->fire_command(num => $source, $user, $num, $message);
    }
    
    return 1;
}

sub links {
    my ($server, $event, $user, $t_server, $serv_mask, $query_mask) = @_;

    # this is the server match.
    if ($t_server->is_local) {
        return $user->handle_unsafe("LINKS $serv_mask $query_mask");
    }
    
    # pass it on.
    $t_server->{location}->fire_command($user, $t_server, $serv_mask, $query_mask);

    return 1;
}

$mod
