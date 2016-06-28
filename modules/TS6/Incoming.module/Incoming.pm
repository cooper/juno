# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-Mac-mini.local
# Fri Aug  8 22:47:08 EDT 2014
# Incoming.pm
#
# @name:            'TS6::Incoming'
# @package:         'M::TS6::Incoming'
# @description:     'basic set of TS6 command handlers'
#
# @depends.modules: 'TS6::Base'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::TS6::Incoming;

use warnings;
use strict;
use 5.010;

use M::TS6::Utils qw(
    user_from_ts6   server_from_ts6     obj_from_ts6
    uid_from_ts6    sid_from_ts6        mode_from_prefix_ts6
);

use utils qw(channel_str_to_list notice);

our ($api, $mod, $pool, $me);

our %ts6_incoming_commands = (
    SID => {
                  # :sid SID       name hops sid :desc
        params => '-source(server) *    *    *   :rest',
        code   => \&sid
    },
    EUID => {
                   # :sid EUID      nick hopcount nick_ts umodes ident cloak ip  uid host act :realname
        params  => '-source(server) *    *        ts      *      *     *     *   *   *    *   :rest',
        code    => \&euid
    },
    SJOIN => {
                  # :sid SJOIN     ch_time ch_name mode_str mode_params... :nicklist
        params => '-source(server) ts      *       *        @rest',
        code   => \&sjoin
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
    TMODE => {     # :src TMODE ch_time ch_name      mode_str mode_params...
        params  => '-source     ts      channel      :rest', # just to join them together
        code    => \&tmode
    },
    JOIN => {
                  # :src          JOIN  ch_time  ch_name
        params => '-source(user)        ts       *(opt)',
        code   => \&_join
    },
    ENCAP => {    # :src   ENCAP serv_mask  sub_cmd  sub_params...
        params => '-source       *          *        @rest',
        code   => \&encap
    },
    KILL => {
                   # :src   KILL    uid     :path
        params  => '-source         user    :rest',
        code    => \&skill
    },
    PART => {
                   # :uid PART    ch_name_multi  :reason
        params  => '-source(user) *              :rest(opt)',
        code    => \&part
    },
    QUIT => {
                   # :src QUIT   :reason
        params  => '-source      :rest',
        code    => \&quit
    },
    KICK => {
                   # :source KICK channel  target_user :reason
        params  => '-source       channel  user        :rest(opt)',
        code    => \&kick
    },
    NICK => {
                   # :uid NICK    newnick
        params  => '-source(user) any',
        code    => \&nick
    },
    PING => {
                   # :sid PING          server.name dest_sid|dest_name
        params  => '-source(server,opt) *           *(opt)',
        code    => \&ping
    },
    PONG => {
                   # :sid PONG      server.name dest_sid|dest_name
        params  => '-source(server) *           *(opt)',
        code    => \&pong
    },
    AWAY => {
                   # :uid AWAY    :reason
        params  => '-source(user) :rest(opt)',
        code    => \&away
    },
    TB => {
                   # :sid TB        channel topic_ts setby :topic
        params  => '-source(server) channel ts       *     :rest',
        code    => \&tb
    },
    TOPIC => {
                  # :uid   TOPIC channel :topic
        params => '-source(user) channel :rest',
        code   => \&topic
    },
    WALLOPS => {
                  # :source WALLOPS :message
        params => '-source          :rest',
        code   => \&wallops
    },
    CHGHOST => {
                  # :source CHGHOST uid   newhost
        params => '-source          user  *',
        code   => \&chghost
    },
    SQUIT => {
                  # :sid SQUIT         sid    :reason
        params => '-source(server,opt) server :rest',
        code   => \&squit
    },
    WHOIS => {
                  # :uid WHOIS   sid|uid    :query(e.g. nickname)
        params => '-source(user) *          :rest',
        code   => \&whois
    },
    MODE => {
                  # :source MODE uid|channel +modes params
        params => '-source @rest',
        code   => \&mode
    }
);

sub handle_numeric {
    my ($server, $msg) = @_;
    my @args = $msg->params;
    my $num  = $msg->command;

    # find the source.
    my $source_serv = obj_from_ts6($msg->{source});
    if (!$source_serv || !$source_serv->isa('server')) {
        return;
    }

    # find the user.
    my $user = obj_from_ts6(shift @args);
    if (!$user || !$user->isa('user')) {
        return;
    }

    # create the message
    $args[$#args] = ':'.$args[$#args] if index($args[$#args], ' ') != -1;
    my $message = join ' ', @args;

    # local user.
    if ($user->is_local) {
        $user->sendfrom($source_serv->full, "$num $$user{nick} $message");
    }

    # === Forward ===
    else {
        $msg->forward_to($user, num => $source_serv, $user, $num, $message);
    }

    return 1;
}

# SID
#
# source:       server
# propagation:  broadcast
# parameters:   server name, hopcount, sid, server description
sub sid {
    my ($server, $msg, $source_serv, $s_name, $hops, $sid, $desc) = @_;

    # info.
    my %s = (
        parent   => $source_serv,       # the server which is the actual parent
        source   => $server->{sid},     # SID of the server who told us about him
        location => $server,            # nearest server we have a physical link to
        ircd     => -1,                 # not applicable in TS6
        proto    => -1,                 # not applicable in TS6
        time     => time                # first time server became known (best bet)
    );

    # if the server description has (H), it's to be hidden.
    my $sub = \substr($desc, 0, 4);
    if (length $sub && $$sub eq '(H) ') {
        $$sub = '';
        $s{hidden} = 1;
    }

    # more info.
    @s{ qw(name desc ts6_sid sid) } = ($s_name, $desc, $sid, sid_from_ts6($sid));

    # do not allow SID or server name collisions.

    if (my $err = utils::check_new_server($s{sid}, $s{name}, $server->{name})) {
        $server->conn->done($err);
        return;
    }

    # create a new server.
    my $serv = $pool->new_server(%s);
    $serv->set_functions(
        uid_to_user => \&user_from_ts6,
        user_to_uid => \&ts6_uid
    );

    # the TS6 IRCd will be considered the same as the parent server.
    # I think this will be okay because unknown modes would not be
    # forwarded anyway, and extra modes would not cause any trouble.
    $serv->{ts6_ircd} = $source_serv->{ts6_ircd} || $server->{ts6_ircd};

    # add mode definitions.
    M::TS6::Utils::register_modes($serv);

    # === Forward ===
    $msg->forward(new_server => $serv);

    return 1;
}

# EUID
#
# charybdis TS6
#
# capab         EUID
# source:       server
# parameters:   nickname, hopcount, nickTS, umodes, username, visible hostname,
#               IP address, UID, real hostname, account name, gecos
# propagation:  broadcast
#
# ts6-protocol.txt:315
#
sub euid {
    my ($server, $msg, $source_serv, @rest) = @_;
    my %u = (
        server   => $source_serv,       # the actual server the user connects from
        source   => $server->{sid},     # SID of the server who told us about him
        location => $server             # nearest server we have a physical link to
    );
    $u{$_} = shift @rest foreach qw(
        nick ts6_dummy nick_time umodes ident
        cloak ip ts6_uid host account_name real
    );
    my ($mode_str, undef) = (delete $u{umodes}, delete $u{ts6_dummy});

    $u{time} = $u{nick_time};                   # for compatibility
    $u{host} = $u{cloak} if $u{host} eq '*';    # host equal to visible
    $u{uid}  = uid_from_ts6($u{ts6_uid});       # convert to juno UID

    # create a temporary user which will be used only for outgoing commands.
    my $new_usr_temp = user->new(%u);

    # uid collision!
    if (my $other = $pool->lookup_user($u{uid})) {
        notice(user_identifier_taken =>
            $server->{name},
            $new_usr_temp->notice_info, $u{uid},
            $other->notice_info
        );
        $server->conn->done('UID collision') if $server->conn;
        return;
    }

    # nick collision!
    my $used = $pool->lookup_user_nick($u{nick});
    if ($used) {
        my ($save_old, $save_new);

        # the new user steals the nick.
        if ($used->{nick_time} > $u{nick_time}) {
            $save_old = 1;
        }

        # the existing user keeps the nick.
        elsif ($used->{nick_time} < $u{nick_time}) {
            $save_new = 1;
        }

        # they both lose the nick.
        else {
            $save_old = 1;
            $save_new = 1;
        }

        # if we can't save the new user, kill him.
        if ($save_new && !$server->has_cap('save')) {
            $server->fire_command(kill => $me, $new_usr_temp, 'Nick collision');
            return;
        }

        # note: SAVE is always sent with the existing nickTS.
        # if the provided TS is not the current nickTS, SAVE is ignored.
        # Upon handling a valid SAVE, however, the nickTS becomes 100.

        # send out a SAVE for the existing user
        # and broadcast a local nickchange to his UID.
        if ($save_old) {
            $server->fire_command(save_user => $me, $used);
            $used->save_locally;
        }

        # send out a SAVE for the new user
        # and change his nick to his TS6 UID locally.
        if ($save_new) {
            $server->fire_command(save_user => $me, $new_usr_temp);
            my $old_nick  = $u{nick};
            $u{nick}      = $new_usr_temp->{nick} = $u{uid};
            $u{nick_time} = 100;
            notice(user_saved => $new_usr_temp->notice_info, $old_nick);
        }

    }

    # create a new user with the given modes.
    my $user = $pool->new_user(%u);
    $user->handle_mode_string($mode_str, 1);

    # === Forward ===
    #
    #   JELP:   UID
    #   TS6:    EUID
    #
    $msg->forward(new_user => $user);

    return 1;
}

# SJOIN
#
# source:       server
# propagation:  broadcast
# parameters:   channelTS, channel, simple modes, opt. mode parameters..., nicklist
#
# ts6-protocol.txt:821
#
sub sjoin {
    my $nicklist = pop;
    my ($server, $msg, $source_serv, $ts, $ch_name, $mode_str, @mode_params) = @_;

    # UPDATE CHANNEL TIME
    #=================================

    # maybe we have a channel by this name, otherwise create one.
    my $channel = $pool->lookup_or_create_channel($ch_name, $ts);

    # take the new time if it's less recent.
    # note that modes are not handled here (the second arg says not to)
    # because they are handled manually in a prettier way for SJOIN.
    my $old_time = $channel->{time};
    my $new_time = $channel->take_lower_time($ts, 1);

    # CONVERT MODES
    #=================================

    # store mode string before any possible changes.
    # this now includes status modes as well,
    # which were previously handled separately.
    my $old_mode_str = $channel->mode_string_all($me);

    # the incoming mode string must be converted to the perspective of this
    # server. this is necessary in case our own modes are unset.
    $mode_str = $server->convert_cmode_string($me, $mode_str, 1);

    # $old_mode_str and $mode_str are now both in the perspective of $me.

    # their TS is either older or the same.
    #
    # 1. wipe out our old modes.
    # 2. accept all new modes.
    # 3. propagate all simple modes (not just the difference).
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
    my $clear_old_modes = $new_time < $old_time;

    # HANDLE USERS
    #====================

    my ($uids_modes, @uids, @good_users) = '+';
    foreach my $str (split /\s+/, $nicklist) {
        my ($prefixes, $uid) = ($str =~ m/^(\W*)([0-9A-Z]+)$/) or next;
        my $user     = user_from_ts6($uid) or next;
        my @prefixes = split //, $prefixes;

        # this user does not physically belong to this server; ignore.
        next if $user->{location} != $server;

        # join the new user.
        push @good_users, $user;
        unless ($channel->has_user($user)) {
            $channel->cjoin($user, $channel->{time});
            $channel->sendfrom_all($user->full, "JOIN $$channel{name}");
            $channel->fire_event(user_joined => $user);
        }

        # no prefixes or not accepting the prefixes.
        next unless length $prefixes && $accept_new_modes;

        # add the modes (these are in the perspective of $server)
        my $modes = join '', map mode_from_prefix_ts6($server, $_), @prefixes;
        $uids_modes .= $modes;
        push @uids, $user->{uid} for 1 .. length $modes;

    }

    # ACCEPT AND RESET MODES
    #=================================

    # okay, now we're ready to apply the modes.
    if ($accept_new_modes) {

        # $uids_modes are currently in the perspective of the TS 6 server.
        # note that this does not provide parameters; they are already in the
        # perspective of the current server (i.e., in JELP format).
        $uids_modes = $server->convert_cmode_string($me, $uids_modes, 1);

        # combine status modes with the other modes in the message.
        # $mode_str, $uids_modes, @mode_params, @uids
        # are now all in the perspective of $serv.
        my $command_mode_str = join(' ',
            '+'.$mode_str.$uids_modes,
            @mode_params,
            @uids
        );

        # determine the difference between
        my $difference = $me->cmode_string_difference(
            $old_mode_str,      # all former modes
            $command_mode_str,  # all new modes including statuses
            0,                  # combine ban lists? not used in TS6
            !$clear_old_modes   # do not remove modes missing from $old_mode_str
        );

        # handle the mode string locally.
        # note: do not supply a $over_protocol sub because
        # this generated string uses juno UIDs.
        $channel->do_mode_string_local($me, $source_serv, $difference, 1, 1)
            if $difference;

    }

    # === Forward DURING BURST ===
    #
    #   during burst, all channel modes will be propagated,
    #   regardless of whether they were present or absent
    #   in this particular SJOIN message.
    #
    #   users will be sent with their current statuses,
    #   if any apply, also without regard to this message.
    #
    #   JELP:   CUM
    #   TS6:    SJOIN
    #
    if ($server->{is_burst}) {
        $msg->forward(channel_burst => $channel, $source_serv, @good_users);
        return 1;
    }

    # === Forward OUTSIDE OF BURST ===
    #
    #   if their TS was bad, the modes were not applied.
    #       - no modes will be propagated (+).
    #
    #   if their TS was good, the modes were applied.
    #       - the modes in the message will be propagated,
    #       - not necessarily all the modes of the channnel.
    #
    #   JELP:   JOIN, CMODE
    #   TS6:    SJOIN
    #
    $mode_str = '+' unless $accept_new_modes;
    $msg->forward(join_with_modes =>
        $channel,       # $channel   = channel object
        $source_serv,   # $serv      = server source of the message
        $mode_str,      # $mode_str  = mode string being sent
        $source_serv,   # $mode_serv = server object for mode perspective
        @good_users     # @members   = channel members (user objects)
    );

    return 1;
}

# PRIVMSG
#
# source:       user
# parameters:   msgtarget, message
#
# Sends a normal message (PRIVMSG) to the given target.
#
# The target can be:
#
# - a client
#   propagation: one-to-one
#
# - a channel name
#   propagation: all servers with -D users on the channel
#   (cmode +m/+n should be checked everywhere, bans should not be checked
#   remotely)
#
# - TODO: Complex PRIVMSG
#   a status character ('@'/'+') followed by a channel name, to send to users
#   with that status or higher only.
#   capab:          CHW
#   propagation:    all servers with -D users with appropriate status
#
# - TODO: Complex PRIVMSG
#   '=' followed by a channel name, to send to chanops only, for cmode +z.
#   capab:          CHW and EOPMOD
#   propagation:    all servers with -D chanops
#
# - TODO: Complex PRIVMSG
#   a user@server message, to send to users on a specific server. The exact
#   meaning of the part before the '@' is not prescribed, except that "opers"
#   allows IRC operators to send to all IRC operators on the server in an
#   unspecified format.
#   propagation: one-to-one
#
# - TODO: Complex PRIVMSG
#   a message to all users on server names matching a mask ('$$' followed by mask)
#   propagation: broadcast
#   Only allowed to IRC operators.
#
# - TODO: Complex PRIVMSG
#   a message to all users with hostnames matching a mask ('$#' followed by mask).
#   Note that this is often implemented poorly.
#   propagation: broadcast
#   Only allowed to IRC operators.
#
# In charybdis TS6, services may send to any channel and to statuses on any
# channel.
#
#
# NOTICE
#
# source:       any
# parameters:   msgtarget, message
#
# As PRIVMSG, except NOTICE messages are sent out, server sources are permitted
# and most error messages are suppressed.
#
# Servers may not send '$$', '$#' and opers@server notices. Older servers may
# not allow servers to send to specific statuses on a channel.
#
#
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
            notice(server_protocol_warning =>
                $server->name, $server->id,
                "sent PRIVMSG with a '\$\$' broadcast target, but this is ".
                "only permitted from user sources according to TS6 spec"
            );
            return;
        }

        # consider each server that matches
        # consider: what if a server is hidden? would this skip it?
        my %done;
        foreach my $serv ($pool->lookup_server_mask($mask)) {
            my $location = $serv->{location} || $serv; # for $me, location = nil

            # already did or the server is connected via the source server
            next if $done{$server};
            next if $location == $server;

            # if the server is me, send to all my users
            if ($serv == $me) {
                $_->sendfrom($source->full, "$command $$_{nick} :$message")
                    foreach $pool->local_users;
                $done{$me} = 1;
                next;
            }

            # === Forward ===
            #
            # otherwise, forward it
            #
            $msg->forward_to($serv, privmsgnotice_server_mask =>
                $command, $source,
                $mask,    $message
            );

            $done{$location} = 1;
        }

        return 1;
    }

    # is it a user?
    my $tuser = user_from_ts6($target);
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

