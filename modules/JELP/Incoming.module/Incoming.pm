# Copyright (c) 2010-16, Mitchell Cooper
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
        code    => \&sid
    },
    UID => {
                   # :sid UID       uid  time modes nick ident host cloak ip    realname
        params  => '-source(server) any  ts   any   any  any   any  any   any   :rest',
        code    => \&uid
    },
    QUIT => {
                   # @from=uid          :src QUIT  :reason
        params  => '-tag.from(user,opt) -source    :rest',
        code    => \&quit
    },
    NICK => {
                   # :uid NICK    newnick
        params  => '-source(user) any',
        code    => \&nick
    },
    BURST => {
                   # :sid BURST     time
        params  => '-source(server) ts',
        code    => \&burst
    },
    ENDBURST => {
                   # :sid ENDBURST  time
        params  => '-source(server) ts',
        code    => \&endburst
    },
    UMODE => {
                   # :uid UMODE   +modes
        params  => '-source(user) any',
        code    => \&umode
    },
    PRIVMSG => {
                   # :src   PRIVMSG  target :message
        params  => '-source -command any    :rest',
        code    => \&privmsgnotice
    },
    NOTICE => {
                   # :src   NOTICE   target :message
        params  => '-source -command any    :rest',
        code    => \&privmsgnotice
    },
    JOIN => {
                   # :uid JOIN    ch_name time
        params  => '-source(user) any     ts',
        code    => \&_join
    },
    OPER => {
                   # :uid OPER    flag1 flag2 ...
        params  => '-source(user) @rest',
        code    => \&oper
    },
    AWAY => {
                   # :uid AWAY    :reason
        params  => '-source(user) :rest',
        code    => \&away
    },
    RETURN => {
                   # :uid RETURN
        params  => '-source(user)',
        code    => \&return_away
    },
    CMODE => {
                   # :src   channel   time   perspective   :modestr
        params  => '-source channel   ts     server        :rest',
        code    => \&cmode
    },
    PART => {
                   # :uid PART    channel time :reason
        params  => '-source(user) channel ts   :rest',
        code    => \&part
    },
    TOPIC => {
                   # :src TOPIC     ch_time topic_time :topic
        params  => '-source channel ts      ts         :rest',
        code    => \&topic
    },
    TOPICBURST => {
                   # :sid TOPICBURST channel ch_time setby topic_time :topic
        params  => '-source(server)  channel ts      any   ts         :rest',
        code    => \&topicburst
    },
    KILL => {
                   # :src KILL uid  :reason
        params  => '-source    user :rest',
        code    => \&_kill
    },
    AUM => {
                   # :sid AUM       name1:letter1 name2:letter2 ...
        params  => '-source(server) @rest',
        code    => \&aum
    },
    ACM => {
                   # :sid ACM       name1:letter1:type1 name2:letter2:type2 ...
        params  => '-source(server) @rest',
        code    => \&acm
    },
    SJOIN => {
                   # :sid SJOIN     ch_name time modes... :user_list
        params  => '-source(server) any     ts   @rest',
        code    => \&sjoin
    },
    KICK => {
                   # :src KICK channel uid  :reason
        params  => '-source    channel user :rest',
        code    => \&kick
    },
    NUM => {
                   # :sid NUM       uid  integer :message
        params  => '-source(server) user any     :rest',
        code    => \&num
    },
    LINKS => {
                   # @for=sid        :uid    LINKS  serv_mask  query_mask
        params  => '-tag.for(server) -source(user)  any        any',
        code    => \&links
    },
    WHOIS => {     # @for=sid        :uid   WHOIS   target_user
        params  => '-tag.for(server) -source(user)  user',
        code    => \&whois
    },
    SNOTICE => {  # @from_user=uid          :sid SNOTICE    flag  :message
        params => '-tag.from_user(user,opt) -source(server) any   :rest',
        code   => \&snotice
    },
    LOGIN => {
                  # :uid LOGIN      actname,...
        params => '-source(user)    any',
        code   => \&login
    },
    PING => {
        params => 'any',
        code   => \&ping
    },
    PARTALL => {
                  # :uid PARTALL
        params => '-source(user)',
        code   => \&partall
    },
    INVITE => {
                  # :uid INVITE  uid  ch_name
        params => '-source(user) user any',
        code   => \&invite
    },
    SAVE => {
                  # :sid SAVE      uid   nickTS
        params => '-source(server) user  ts',
        code   => \&save
    },
    USERINFO => {
        params => '-source(user)',
        code   => \&userinfo
    },
    FNICK => {    # :sid FNICK      uid  new_nick new_nick_ts old_nick_ts
        params => '-source(server)  user *        ts          ts',
        code   => \&fnick
    }
);

