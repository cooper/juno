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

use modes;
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
    },
    FJOIN => {
                  # :sid FJOIN     uid  ch_name ch_time
        params => '-source(server) user *       ts(opt)',
        code   => \&fjoin
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

# new server
sub sid {
    # server any    ts any  any   any  :rest
    # :sid   SID   newsid ts name proto ircd :desc
    my ($server, $msg, @args) = @_;

    # info.
    my %serv;
    $serv{$_}       = shift @args for qw(parent sid time name proto ircd desc);
    $serv{source}   = $server->{sid}; # SID we learned about the server from
    $serv{location} = $server;

    # hidden?
    my $sub = \substr($serv{desc}, 0, 4);
    if (length $sub && $$sub eq '(H) ') {
        $$sub = '';
        $serv{hidden} = 1;
    }

    # do not allow SID or server name collisions.
    my $err = server::protocol::check_new_server(
        $serv{sid},
        $serv{name},
        $server->{name}
    );
    if ($err) {
        $server->conn->done($err);
        return;
    }

    # create a new server.
    my $serv = $pool->new_server(%serv);

    # === Forward ===
    $msg->forward(new_server => $serv);

    return 1;
}

# new user
sub uid {
    # server any ts any   any  any   any  any   any :rest
    # :sid   UID   uid ts modes nick ident host cloak ip  :realname
    my ($server, $msg, @args) = @_;

    my %user;
    $user{$_}       = shift @args for
        qw(server uid nick_time modes nick ident host cloak ip real);
    $user{source}   = $server->{sid}; # SID we learned about the user from
    $user{location} = $server; # server through which this user is reached
    my $mode_str    = delete $user{modes};

    # create a temporary user object.
    my $new_usr_temp = user->new(%user);

    # uid collision?
    if (my $other = $pool->lookup_user($user{uid})) {
        notice(user_identifier_taken =>
            $server->{name},
            $new_usr_temp->notice_info, $new_usr_temp->id,
            $other->notice_info
        );
        $server->conn->done('UID collision') if $server->conn;
        return;
    }

    # nick collision!
    my $used = $pool->nick_in_use($user{nick});

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

    # create a new user.
    my $user = $pool->new_user(%$new_usr_temp);

    # set modes.
    $user->handle_mode_string($mode_str, 1);

    # === Forward ===
    #
    #   JELP:   UID
    #   TS6:    EUID
    #
    $msg->forward(new_user => $user);

    return 1;
}

# user or server quit
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

# nick change
sub nick {
    # user any
    # :uid NICK  newnick
    my ($server, $msg, $user, $newnick) = @_;

    # tell ppl
    $user->send_to_channels("NICK $newnick");
    $user->change_nick($newnick, time);

    # === Forward ===
    $msg->forward(nick_change => $user);

}

# indicates a server is bursting info
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

# indicates the end of server burst
sub endburst {
    # server dummy
    # :sid   ENDBURST
    my ($server, $msg, $serv, $their_time) = @_;
    $server->end_burst();

    # if we haven't sent our own burst yet, do so.
    $serv->send_burst if $serv->{conn} && !$serv->{i_sent_burst};

    # === Forward ===
    $msg->forward(endburst => $serv, $their_time);

}

# user mode change
sub umode {
    # user any
    # :uid UMODE modestring
    my ($server, $msg, $user, $str) = @_;
    $user->do_mode_string_local($str, 1);

    # === Forward ===
    $msg->forward(umode => $user, $str);

}

# PRIVMSG or NOTICE
sub privmsgnotice {
    my ($server, $msg, $source, $command, $target, $message) = @_;
    my @status_modes = grep { $_->{type} == MODE_STATUS }
        values %{ $server->{cmodes} };
    return server::protocol::handle_privmsgnotice(
        @_[0..5],
        channel_lookup  => sub { $pool->lookup_channel(shift) },
        user_lookup     => sub { $pool->lookup_user(shift)    },
        atserv_lookup   => sub { $pool->lookup_server(shift)  },
        supports_atserv => 1,
        opers_prefix    => 'opers',
        opmod_prefix    => '=',
        smask_prefix    => '$$',
        chan_prefixes   => [ map "\@$$_{letter}", @status_modes ],
        chan_pfx_lookup => sub {
            my $prefix = shift;
            my $letter = chop $prefix;
            foreach my $hideous (keys %ircd::channel_mode_prefixes) {
                my $ref = ircd::channel_mode_prefixes{$hideous};
                return $hideous if $ref->[0] eq $letter;
            }
        }
    );
}

# channel join
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

    # split into add and remove
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

    # commit changes
    $user->add_flags(@add);
    $user->remove_flags(@remove);

    # === Forward ===
    $msg->forward(oper => $user, @flags);

}