# TMODE
#
# source:       any
# parameters:   channelTS, channel, cmode changes, opt. cmode parameters...
#
# ts6-protocol.txt:937
#
sub tmode {
    my ($server, $msg, $source, $ts, $channel, $mode_str) = @_;

    # take the lower time.
    my $new_ts = $channel->take_lower_time($ts);
    return unless $ts == $new_ts;

    # convert the mode string to this server.
    # this is not necessary for translating the modes, but it is
    # instead used because it will convert TS6 UIDs to juno UIDs.
    #
    $mode_str = $server->convert_cmode_string($me, $mode_str, 1);

    # then, do the mode string from the perspective of this server.
    $channel->do_mode_string_local($me, $source, $mode_str, 1, 1);

    # === Forward ===
    #
    #   mode changes will be propagated only if the TS was good.
    #
    #   JELP:   CMODE
    #   TS6:    TMODE
    #
    # $source, $channel, $time, $perspective, $mode_str
    # the perspective is $me because it was converted.
    #
    $msg->forward(cmode => $source, $channel, $channel->{time}, $me, $mode_str);

}

# JOIN
#
# 1.
# source:       user
# parameters:   '0' (one ASCII zero)
# propagation:  broadcast
#
# 2.
# source:       user
# parameters:   channelTS, channel, '+' (a plus sign)
# propagation:  broadcast
#
# ts6-protocol.txt:397
#
sub _join {
    my ($server, $msg, $user, $ts, $ch_name) = @_;

    # JOIN 0 - part all channels.
    if ($ts eq '0' && !length $ch_name) {
        $user->do_part_all();
        $msg->forward(part_all => $user);
        return 1;
    }

    # at this point, there must be a channel.
    return unless length $ch_name;

    # find or create.
    my ($channel, $new) = $pool->lookup_or_create_channel($ch_name, $ts);

    # take lower time if necessary, and add the user to the channel.
    $channel->take_lower_time($ts) unless $new;
    $channel->cjoin($user, $ts)    unless $channel->has_user($user);

    # for each user in the channel, send a JOIN message.
    $channel->sendfrom_all($user->full, "JOIN $$channel{name}");

    # fire after join event.
    $channel->fire_event(user_joined => $user);

    # === Forward ===
    $msg->forward(join => $user, $channel, $ts);

    return 1;
}