sub init {
    $mod->register_jelp_command(
        name       => $_,
        parameters => $scommands{$_}{params},
        code       => $scommands{$_}{code},
        forward    => $scommands{$_}{forward}
    ) || return foreach keys %scommands;

    # global user commands
    $mod->register_global_command(name => $_) || return foreach qw(
        version time admin motd rehash connect lusers users
    );

    undef %scommands;
    return 1;
}

###################
# SERVER COMMANDS #
###################

sub sid {
    # server any    ts any  any   any  :rest
    # :sid   SID   newsid ts name proto ircd :desc
    my ($server, $msg, @args) = @_;

    # info.
    my $ref          = {};
    $ref->{$_}       = shift @args foreach qw[parent sid time name proto ircd desc];
    $ref->{source}   = $server->{sid}; # source = sid we learned about the server from
    $ref->{location} = $server;

    # hidden?
    my $sub = \substr($ref->{desc}, 0, 4);
    if (length $sub && $$sub eq '(H) ') {
        $$sub = '';
        $ref->{hidden} = 1;
    }

    # do not allow SID or server name collisions
    if (my $err = server::protocol::check_new_server(
    $ref->{sid}, $ref->{name}, $server->{name})) {
        $server->conn->done($err);
        return;
    }

    # create a new server
    my $serv = $pool->new_server(%$ref);

    # === Forward ===
    $msg->forward(new_server => $serv);

    return 1;
}

sub uid {
    # server any ts any   any  any   any  any   any :rest
    # :sid   UID   uid ts modes nick ident host cloak ip  :realname
    my ($server, $msg, @args) = @_;

    my $ref          = {};
    $ref->{$_}       = shift @args foreach
        qw[server uid nick_time modes nick ident host cloak ip real];
    $ref->{source}   = $server->{sid}; # source = sid we learned about the user from
    $ref->{location} = $server;
    my $modestr      = delete $ref->{modes};
    # location = the server through which this server can access the user.
    # the location is not necessarily the same as the user's server.

    # create a temporary user object.
    my $new_usr_temp = user->new(%$ref);

    # uid collision?
    if (my $other = $pool->lookup_user($ref->{uid})) {
        notice(user_identifier_taken =>
            $server->{name},
            $new_usr_temp->notice_info, $new_usr_temp->id,
            $other->notice_info
        );
        $server->conn->done('UID collision') if $server->conn;
        return;
    }

    # nick collision!
    my $used = $pool->nick_in_use($ref->{nick});

    # unregistered user. kill it.
    if ($used && $used->isa('connection')) {
        $used->done('Overridden');
        undef $used;
    }

    # it's a registered user.
    if ($used) {
        server::protocol::handle_nick_collision(
            $server,
            $used, $new_usr_temp, 1
        ) and return 1;
    }

    # create a new user
    my $user = $pool->new_user(%$new_usr_temp);

    # set modes.
    $user->handle_mode_string($modestr, 1);

    # === Forward ===
    #
    #   JELP:   UID
    #   TS6:    EUID
    #
    $msg->forward(new_user => $user);

    return 1;
}

sub quit {
    # source   :rest
    # :source QUIT   :reason
    my ($server, $msg, $from, $source, $reason) = @_;

    # can't quit local users or the local server.
    return if $source->is_local;

    # our uplink.
    if ($source->isa('server') && $source->conn) {

        # we might have a tag which says who it's from
        notice(squit =>
            $from->notice_info,
            $source->{name}, $source->{parent}{name}
        ) if $from;

        # close it. this will also propagate.
        $source->conn->done($reason);

        return 1;
    }

    # delete the server or user
    $source->quit($reason);

    # === Forward ===
    $msg->forward(quit => $source, $reason);

    return 1;
}

# handle a nickchange
sub nick {
    # user any
    # :uid NICK  newnick
    my ($server, $msg, $user, $newnick) = @_;

    # tell ppl
    $user->send_to_channels("NICK $newnick");
    $user->change_nick($newnick, time);

    # === Forward ===
    $msg->forward(nickchange => $user);

}