# mark user as away
sub away {
    # user :rest
    # :uid AWAY  :reason
    my ($server, $msg, $user, $reason) = @_;
    $user->do_away($reason);

    # === Forward ===
    $msg->forward(away => $user);

}

# unmark user as away
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
    my ($server, $msg, $source, $channel, $time, $perspective, $mode_str) = @_;

    # ignore if time is older and take lower time
    my $new_ts = $channel->take_lower_time($time);
    return unless $time == $new_ts;

    # handle the mode string and send to local users.
    $channel->do_mode_string_local($perspective, $source, $mode_str, 1, 1);

    # === Forward ===
    #
    # $source, $channel, $time, $perspective, $mode_str
    #
    # JELP: CMODE
    # TS6:  TMODE
    #
    $msg->forward(cmode => $source, $channel, $time, $perspective, $mode_str);

    return 1;
}

# channel part
sub part {
    # user channel ts   :rest
    # :uid PART  channel time :reason
    my ($server, $msg, $user, $channel, $time, $reason) = @_;

    # take the lower time
    $channel->take_lower_time($time);

    # ?!?!!?!
    if (!$channel->has_user($user)) {
        notice(server_protocol_warning =>
            $server->notice_info,
            "sent PART for ".$user->notice_info.
            "from $$channel{name}, but the user is not there"
        );
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
    # :sid   AUM   name:letter -name
    #
    my ($server, $msg, $serv, @pieces) = @_;

    # keep track of changes to forward
    my @added;      # list of array refs in form [ mode name, letter ]
    my @removed;    # list of string mode names

    foreach my $str (@pieces) {

        # when dash is present, remove by name.
        if (!index($str, '-')) {
            $serv->remove_umode(substr $str, 1);
            push @removed, $str;
            next;
        }

        # when adding, both of these must be present.
        my ($name, $letter) = split /:/, $str, 2;
        next if !length $name || !length $letter;

        $serv->add_umode($name, $letter);
        push @added, [ $name, $letter ];
    }

    # === Forward ===
    #
    # this will probably only be used for JELP
    #
    $msg->forward(add_umodes => $serv, \@added, \@removed);

    return 1;
}

# add channel mode, compact ACM
sub acm {
    # server @rest
    # :sid   ACM   name:letter:type -name
    my ($server, $msg, $serv, @pieces) = @_;

    # keep track of changes to forward
    my @added;      # list of array refs in form [ mode name, letter, type ]
    my @removed;    # list of string mode names

    foreach my $str (@pieces) {

        # when dash is present, remove by name.
        if (!index($str, '-')) {
            $serv->remove_cmode(substr $str, 1);
            push @removed, $str;
            next;
        }

        # ensure that all values are present.
        my ($name, $letter, $type) = split /:/, $str, 3;
        next if
            !length $name   ||
            !length $letter ||
            !length $type;

        $serv->add_cmode($name, $letter, $type);
        push @added, [ $name, $letter, $type ];
    }

    # === Forward ===
    #
    # this will probably only be used for JELP
    #
    $msg->forward(add_cmodes => $serv, \@added, \@removed);

    return 1;
}

# channel burst
sub sjoin {
    # server         any     ts   any   :rest
    # :sid   SJOIN   channel time users :modestr
    my $nicklist = pop;
    my ($server, $msg, $source_serv, $ch_name, $ts,
        $mode_str_modes, @mode_params) = @_;

    # UPDATE CHANNEL TIME
    #=================================

    # maybe we have a channel by this name, otherwise create one.
    my ($channel, $new) = $pool->lookup_or_create_channel($ch_name, $ts);

    # take the new time if it's less recent.
    # note that modes are not handled here (the second arg says not to)
    # because they are handled manually in a prettier way for CUM.
    my $old_time = $channel->{time};
    my $new_time = $channel->take_lower_time($ts, 1);

    # CONVERT MODES
    #=================================

    # store modes existing and incoming modes.
    my $old_modes = $channel->all_modes;
    my $new_modes = modes->new_from_string(
        $source_serv,
        join(' ', $mode_str_modes, @mode_params),
        1 # over protocol
    );

    # accept new modes if the accepted TS is equal to the incoming TS.
    # clear old modes if the accepted TS is older than the stored TS and
    # is not equal to zero (in which case all modes are preserved).
    #
    # The interpretation depends on the channelTS and the current TS of the channel.
    # If either is 0, set the channel's TS to 0 and accept all modes. Otherwise, if
    # the incoming channelTS is greater (newer), ignore the incoming simple modes
    # and statuses and join and propagate just the users. If the incoming channelTS
    # is lower (older), wipe all modes and change the TS, notifying local users of
    # this but not servers (invites may be cleared). In the latter case, kick on
    # split riding may happen: if the key (+k) differs or the incoming simple modes
    # include +i, kick all local users, sending KICK messages to servers.
    #
    (my $accept_new_modes)++ if $new_time == $ts;
    my $clear_old_modes = $new_time < $old_time && $new_time != 0;

    # HANDLE USERS
    #====================

    # determine the user mode string.
    my ($uid_letters, @uids, @good_users) = '+';
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

        # add the letters in the perspective of $source_serv.
        $uid_letters .= $modes;
        push @uids, $uid for 1 .. length $modes;
    }

    # ACCEPT AND RESET MODES
    #=================================

    # okay, now we're ready to apply the modes.
    if ($accept_new_modes) {

        # create a moderef based on the status modes we just extracted.
        my $uid_modes = modes->new_from_string(
            $source_serv,
            join(' ', $uid_letters, @uids),
            1 # over protocol
        );

        # combine status modes with the other modes in the message.
        $new_modes->merge_in($uid_modes);

        # determine the difference between the old mode string and the new one.
        my $changes = modes::difference(
            $old_modes,         # modes before any changes
            $new_modes,         # incoming modes
            !$clear_old_modes   # ignore missing modes unless $clear_old_modes
        );

        # handle the modes locally.
        # ($source, $modes, $force, $organize)
        $channel->do_modes_local($source_serv, $changes, 1, 1);

    }

    # delete the channel if no users
    $channel->destroy_maybe if $new;

    # === Forward ===
    #
    #   all channel modes will be propagated,
    #   regardless of whether they were present or absent
    #   in this particular SJOIN message.
    #
    #   users will be sent with their current statuses,
    #   if any apply, also without regard to this message.
    #
    #   JELP:   SJOIN
    #   TS6:    SJOIN
    #
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

    # ($source, $topic, $setby, $time, $check_text)
    $channel->do_topic($source, $topic, $source->full, time);

    # === Forward ===
    $msg->forward(topic => $source, $channel, $channel->{time}, $topic);

    return 1
}