# ENCAP
#
# source:       any
# parameters:   target server mask, subcommand, opt. parameters...
#
# ts6-protocol.txt:253
#
sub encap {
    my ($server, $msg, $source, $serv_mask, $cmd, @rest) = @_;

    my (%done, $doing_me);
    foreach my $serv ($pool->lookup_server_mask($serv_mask)) {
        my $location = $serv->{location} || $serv; # for $me, location = nil

        # already did or the server is connected via the source server
        next if $done{$server};
        next if $location == $server;

        # if the server is me
        if ($serv == $me) {
            $doing_me = 1;
            next;
        }

        # === Forward ===
        #
        # TODO: !!! this will have to actually break down
        # what the commands are and fire the appropriate outgoing
        # handlers, since other protocols do not have ENCAP
        #

        $done{$location} = 1;
    }

    return 1 unless $doing_me;

    # TODO: make a better way to handle ENCAP stuff
    if ($cmd eq 'LOGIN') {
        # source: user
        # parameters: account name
        return login($server, $msg, $source, @rest);
    }
    if ($cmd eq 'SU') {
        # source: services server
        # parameters: user, new login name
        my $user = $pool->lookup_user(uid_from_ts6($rest[0])) or return;
        if (!length $rest[1]) {
            delete $user->{account};
            L("TS6 logout $$user{nick}");
            return 1;
        }
        return login($server, $msg, $user, $rest[1]);
    }

    return 1;
}