sub burst {
    # server dummy
    # :sid   BURST
    my ($server, $msg, $serv, $their_time) = @_;
    $serv->{is_burst} = time;
    L("$$serv{name} is bursting information");
    notice(server_burst => $serv->notice_info);

    # === Forward ===
    $msg->forward(burst => $serv, $their_time);

}

sub endburst {
    # server dummy
    # :sid   ENDBURST
    my ($server, $msg, $serv, $their_time) = @_;
    my $time    = delete $serv->{is_burst};
    my $elapsed = time - $time;
    $serv->{sent_burst} = time;

    L("end of burst from $$serv{name}");
    notice(server_endburst => $serv->notice_info, $elapsed);

    # if we haven't sent our own burst yet, do so.
    $serv->send_burst if $serv->{conn} && !$serv->{i_sent_burst};

    # === Forward ===
    $msg->forward(endburst => $serv, $their_time);

}

sub umode {
    # user any
    # :uid UMODE modestring
    my ($server, $msg, $user, $str) = @_;
    $user->do_mode_string_local($str, 1);

    # === Forward ===
    $msg->forward(umode => $user, $str);

}

sub privmsgnotice {
    my ($server, $msg, $source, $command, $target, $message) = @_;

    # Complex PRIVMSG
    #   a message to all users on server names matching a mask ('$$' followed by mask)
    #   propagation: broadcast
    #   Only allowed to IRC operators.
    if ($target =~ m/^\$\$(.+)$/) {
        my $mask = $1;

        # it cannot be a server source.
        if ($source->isa('server')) {
            L('For TS6 compatibility, "$$" complex PRIVMSG not permitted with server as a source');
            return;
        }

        # consider each server that matches
        # consider: what if a server is hidden? would this skip it?
        my %done;
        foreach my $serv ($pool->lookup_server_mask($mask)) {
            my $location = $serv->{location} || $serv; # for $me, location = nil

            # already did or the server is connected via the source server
            next if $done{$location};
            next if $location == $server;

            # if the server is me, send to all my users
            if ($serv == $me) {
                $_->sendfrom($source->full, "$command $$_{nick} :$message")
                    foreach $pool->local_users;
                $done{$me} = 1;
                next;
            }

            # otherwise, forward it
            $msg->forward_to($serv, privmsgnotice_server_mask =>
                $command, $source,
                $mask,    $message
            );

            $done{$location} = 1;
        }

        return 1;
    }

    # is it a user?
    my $tuser = $pool->lookup_user($target);
    if ($tuser) {

        # if it's mine, send it.
        if ($tuser->is_local) {
            $tuser->sendfrom($source->full, "$command $$tuser{nick} :$message");
            return 1;
        }

        # === Forward ===
        #
        # the user does not belong to us;
        # pass this on to its physical location.
        #
        $msg->forward_to($tuser, privmsgnotice =>
            $command, $source,
            $tuser,   $message
        );

        return 1;
    }

    # must be a channel.
    my $channel = $pool->lookup_channel($target);
    if ($channel) {

        # the second-to-last argument here tells ->handle_privmsgnotice
        # to not forward the message to servers. that is handled below.
        #
        # the last argument tells it to force the message to send,
        # regardless of modes or bans, etc.
        #
        $channel->handle_privmsgnotice($command, $source, $message, 1, 1);

        # === Forward ===
        #
        # forwarding to a channel means to send it to every server that
        # has 1 or more members in the channel.
        #
        $msg->forward_to($channel, privmsgnotice =>
            $command, $source,
            $channel, $message
        );

        return 1;
    }

    return;
}

sub _join {
    # user any     ts
    # :uid JOIN  channel time
    my ($server, $msg, $user, $chname, $time) = @_;
    my ($channel, $new) = $pool->lookup_or_create_channel($chname, $time);

    # take lower time if necessary.
    $channel->take_lower_time($time) unless $new;

    # do the join.
    $channel->do_join($user);

    # === Forward ===
    $msg->forward(join => $user, $channel, $channel->{time});

}

# add user flags
sub oper {
    # user @rest
    # :uid OPER  flag flag flag
    my ($server, $msg, $user, @flags) = @_;
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

    # === Forward ===
    $msg->forward(oper => $user, @flags);

}

sub away {
    # user :rest
    # :uid AWAY  :reason
    my ($server, $msg, $user, $reason) = @_;
    $user->do_away($reason);

    # === Forward ===
    $msg->forward(away => $user);

}