sub topicburst {
    # source            channel ts   any   ts   :rest
    # :sid   TOPICBURST channel ts   setby time :topic
    my ($server, $msg, $s_serv, $channel, $ts, $setby, $topic_ts, $topic) = @_;

    # Accept if...
    my $accept =
        !$channel->{topic}              ||  # the channel has no topic
         $channel->{time} > $ts         ||  # the provided channelTS is older
        ($channel->{time} == $ts && $channel->{topic}{time} < $topic_ts);
        # the channelTS are equal and the provided topicTS is newer
    return unless $accept;

    # (issue #132) we don't have to check if the topic is a shorter version of
    # the existing one here because TOPICBURST only accepts topics with a newer
    # topicTS. if it is newer, it will always win.

    # ($source, $topic, $setby, $time, $check_text)
    my $old = $channel->{topic};
    $channel->do_topic($s_serv, $topic, $setby, $topic_ts, 1);

    # === Forward ===
    $msg->forward(topicburst =>
        $channel,
        source      => $s_serv,
        old         => $old,
        channel_ts  => $ts
    );

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

    # If the first digit is 0 (indicating a reply about the local connection),
    # it should be changed to 1 before propagation or sending to a user.
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
    foreach my $user ($pool->real_users) {
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
        $msg->forward_to($user, force_nick =>
            $source_serv, $user, $new_nick, $new_nick_ts, $old_nick_ts);
        return 1;
    }

    return server::linkage::handle_svsnick(
        $msg, $source_serv, $user, $new_nick,
        $new_nick_ts, $old_nick_ts
    );
}

# force join
sub fjoin {
    my ($server, $msg, $source_serv, $user, $ch_name, $ch_time) = @_;

    # not my user
    if (!$user->is_local) {
        $msg->forward_to($user, force_join =>
            $source_serv, $user, $ch_name, $ch_time);
        return 1;
    }

    # if the channel time is present, the channel must exist.
    if (defined $ch_time) {
        my $channel = $pool->lookup_channel($ch_name) or return;

        # incorrect time
        if ($ch_time != $channel->{time}) {
            L(
                "Rejecting FJOIN with incorrect channel TS from ".
                $source_serv->notice_info
            );
            return;
        }

        # attempt local join. this can fail. it will notify other servers
        # if the user did successfully join.
        return $channel->attempt_local_join($user);
    }

    # if no channel time is provided, we are forcing the join.
    # ($user, $new, $key, $force)
    my ($channel, $new) = $pool->lookup_or_create_channel($ch_name);
    return $channel->attempt_local_join($user, $new, undef, 1);
}

$mod