# LOGIN
#
# encap only
# source:       user
# parameters:   account name
#
# ts6-protocol.txt:505
#
sub login {
    my ($server, $msg, $user, $act_name) = @_;
    L("TS6 login $$user{nick} as $act_name");
    $user->{account} = { name => $act_name };
    return 1;
}

# KILL
#
# source:       any
# parameters:   target user, path
# propagation:  broadcast
#
# ts6-protocol.txt:444
#
sub skill {
    # source            user  :rest
    # :source     KILL  uid   :path
    # path is the source and the reason; e.g. server!host!iuser!nick (go away)
    my ($server, $msg, $source, $tuser, $path) = @_;

    # this ignores non-local users.
    my $reason = (split / /, $path, 2)[1];
    $reason = substr $reason, 1, -1;

    # local; destroy connection.
    if ($tuser->is_local) {
        $tuser->get_killed_by($source, $reason);
    }

    # not local; just dispose of it.
    else {
        my $name = $source->name;
        $tuser->quit("Killed ($name ($reason))");
    }

    # === Forward ===
    $msg->forward(kill => $source, $tuser, $reason);

}

# PART
#
# source:       user
# parameters:   comma separated channel list, message
#
# ts6-protocol.txt:617
#
sub part {
    my ($server, $msg, $user, $ch_str, $reason) = @_;
    my @channels = channel_str_to_list($ch_str);
    foreach my $channel (@channels) {

        # ?!?!!?!
        if (!$channel->has_user($user)) {
            L("attempting to remove $$user{nick} from $$channel{name} ".
                "but that user isn't on that channel");
            return;
        }

        # remove the user and tell others
        $channel->handle_part($user, $reason);

    }

    # === Forward ===
    $msg->forward(part => $user, \@channels, $reason);

}