sub return_away {
    # user dummy
    # :uid RETURN
    my ($server, $msg, $user) = @_;
    $user->do_away();

    # === Forward ===
    $msg->forward(return_away => $user);

}

# set a mode on a channel
sub cmode {
    #                   source   channel   ts     server        :rest
    #                  :source   channel   time   perspective   :modestr
    my ($server, $msg, $source, $channel, $time, $perspective, $modestr) = @_;

    # ignore if time is older and take lower time
    my $new_ts = $channel->take_lower_time($time);
    return unless $time == $new_ts;

    # handle the mode string and send to local users.
    $channel->do_mode_string_local($perspective, $source, $modestr, 1, 1);

    # === Forward ===
    #
    # $source, $channel, $time, $perspective, $modestr
    #
    # JELP: CMODE
    # TS6:  TMODE
    #
    $msg->forward(cmode => $source, $channel, $time, $perspective, $modestr);

    return 1;
}

sub part {
    # user channel ts   :rest
    # :uid PART  channel time :reason
    my ($server, $msg, $user, $channel, $time, $reason) = @_;

    # take the lower time
    $channel->take_lower_time($time);

    # ?!?!!?!
    if (!$channel->has_user($user)) {
        L("attempting to remove $$user{nick} from $$channel{name} but that user isn't on that channel");
        return;
    }

    # remove the user and tell others
    $channel->do_part($user, $reason);

    # === Forward ===
    $msg->forward(part => $user, $channel, $reason);

    return 1;
}

# add user mode, compact AUM
sub aum {
    # server @rest
    # :sid   AUM   name:letter name:letter
    my ($server, $msg, $serv) = (shift, shift, shift);
    foreach my $str (@_) {
        my ($name, $letter) = split /:/, $str;
        next if !length $name || !length $letter;
        $serv->add_umode($name, $letter);
    }

    # === Forward ===
    #
    # this will probably only be used for JELP
    #
    $msg->forward(add_umodes => $serv);

    return 1;
}

# add channel mode, compact ACM
sub acm {
    # server @rest
    # :sid   ACM   name:letter:type name:letter:type
    my ($server, $msg, $serv) = (shift, shift, shift);
    foreach my $str (@_) {
        my ($name, $letter, $type) = split /:/, $str, 3;

        # ensure that all values are present.
        next if
            !length $name   ||
            !length $letter ||
            !length $type;

        $serv->add_cmode($name, $letter, $type)
    }

    # === Forward ===
    #
    # this will probably only be used for JELP
    #
    $msg->forward(add_cmodes => $serv);

    return 1;
}