# QUIT
#
# source:       user
# parameters:   comment
#
# ts6-protocol.txt:696
#
sub quit {
    # source   :rest
    # :source QUIT   :reason
    my ($server, $msg, $source, $reason) = @_;
    return if $source == $me;
    return unless $source->{location} == $server->{location};

    # delete the server or user
    $source->quit($reason);

    # === Forward ===
    $msg->forward(quit => $source, $reason);

    return 1;
}

# KICK
#
# source:       any
# parameters:   channel, target user, opt. reason
# propagation:  broadcast
#
# ts6-protocol.txt:433
#
sub kick {
    my ($server, $msg, $source, $channel, $t_user, $reason) = @_;
    # note: we're technically supposed to check for $source's op if
    # it's a user, iff the channel TS is zero.

    $channel->user_get_kicked($t_user, $source, $reason);

    # === Forward ===
    $msg->forward(kick => $source, $channel, $t_user, $reason);

    return 1;
}

# NICK
#
# 1.
# source: user
# parameters: new nickname, new nickTS
# propagation: broadcast
#
# 2.
# source: server
# parameters: nickname, hopcount, nickTS, umodes, username, hostname, server, gecos
#
# ts6-protocol.txt:562
#
sub nick {
    # user any
    # :uid NICK  newnick
    my ($server, $msg, $user, $newnick) = @_;

    # tell ppl
    $user->send_to_channels("NICK $newnick");
    $user->change_nick($newnick, time);

    # === Forward ===
    $msg->forward(nickchange => $user);

    return 1;
}

# PING
#
# source:       any
# parameters:   origin, opt. destination server
#
# ts6-protocol.txt:700
#
sub ping {
    my ($server, $msg, $source_serv, $origin_name, $dest_serv_str) = @_;

    # so apparently some things (e.g. atheme) use a server name destination
    my $dest_serv =
        server_from_ts6($dest_serv_str) ||
        $pool->lookup_server_name($dest_serv_str)
        if length $dest_serv_str;

    # no destination or destination is me.
    # I get to reply to this with a PONG.
    if (!$source_serv || !$dest_serv || $dest_serv == $me) {
        $server->fire_command(pong => $me, $server);
        return 1;
    }

    # otherwise, forward it on.
    $msg->forward_to($dest_serv, ping => $source_serv, $dest_serv);

    return 1;
}

# PONG
#
# source:       server
# parameters:   origin, destination
#
# ts6-protocol.txt:714
#
sub pong {
    my ($server, $msg, $source_serv, $origin_name, $dest_serv_str) = @_;

    # the first pong indicates the end of a burst.
    if ($source_serv->{is_burst}) {
        my $time    = delete $source_serv->{is_burst};
        my $elapsed = time - $time;
        $source_serv->{sent_burst} = time;

        L("end of burst from $$source_serv{name}");
        notice(server_endburst =>
            $source_serv->{name}, $source_serv->{sid}, $elapsed);

        # === Forward ===
        $msg->forward(endburst => $source_serv, time);

        return 1;
    }

    # so apparently some things (e.g. atheme) use a server name destination
    my $dest_serv =
        server_from_ts6($dest_serv_str) ||
        $pool->lookup_server_name($dest_serv_str)
        if length $dest_serv_str;

    # is there a destination other than me?
    if ($dest_serv && $dest_serv != $me) {

        # === Forward ===
        $msg->forward_to($dest_serv, pong => $source_serv, $dest_serv);

    }
    else {
        # this pong is for us
    }

    return 1;
}