# channel burst
sub sjoin {
    # server         any     ts   any   :rest
    # :sid   SJOIN   channel time users :modestr
    my $nicklist = pop;
    my ($server, $msg, $source_serv, $ch_name, $ts, $mode_str_modes, @mode_params) = @_;

    # maybe we have a channel by this name, otherwise create one.
    my ($channel, $new) = $pool->lookup_or_create_channel($ch_name, $ts);

    # take the new time if it's less recent.
    # note that modes are not handled here (the second arg says not to)
    # because they are handled manually in a prettier way for CUM.
    my $old_time = $channel->{time};
    my $new_time = $channel->take_lower_time($ts, 1);

    # CONVERT MODES
    #=================================

    # store mode string before any possible changes.
    # this now includes status modes as well,
    # which were previously handled separately.
    my (undef, $old_mode_str) = $channel->mode_string_all($me);

    # the incoming mode string must be converted to the perspective of this
    # server. this is necessary because everything needs to be in the same
    # perspective for one unified mode handle.
    #
    # we use this server's perspective rather than the source server's
    # to ensure that all current modes known to this server are unset if the
    # provided TS is older than our existing channelTS.
    #
    # note that converting the mode string to local perspective will result in
    # a loss of modes unknown to this server. that is OK as of the time of
    # writing because ANY ->mode_string_all() call from this server, regardless
    # of the perspective argument, will omit modes unknown to the local server.
    # it is currently impossible to track unknown modes. see issue #100.
    #
    my $mode_str = join ' ', $mode_str_modes, @mode_params;
    $mode_str = $source_serv->convert_cmode_string($me, $mode_str, 1);

    # $old_mode_str and $mode_str are now both in the perspective of $me.

    (my $accept_new_modes)++ if $new_time == $ts;
    my $clear_old_modes = $new_time < $old_time;

    # HANDLE USERS
    #====================

    # determine the user mode string.
    my ($uids_modes, @uids, @good_users) = '+';
    USER: foreach my $str (split /\s+/, $nicklist) {

        # find the user and modes
        my ($uid, $modes) = split /!/, $str;
        my $user = $pool->lookup_user($uid) or next USER;

        # this user does not physically belong to this server; ignore.
        next if $user->{location} != $server;

        # join the new user
        push @good_users, $user;
        $channel->do_join($user);

        # no prefixes or not accepting the prefixes.
        next unless length $modes && $accept_new_modes;

        $uids_modes .= $modes;
        push @uids, $uid for 1 .. length $modes;

    }

    # ACCEPT AND RESET MODES
    #=================================

    # okay, now we're ready to apply the modes.
    if ($accept_new_modes) {

        # $uids_modes are currently in the perspective of the source server.
        #
        # we used to only convert the mode letters and not pass the parameters
        # to ->convert_cmode_string(), but this caused parameter mixups when the
        # destination server did not recognize one of the status modes.
        #
        my $uid_str = join ' ', $uids_modes, @uids;
        $uid_str = $source_serv->convert_cmode_string($me, $uid_str, 1);

        # combine status modes with the other modes in the message,
        # now that $mode_str and $uid_str are both in the perspective of $me.
        my $command_mode_str = $me->combine_cmode_strings($mode_str, $uid_str);

        # determine the difference between the old mode string and the new one.
        # note that ->cmode_string_difference() ONLY supports positive +modes.
        my $difference = $me->cmode_string_difference(
            $old_mode_str,      # all former modes
            $command_mode_str,  # all new modes including statuses
            0,                  # combine ban lists? no longer used in JELP
            !$clear_old_modes   # do not remove modes missing from $old_mode_str
        );

        # handle the mode string locally.
        # note: do not supply a $over_protocol sub because
        # this generated string uses juno UIDs.
        $channel->do_mode_string_local($me, $source_serv, $difference, 1, 1)
            if $difference;

    }

    # delete the channel if no users
    $channel->destroy_maybe if $new;

    # === Forward ===
    $msg->forward(channel_burst => $channel, $source_serv, @good_users);

    return 1;
}

sub topic {
    # source  channel ts ts   :rest
    # :source TOPIC channel ts time :topic
    my ($server, $msg, $source, $channel, $ts, $time, $topic) = @_;

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

    # === Forward ===
    $msg->forward(topic => $source, $channel, $channel->{time}, $topic);

    return 1
}

sub topicburst {
    # source            channel ts   any   ts   :rest
    # :sid   TOPICBURST channel ts   setby time :topic
    my ($server, $msg, $s_serv, $channel, $ts, $setby, $topic_ts, $topic) = @_;

    if ($channel->take_lower_time($ts) != $ts) {
        # bad channel time
        return;
    }

    # we have a topic btw.
    if ($channel->{topic}) {

        # our topicTS is older.
        return if $channel->{topic}{time} < $topic_ts;

        # the topics are the same.
        return if
            $channel->{topic}{topic} eq $topic &&
            $channel->{topic}{setby} eq $setby;

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
            time   => $topic_ts,
            topic  => $topic,
            source => $server->{sid} # source = SID of server location where topic set
        };
    }
    else {
        delete $channel->{topic};
    }

    # === Forward ===
    $msg->forward(topicburst => $channel);

    return 1;
}

sub _kill {
    # user  user :rest
    # :uid  KILL  uid  :reason
    my ($server, $msg, $source, $tuser, $reason) = @_;

    $tuser->get_killed_by($source, $reason);

    # === Forward ===
    $msg->forward(kill => $source, $tuser, $reason);

}

sub kick {
    # source channel user :rest
    # :id    KICK  channel uid  :reason
    my ($server, $msg, $source, $channel, $t_user, $reason) = @_;

    $channel->user_get_kicked($t_user, $source, $reason);

    # === Forward ===
    $msg->forward(kick => $source, $channel, $t_user, $reason);

    return 1;
}