# AWAY
#
# source:       user
# propagation:  broadcast
# parameters:   opt. away reason
#
# ts6-protocol.txt:215
#
sub away {
    my ($server, $msg, $user, $reason) = @_;

    # if the reason is not present, the user has returned.
    if (!length $reason) {
        $user->do_away();

        # === Forward ===
        $msg->forward(return_away => $user);

        return 1;
    }

    # otherwise, set the away reason.
    $user->do_away($reason);

    # === Forward ===
    $msg->forward(away => $user);

    return 1;
}

# TOPIC
#
# source:       user
# propagation:  broadcast
# parameters:   channel, topic
#
# ts6-protocol.txt:957
#
sub topic {
    # -source(user) channel :rest
    # :uid TOPIC    channel :topic
    my ($server, $msg, $user, $channel, $topic) = @_;

    # tell users.
    $channel->sendfrom_all($user->full, "TOPIC $$channel{name} :$topic");

    # set it
    if (length $topic) {
        $channel->{topic} = {
            setby  => $user->full,
            time   => time,
            topic  => $topic,
            source => $server->{sid}
        };
    }
    else {
        delete $channel->{topic}
    }

    # === Forward ===
    $msg->forward(topic => $user, $channel, $channel->{time}, $topic);

    return 1;
}

# TB
#
# capab:        TB
# source:       server
# propagation:  broadcast
# parameters:   channel, topicTS, opt. topic setter, topic
#
# ts6-protocol.txt:916
#
sub tb {
    # -source(server)   channel ts       *     :rest
    # :sid TB           channel topic_ts setby :topic
    my ($server, $msg, $s_serv, $channel, $topic_ts, $setby, $topic) = @_;

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

    # set it.
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

# WALLOPS
#
# 1.
# source:       user
# parameters:   message
# propagation:  broadcast
# In charybdis TS6, includes non-opers.
#
# 2.
# source:       server
# parameters:   message
# propagation:  broadcast
# In charybdis TS6, this may only be sent to opers.
#
# ts6-protocol.txt:1140
#
# :source WALLOPS :message
# -source         :rest
#
sub wallops {
    my ($server, $msg, $source, $message) = @_;

    # is it a server or a user? this determines whether it is oper-only.
    my $source_serv = $source->isa('server');

    $pool->fire_wallops_local($source, $message, $source_serv);

    #=== Forward ===#
    $msg->forward(wallops => $source, $message);

    return 1;
}

# CHGHOST
#
# charybdis TS6
# source:       any
# propagation:  broadcast
# parameters:   client, new hostname
#
sub chghost {
    my ($server, $msg, $source, $user, $new_host) = @_;
    $user->get_mask_changed($user->{ident}, $new_host);

    #=== Forward ===#
    $msg->forward(chghost => $source, $user, $new_host);

    return 1;
}

# SQUIT
#
# parameters:   target server, comment
#
sub squit {
    my ($server, $msg, $s_serv, $t_serv, $comment) = @_;

    # the provided $s_serv will either be a server object or
    # undef if there was no source.

    # if the target server is me or the source server, close the link.
    if (!$s_serv && $t_serv == $me) {
        notice(server_closing => $server->name, $server->id, $comment);
        $server->conn->done($comment);
        $t_serv = $server; # forward SQUIT with their UID, not ours
    }

    # can't squit self without a direct connection.
    elsif ($t_serv == $me) {
        notice(
            server_protocol_error =>
            $s_serv->name, $s_serv->id,
            'attempted to SQUIT the local server '.$me->{name}
        );
        $server->conn->done("Attempted to SQUIT $$me{name}");
        return; # don't forward
    }

    # otherwise, we can simply quit the target server.
    else {
        $t_serv->quit($comment);
    }

    #=== Forward ===#
    $msg->forward(quit => $t_serv, $comment);

    return 1;
}

# WHOIS
# source: user
# parameters: hunted, target nick
#
sub whois {
    my ($server, $msg, $s_user, $target, $query) = @_;
    # $s_user is the user doing the query
    # $target ought to be a string SID or UID
    # $query is the raw query itself, such as a nickname

    $target = obj_from_ts6($target);
    if (!$target) {
        notice(server_protocol_warning =>
            $server->name, $server->id,
            "provided invalid target server in remote WHOIS"
        );
        return;
    }

    # this could be a user or server object.
    # either way, forward this onto physical location.
    my $loc = $target->{location};

    # it's me!
    if ($loc == $me) {
        return $s_user->handle_unsafe("WHOIS $query");
    }

    # if we're forwarding, actually look up the user.
    my $t_user = $pool->lookup_user_nick($query);
    if (!$t_user) {
        notice(server_protocol_warning =>
            $server->name, $server->id,
            "sent a remote WHOIS query with an unknown nick; cannot forward"
        );
        return;
    }

    #=== Forward ===#
    $msg->forward_to($t_user, whois => $s_user, $t_user, $loc);

    return 1;
}

# MODE
#
# 1.
# source:       user
# parameters:   client, umode changes
# propagation:  broadcast
#
# Propagates a user mode change. The client parameter must refer to the same user
# as the source.
#
# Not all umodes are propagated to other servers.
#
# 2.
# source:       any
# parameters:   channel, cmode changes, opt. cmode parameters...
#
# Propagates a channel mode change.
#
# This is deprecated because the channelTS is not included. If it is received,
# it should be propagated as TMODE.
#
sub mode {
    my ($server, $msg, $source, $target_str, $mode_str, @params) = @_;

    # if it's a channel, this is the deprecated form.
    # it will be forwarded on with the channelTS as TMODE.
    my $target = $pool->lookup_channel($target_str);
    if ($target && $target->isa('channel')) {

        # the $mode_str actually does not include parameters yet
        $mode_str = join ' ', $mode_str, @params;

        # convert the mode string to this server.
        # this is not necessary for translating the modes, but it is
        # instead used because it will convert TS6 UIDs to juno UIDs.
        #
        # then, do the mode string from the perspective of this server.
        #
        $mode_str = $server->convert_cmode_string($me, $mode_str, 1);
        $target->do_mode_string_local($me, $source, $mode_str, 1, 1);

        # === Forward ===
        #
        #   mode changes will be propagated only if the TS was good.
        #
        #   JELP:   CMODE
        #   TS6:    TMODE
        #
        # $source, $channel, $time, $perspective, $mode_str
        # the perspective is $me because it was converted.
        #
        $msg->forward(cmode => $source, $target, $target->{time}, $me, $mode_str);

        return 1;
    }

    # if it's a user, make sure the source matches.
    # remember that $source may not even be a user.
    $target = user_from_ts6($target_str) or return;
    if ($source != $target) {
        notice(server_protocol_warning =>
            $server->name, $server->id,
            'sent MODE message with nonmatching source (' .
            $source->name.') and target ('.$target->name.')');
        return;
    }

    # handle the changes.
    $target->do_mode_string_local($mode_str, 1);

    # === Forward ===
    $msg->forward(umode => $target, $mode_str);

    return 1;
}

$mod