# remote numeric.
# server user any :rest
sub num {
    my ($server, $msg, $source, $user, $num, $message) = @_;

    # If the first digit is 0 (indicating a reply about the local connection), it
    # should be changed to 1 before propagation or sending to a user.
    my $first = \substr($num, 0, 1);
    if ($$first eq '0') {
        $$first = '1';
    }

    # local user.
    if ($user->is_local) {
        $user->sendfrom($source->full, "$num $$user{nick} $message");
    }

    # === Forward ===
    # forward to next hop.
    else {
        $msg->forward_to($user, num => $source, $user, $num, $message);
    }

    return 1;
}

sub links {
    my ($server, $msg, $t_server, $user, $serv_mask, $query_mask) = @_;

    # this is the server match.
    if ($t_server->is_local) {
        return $user->handle_unsafe("LINKS $serv_mask $query_mask");
    }

    # === Forward ===
    $msg->forward_to($t_server, $user, $t_server, $query_mask);

    return 1;
}

sub whois {
    my ($server, $msg, $t_server, $user, $t_user) = @_;

    # this message is for me.
    if ($t_server->is_local) {
        return $user->handle_unsafe("WHOIS $$t_user{nick}");
    }

    # === Forward ===
    $msg->forward_to($t_server, whois => $user, $t_user, $t_server);

    return 1;
}

sub snotice {
    my ($server, $msg, $from_user, $s_serv, $notice, $message) = @_;
    (my $pretty = ucfirst $notice) =~ s/_/ /g;

    # send to users with this notice flag.
    foreach my $user ($pool->actual_users) {
        next unless blessed $user; # during destruction.
        next unless $user->is_mode('ircop');
        next unless $user->has_notice($notice);
        next if $from_user && $user == $from_user;
        $user->server_notice($s_serv, 'Notice', "$pretty: $message");
    }

    # === Forward ===
    $msg->forward(snotice => $s_serv, $notice, $message, $from_user);

    return 1;
}

sub login {
    my ($server, $msg, $user, $str) = @_;
    # $str is a comma-separated list.
    # the first item is always the account name. the rest can be any strings,
    # depending on the builtin account implementation. here, we are only
    # concerned with the account name.
    # consider: if other items are present, should we ignore this entirely here?

    my @items = split /,/, $str;
    $user->do_login($items[0]);

    # === Forward ===
    $msg->forward(login => $user, @items);

    return 1;
}

sub ping {
    my ($server, $msg, $given) = @_;
    $server->sendme("PONG $$me{name} :$given");
}

sub partall {
    my ($server, $msg, $user) = @_;
    $user->do_part_all();

    # === Forward ===
    $msg->forward(part_all => $user);

    return 1;
}

sub invite {
    # :uid INVITE target ch_name
    my ($server, $msg, $user, $t_user, $ch_name) = @_;

    # local user.
    if ($t_user->is_local) {
        $t_user->loc_get_invited_by($user, $ch_name);
        return 1;
    }

    # === Forward ===
    # forward on to next hop.
    $msg->forward_to($t_user, invite => $user, $t_user, $ch_name);

    return 1;
}


sub save {
    my ($server, $msg, $source_serv, $t_user, $time) = @_;

    # only accept the message if the nickTS is correct.
    return if $t_user->{nick_time} != $time;

    $t_user->save_locally;

    #=== Forward ===#
    $msg->forward(save_user => $source_serv, $t_user, $time);

    return 1;
}

# change several user fields at once
sub userinfo {
    my ($server, $msg, $user) = @_;

    # nick ident host nick_time account

    # real host change
    if (length(my $new_real_host = $msg->tag('real_host'))) {
        $user->{host} = $new_real_host;
    }

    # cloak and/or ident changed
    my $new_host  = $msg->tag('host');
    my $new_ident = $msg->tag('ident');
    if (defined $new_host || defined $new_ident) {
        $user->get_mask_changed(
            $new_ident // $user->{ident},
            $new_host  // $user->{cloak},
            $server->name
        );
    }

    #=== Forward ===#
    my %fields = %{ $msg->tags || {} };
    $msg->forward(update_user => $user, %fields);

}

# force nick change
sub fnick {
    my ($server, $msg, $source_serv, $user,
    $new_nick, $new_nick_ts, $old_nick_ts) = @_;

    # not my user
    if (!$user->is_local) {
        $msg->forward_to($user,
            svsnick => $server, $user, $new_nick, $new_nick_ts, $old_nick_ts
        );
        return 1;
    }

    return server::linkage::handle_svsnick(
        $msg, $source_serv, $user, $new_nick,
        $new_nick_ts, $old_nick_ts
    );
}

$mod
