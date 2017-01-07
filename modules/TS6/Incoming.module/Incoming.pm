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
    ts6_id          level_from_prefix_ts6
);

use utils qw(channel_str_to_list notice);

our ($api, $mod, $pool, $me);

our %ts6_incoming_commands = (
    SID => {
                  # :sid SID       name hops sid :desc
        params => '-source(server) *    *    *   :',
        code   => \&sid
    },
    EUID => {
                   # :sid EUID      nick hopcount nick_ts umodes ident cloak ip  uid host act :realname
        params  => '-source(server) *    *        ts      *      *     *     *   *   *    *   :',
        code    => \&euid
    },
    UID => {
                  # :sid UID       nick hopcount nick_ts umodes ident cloak ip uid :realname
        params => '-source(server) *    *        ts      *      *     *     *  *   :',
        code   => \&uid
    },
    SJOIN => {
                  # :sid SJOIN     ch_time ch_name mode_str mode_params... :nicklist
        params => '-source(server) ts      *       *        ...',
        code   => \&sjoin
    },
    PRIVMSG => {
                   # :src   PRIVMSG  target :message
        params  => '-source -command *      :',
        code    => \&privmsgnotice
    },
    NOTICE => {
                   # :src   NOTICE   target :message
        params  => '-source -command *      :',
        code    => \&privmsgnotice
    },
    TMODE => {     # :src TMODE ch_time ch_name      mode_str mode_params...
        params  => '-source     ts      channel      :', # just to join them together
        code    => \&tmode
    },
    JOIN => {
                  # :src JOIN     ch_time  ch_name
        params => '-source(user)  ts       *(opt)',
        code   => \&_join
    },
    ENCAP => {    # :src   ENCAP serv_mask  sub_cmd  sub_params...
        params => '-source       *          *        ...',
        code   => \&encap
    },
    KILL => {
                   # :src   KILL    uid     :path
        params  => '-source         user    :',
        code    => \&_kill
    },
    PART => {
                   # :uid PART    ch_name_multi  :reason
        params  => '-source(user) *              :(opt)',
        code    => \&part
    },
    QUIT => {
                   # :src QUIT   :reason
        params  => '-source      :',
        code    => \&quit
    },
    KICK => {
                   # :source KICK channel  target_user :reason
        params  => '-source       channel  user        :(opt)',
        code    => \&kick
    },
    NICK => {
                   # :uid NICK    newnick new_nick_ts
        params  => '-source(user) *       ts',
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
        params  => '-source(user) :(opt)',
        code    => \&away
    },
    ETB => {
                  # :sid|uid ETB channelTS channel topicTS setby extensions topic
        params => '-source       ts        channel ts      *     ...',
        code   => \&etb
    },
    TB => {
                   # :sid TB        channel topic_ts setby    :topic
        params  => '-source(server) channel ts       *(opt)   :',
        code    => \&tb
    },
    TOPIC => {
                  # :uid   TOPIC channel :topic
        params => '-source(user) channel :',
        code   => \&topic
    },
    WALLOPS => {
                  # :source WALLOPS :message
        params => '-source          :',
        code   => \&wallops
    },
    OPERWALL => {
                  # :uid OPERWALL  :message
        params => '-source(user)   :',
        code   => \&operwall
    },
    CHGHOST => {
                  # :source CHGHOST uid   newhost
        params => '-source          user  *',
        code   => \&chghost
    },
    ENCAP_CHGHOST => {
                  # :uid ENCAP   serv_mask  CHGHOST  new_host
        params => '-source(user) *          skip     *',
        code   => \&ENCAP_CHGHOST
    },
    SQUIT => {
                  # :sid SQUIT     sid    :reason
        params => '-source(opt)    server :',
        code   => \&squit
    },
    WHOIS => {
                  # :uid WHOIS   sid|uid    :query(e.g. nickname)
        params => '-source(user) hunted     :',
        code   => \&whois
    },
    MODE => {
                  # :source MODE uid|channel +modes params
        params => '-source ...',
        code   => \&mode
    },
    ADMIN => {
                  # :uid         ADMIN    sid
        params => '-source(user) -command hunted',
        code   => \&generic_hunted
    },
    INFO => {
                  # :uid         INFO     sid
        params => '-source(user) -command hunted',
        code   => \&generic_hunted
    },
    MOTD => {
                  # :uid         MOTD     sid
        params => '-source(user) -command hunted',
        code   => \&generic_hunted
    },
    TIME => {
                  # :uid         TIME     sid
        params => '-source(user) -command hunted',
        code   => \&generic_hunted
    },
    VERSION => {
                  # :sid|uid   VERSION  sid
        params => '-source     -command hunted',
        code   => \&generic_hunted
    },
    USERS => {
                  # :sid|uid      USERS    sid
        params => '-source(user)  -command hunted',
        code   => \&generic_hunted
    },
    LUSERS => {
                # :uid LUSERS        server_mask(unused) sid
        params => '-source(user)     skip                hunted',
        code   => \&lusers
    },
    INFO => {
                  # :uid INFO    sid
        params => '-source(user) hunted',
        code   => \&info
    },
    LINKS => {
                # :uid LINKS     sid        server_mask
        params => '-source(user) hunted     *',
        code   => \&links
    },
    INVITE => {
                  # :uid INVITE  uid  channel channelTS
        params => '-source(user) user channel ts(opt)',
        code   => \&invite
    },
    ENCAP_LOGIN => {
                  # :uid ENCAP   serv_mask  LOGIN    account_name
        params => '-source(user) *          skip     *',
        code   => \&login
    },
    ENCAP_SU => {
                  # :sid ENCAP     serv_mask  SU    uid    account_name
        params => '-source(server) *          skip  user   *(opt)',
        code   => \&su
    },
    ENCAP_REHASH => {
                  # :sid ENCAP     serv_mask REHASH type
        params => '-source(server) *         skip   *(opt)',
        code   => \&rehash
    },
    SAVE => {
                  # :sid SAVE      uid   nickTS
        params => '-source(server) user  ts',
        code   => \&save
    },
    ENCAP_RSFNC => {
                  # :sid ENCAP     serv_mask RSFNC  uid  new_nick new_nick_ts old_nick_ts
        params => '-source(server) *         skip   user *        ts          ts',
        code   => \&rsfnc
    },
    CONNECT => {
                  # :sid|uid CONNECT connect_mask target_sid
        params => '-source           *            hunted',
        code   => \&_connect
    },
    ENCAP_GCAP => {
                  # :sid ENCAP     serv_mask GCAP  caps
        params => '-source(server) *         skip  :',
        code   => \&gcap
    },
    ENCAP_REALHOST => {
                  # :uid ENCAP   serv_mask REALHOST host
        params => '-source(user) *         skip     *',
        code   => \&realhost
    },
    ENCAP_SNOTE => {
                  # :sid ENCAP     serv_mask SNOTE    letter :message
        params => '-source(server) *         skip     *      *',
        code   => \&realhost
    }
);

sub handle_numeric {
    my ($server, $msg) = @_;
    my $num  = $msg->command;

    # from ts6-protocol.txt:
    # If the first digit is 0 (indicating a reply about the local connection), it
    # should be changed to 1 before propagation or sending to a user.
    my $first = \substr($num, 0, 1);
    if ($$first eq '0') {
        $$first = '1';
    }

    # find the source.
    my $source_serv = obj_from_ts6($msg->{source});
    if (!$source_serv || !$source_serv->isa('server')) {
        return;
    }

    # find the user.
    my $user = obj_from_ts6($msg->params(0));
    if (!$user || !$user->isa('user')) {
        return;
    }

    # create the message
    # force list context
    my (undef, $message) = $msg->parse_params('skip :');

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

    if (my $err = server::protocol::check_new_server(
    $s{sid}, $s{name}, $server->{name})) {
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
    $serv->{ircd_name} = $source_serv->{ircd_name} || $server->{ircd_name};

    # add mode definitions.
    server::protocol::ircd_register_modes($serv);

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

    $u{time} = $u{nick_time};                       # for compatibility
    $u{host} = $u{cloak} if $u{host} eq '*';        # host equal to visible
    $u{uid}  = uid_from_ts6($u{ts6_uid});           # convert to juno UID
    $u{nick} = $u{uid} if $u{nick} eq $u{ts6_uid};  # use juno uid as nick

    # create a temporary user object.
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
    my $used = $pool->nick_in_use($u{nick});

    # unregistered user. kill it.
    if ($used && $used->isa('connection')) {
        $used->done('Overridden');
        undef $used;
    }

    # it's a registered user.
    if ($used) {
        server::protocol::handle_nick_collision(
            $server,
            $used, $new_usr_temp,
            $server->has_cap('save')
        ) and return 1;
    }

    # create a new user with the given modes.
    my $user = $pool->new_user(%$new_usr_temp);
    $user->handle_mode_string($mode_str, 1);
    $user->fire('initially_set_modes');

    # log the user in
    my $act_name = delete $user->{account_name};
    if (length $act_name && $act_name ne '*') {
        L("TS6 login $$user{nick} as $act_name");
        $user->do_login($act_name);
    }

    # === Forward ===
    #
    #   JELP:   UID
    #   TS6:    EUID
    #
    $msg->forward(new_user => $user);

    return 1;
}

# UID
#
# source:       server
# propagation:  broadcast
# parameters:   nickname, hopcount, nickTS, umodes, username, visible hostname,
#               IP address, UID, gecos
# propagation:  broadcast
#
sub uid {
    my ($server, $msg, $source_serv, @rest) = @_;
    # (0)nick (1)hopcount (2)nick_ts (3)umodes (4)ident (5)cloak (6)ip (7)uid (8)realname
    #    nick ts6_dummy   nick_time  umodes    ident    cloak    ip    ts6_uid
    return euid(@_[0..2], @rest[0..7], '*', '*', $rest[8]);
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
    my ($server, $msg, $source_serv, $ts, $ch_name, $mode_str_modes, @mode_params) = @_;

    # UPDATE CHANNEL TIME
    #=================================

    # maybe we have a channel by this name, otherwise create one.
    my ($channel, $new) = $pool->lookup_or_create_channel($ch_name, $ts);

    # take the new time if it's less recent.
    # note that modes are not handled here (the second arg says not to)
    # because they are handled manually in a prettier way for SJOIN.
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

    my ($uid_letters, @uids, @good_users) = '+';
    foreach my $str (split /\s+/, $nicklist) {
        my ($prefixes, $uid) = ($str =~ m/^(\W*)([0-9A-Z]+)$/) or next;
        my $user     = user_from_ts6($uid) or next;
        my @prefixes = split //, $prefixes;

        # this user does not physically belong to this server; ignore.
        next if $user->{location} != $server;

        # join the new user.
        push @good_users, $user;
        $channel->do_join($user);

        # no prefixes or not accepting the prefixes.
        next unless length $prefixes && $accept_new_modes;

        # map to TS6.
        my $id = ts6_id($user);
        my $modes = join '', map mode_from_prefix_ts6($server, $_), @prefixes;

        # add the letters in the perspective of $source_serv.
        $uid_letters .= $modes;
        push @uids, $id for 1 .. length $modes;
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
#   propagation:    one-to-one
#
# - a channel name
#   propagation:    all servers with -D users on the channel
#   (cmode +m/+n should be checked everywhere, bans should not be checked
#   remotely)
#
# - Complex PRIVMSG
#   a status character ('@'/'+') followed by a channel name, to send to users
#   with that status or higher only.
#   capab:          CHW
#   propagation:    all servers with -D users with appropriate status
#
# - Complex PRIVMSG
#   '=' followed by a channel name, to send to chanops only, for cmode +z.
#   capab:          CHW and EOPMOD
#   propagation:    all servers with -D chanops
#
# - Complex PRIVMSG
#   a user@server message, to send to users on a specific server. The exact
#   meaning of the part before the '@' is not prescribed, except that "opers"
#   allows IRC operators to send to all IRC operators on the server in an
#   unspecified format.
#   propagation:    one-to-one
#
# - Complex PRIVMSG
#   a message to all users on server names matching a mask ('$$' followed by mask)
#   propagation:    broadcast
#   Only allowed to IRC operators.
#
# - Complex PRIVMSG
#   a message to all users with hostnames matching a mask ('$#' followed by mask).
#   Note that this is often implemented poorly.
#   propagation:    broadcast
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
    return server::protocol::handle_privmsgnotice(
        @_[0..5],
        channel_lookup  => sub { $pool->lookup_channel(shift)     },
        atserv_lookup   => sub { $pool->lookup_server_name(shift) },
        user_lookup     => \&user_from_ts6,
        supports_atserv => 1,
        opers_prefix    => 'opers',
        opmod_prefix    => '=',
        smask_prefix    => '$$',
        chan_prefixes   => [ keys %{ $server->{ircd_prefixes} || {} } ],
        chan_lvl_lookup => sub { level_from_prefix_ts6($server, shift) }
    );
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

    # take lower time if necessary.
    $channel->take_lower_time($ts) unless $new;

    # do the join.
    $channel->do_join($user);

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
    my ($server, $msg, $source, $serv_mask, $encap_cmd, @rest) = @_;

    # ENCAP
    #
    # This master handler fires virtual commands which manually ->forward().
    # If no handler exists, this one will forward the message to TS6 servers
    # exactly as it was received. Unfortunately it is impossible to send
    # unknown ENCAP commands to indirectly-connected TS6 servers with servers
    # linked via other protocols in between them.
    #
    # SEE ISSUE #29 for details.
    #

    # create a fake ENCAP_* command.
    my $cmd = uc 'ENCAP_'.$encap_cmd;
    $msg->{command} = $cmd;

    # fire the virtual command.
    my $fire = $server->prepare_together(
        [ "ts6_message"      => $msg ],
        [ "ts6_message_$cmd" => $msg ]
    )->fire('safe');

    # an exception occurred in the virtual command handler.
    if (my $e = $fire->exception) {
        my $stopper = $fire->stopper;
        notice(exception => "Error in $cmd from $stopper: $e");
        return;
    }

    # if a TS6 command handler manually forwarded this, we're done.
    return 1 if $msg->{encap_forwarded};

    # otherwise, forward as-is to TS6 servers.
    L(
        "ENCAP $encap_cmd is not explicitly forwarded by this server; ".
        'propagating as-is'
    );
    $msg->{command} = 'ENCAP';
    my %done = ($me => 1);

    # find servers matching the mask.
    foreach my $serv ($pool->lookup_server_mask($serv_mask)) {
        my $location = $serv->{location} || $serv;  # for $me, location = nil

        next if $done{$location};                   # already did this location
        $done{$location} = 1;                       # remember sent/checked

        next if $location == $server;               # this is the origin
        next if ($location->{link_type} // '') ne 'ts6';    # not a TS6 server

        # OK, send it as-is.
        $location->send($msg->data);

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
    my ($server, $msg, $user, $serv_mask, $act_name) = @_;
    $msg->{encap_forwarded}++;

    # login.
    L("TS6 login $$user{nick} as $act_name");
    $user->do_login($act_name);

    #=== Forward ===#
    $msg->forward_to_mask($serv_mask, login => $user, $act_name);

    return 1;
}

# SU
#
# encap only
# encap target: *
# source:       services server
# parameters:   target user, new login name (optional)
#
sub su {
    my ($server, $msg, $source_serv, $serv_mask, $user, $act_name) = @_;
    $msg->{encap_forwarded}++;

    # no account name = logout.
    if (!length $act_name) {
        L("TS6 logout $$user{nick}");
        $user->do_logout();

        #=== Forward ===#
        $msg->forward_to_mask($serv_mask, su_logout => $source_serv, $user);

        return 1;
    }

    # login.
    L("TS6 login $$user{nick} as $act_name");
    $user->do_login($act_name);

    #=== Forward ===#
    $msg->forward_to_mask($serv_mask, su_login =>
        $source_serv, $user, $act_name
    );

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
sub _kill {
    # source            user  :
    # :source     KILL  uid   :path
    # path is the source and the reason; e.g. server!host!iuser!nick (go away)
    my ($server, $msg, $source, $tuser, $path) = @_;

    # this ignores non-local users.
    my $reason = (split / /, $path, 2)[1];
    $reason = substr $reason, 1, -1;

    $tuser->get_killed_by($source, $reason);

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
        $channel->do_part($user, $reason);

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
    # source   :
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
    my ($server, $msg, $user, $newnick, $newts) = @_;

    # use juno uid as nick
    $newnick = $user->{uid} if $newnick eq ts6_id($user);

    # tell ppl
    $user->send_to_channels("NICK $newnick");
    $user->change_nick($newnick, $newts);

    # === Forward ===
    $msg->forward(nick_change => $user);

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

    # the destination is another non-TS6 server connected through me.
    # JELP PING/PONG only work on a direct connection. see issue #62.
    # here we emulate a reply from the target server.
    my $loc = $dest_serv->{location};
    if ($loc && $loc->conn && $loc->{link_type} ne 'ts6') {
        $server->fire_command(pong => $dest_serv, $server);
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
        $source_serv->end_burst();

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
    # -source(user) channel :
    # :uid TOPIC    channel :topic
    my ($server, $msg, $user, $channel, $topic) = @_;

    # ($source, $topic, $setby, $time, $check_text)
    $channel->do_topic($user, $topic, $user->full, time);

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
    # -source(server)   channel ts       *(opt) :
    # :sid TB           channel topic_ts setby  :topic
    my ($server, $msg, $s_serv, $channel, $topic_ts, $setby, $topic) = @_;

    # no topic. this means the setby parameter was omitted.
    if (!defined $topic) {
        $topic = $setby;
        $setby = $s_serv->name;
    }

    # TB does not support unsetting topics. the new topic has to have length.
    return if !length $topic;

    if ($channel->{topic}) {

        # TB does not support switching to older topics or changing solely the
        # topicTS. if we have a topic already and it is older, ignore this message.
        return if $channel->{topic}{time} < $topic_ts;

        # if the topic existed already and is unchanged, ignore this message.
        # we only care about the first length($topic) chars. see issue #132.
        return if substr($channel->{topic}{topic}, 0, length $topic) eq $topic;

    }

    # set the topic
    my $old = $channel->{topic};    # don't propagate if unchanged
    $channel->do_topic($s_serv, $topic, $setby, $topic_ts) or return;

    # === Forward ===
    $msg->forward(topicburst =>
        $channel,
        source      => $s_serv,
        old         => $old
    );

    return 1;
}

# ETB
# capab:        EOPMOD
# source:       any
# propagation:  broadcast
# parameters:   channelTS, channel, topicTS, topic setter, opt. extensions, topic
#
sub etb {
    my ($server, $msg, $source, $ch_time, $channel, $topic_ts, $setby) = @_;
    my $topic = pop;

    # Accept if...
    my $accept =
        !$channel->{topic}              ||  # the channel has no topic
         $channel->{time} > $ch_time    ||  # the provided channelTS is older
        ($channel->{time} == $ch_time && $channel->{topic}{time} < $topic_ts);
        # the channelTS are equal and the provided topicTS is newer
    return unless $accept;

    # (issue #132) we don't have to check if the topic is a shorter version of
    # the existing one here because ETB only accepts topics with a newer
    # topicTS. if it is newer, it will always win.

    # set the topic.
    my $old = $channel->{topic};
    $channel->do_topic($source, $topic, $setby, $topic_ts, 1);

    # === Forward ===
    #
    # Note that the including the provided $channel_ts is crucial here.
    # Services uses channelTS '0' to force a topic change. The channelTS
    # must be propagated as it was received.
    #
    $msg->forward(topicburst =>
        $channel,
        source      => $source,
        old         => $old,
        channel_ts  => $ch_time
    );

    return;
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
# -source         :
#
sub wallops {
    my ($server, $msg, $source, $message) = @_;

    # is it a server or a user? this determines whether it is oper-only.
    my $oper_only = $source->isa('server');

    $pool->fire_wallops_local($source, $message, $oper_only);

    #=== Forward ===#
    $msg->forward(wallops => $source, $message, $oper_only);

    return 1;
}

# OPERWALL
#
# source: user
# parameters: message
# propagation: broadcast
#
sub operwall {
    my ($server, $msg, $user, $message) = @_;

    $pool->fire_wallops_local($user, $message, 1);

    #=== Forward ===#
    $msg->forward(wallops => $user, $message, 1);

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
    $user->get_mask_changed($user->{ident}, $new_host, $source->name);

    #=== Forward ===#
    $msg->forward(chghost => $source, $user, $new_host);

    return 1;
}

sub encap_chghost {
    my ($server, $msg, $user, $serv_mask, $new_host) = @_;
    $msg->{encap_forwarded}++;
    return chghost(@_[0..2], $new_host);
}

# SQUIT
#
# parameters:   target server, comment
#
sub squit {
    my ($server, $msg, $source, $t_serv, $comment) = @_;

    # the provided $source will either be a user or server object
    # or undef if there was no source.
    my $real_source = $source;
    $source ||= $server;

    # if the target server is the receiving server or the local link this came
    # from, this is an announcement that the link is being closed.
    if ($t_serv == $server || $t_serv == $me) {
        $t_serv = $server;
        $t_serv->conn->done($comment);
        notice(server_closing => $server->notice_info, $comment);
    }

    # the target server is an uplink of this server.
    # that means that this was a remote SQUIT.
    elsif ($t_serv->conn) {
        notice(squit => $source->notice_info, $t_serv->{name}, $me->name);
        $t_serv->conn->done($comment);
    }

    # otherwise, we can simply quit the target server.
    else {
        $t_serv->quit($comment);

        #=== Forward ===#
        $msg->forward(quit => $t_serv, $comment, $real_source);

    }

    return 1;
}

# WHOIS
# source: user
# parameters: hunted, target nick
#
sub whois {
    my ($server, $msg, $s_user, $target, $query) = @_;
    # $s_user is the user doing the query
    # $target is a server object from hunted
    # $query is the raw query itself, such as a nickname

    # forward this onto physical location.
    my $loc = $target->{location} || $target;

    # it's me!
    if ($loc == $me) {
        return $s_user->handle_unsafe("WHOIS $query");
    }

    # if we're forwarding, actually look up the user.
    my $t_user = $pool->lookup_user_nick($query);
    if (!$t_user) {
        notice(server_protocol_warning =>
            $server->notice_info,
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
            $server->notice_info,
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

# ADMIN, INFO, MOTD, TIME, VERSION
#
# source:       user
# parameters:   hunted
#
sub generic_hunted {
    my ($server, $msg, $source, $command, $t_server) = @_;

    # VERSION supports a server source, but I don't know what to do about that.
    $source->isa('user') or return;

    # if the target server is not me, forward it.
    if ($t_server != $me) {
        # this line is for when I search the codebase to change something:
        # admin => info => motd => time => version => users =>
        $msg->forward_to($t_server, lc $command => $source, $t_server);
        return 1;
    }

    # otherwise, handle it locally.
    return $source->handle_unsafe($command);

}

# LUSERS
#
# source:       user
# parameters:   server mask, hunted
#
sub lusers {
    my ($server, $msg, $user, $t_server) = @_;

    # if the target server is not me, forward it.
    if ($t_server != $me) {
        $msg->forward_to($t_server, lusers => $user, $t_server);
        return 1;
    }

    # otherwise, handle it locally.
    return $user->handle_unsafe("LUSERS");

}

# INFO
#
# source:       user
# parameters:   hunted
#
sub info {
    my ($server, $msg, $user, $t_server) = @_;

    # if the target server is not me, forward it.
    if ($t_server != $me) {
        $msg->forward_to($t_server, info => $user, $t_server);
        return 1;
    }

    # otherwise, handle it locally.
    return $user->handle_unsafe("INFO");
}

# LINKS
#
# source:       user
# parameters:   hunted, server mask
#
sub links {
    my ($server, $msg, $user, $t_server, $server_mask) = @_;

    # if the target server is not me, forward it.
    if ($t_server != $me) {
        $msg->forward_to($t_server, links => $user, $t_server, $server_mask);
        return 1;
    }

    # otherwise, handle it locally.
    return $user->handle_unsafe("LINKS * $server_mask");

}

# INVITE
#
# source:       user
# parameters:   target user, channel, opt. channelTS
# propagation:  one-to-one
#
sub invite {
    my ($server, $msg, $user, $t_user, $channel, $time) = @_;

    # if the timestamp is newer than what we have, drop the message.
    return if defined $time && $channel->{time} < $time;

    # this user belongs to me.
    if ($t_user->is_local) {
        $t_user->loc_get_invited_by($user, $channel);
        return 1;
    }

    #=== Forward ===#
    # forward on to next hop.
    $msg->forward_to($t_user, invite => $user, $t_user, $channel);

    return 1;
}

# REHASH
#
# charybdis TS6
# encap only
# source:       user
# parameters:   opt. rehash type
#
sub rehash {
    my ($server, $msg, $user, $serv_mask, $type) = @_;
    $msg->{encap_forwarded}++;

    # rehash if the mask matches me.
    my @servers = $pool->lookup_server_mask($serv_mask) or return;
    if ($servers[0] == $me) {
        ircd::rehash($user);
    }

    #=== Forward ===#
    $msg->forward_to_mask($serv_mask,
        ircd_rehash => $user, $serv_mask, $type, @servers
    );

    return 1;
}

# SAVE
#
# capab:        SAVE
# source:       server
# propagation:  broadcast
# parameters:   target uid, TS
#
sub save {
    my ($server, $msg, $source_serv, $t_user, $time) = @_;

    # only accept the message if the nickTS is correct.
    return if $t_user->{nick_time} != $time;

    $t_user->save_locally;

    #=== Forward ===#
    $msg->forward(save_user => $source_serv, $t_user, $time);

    return 1;
}

# RSFNC
#
# encap only
# capab:        RSFNC
# encap target: single server
# source:       services server
# parameters:   target user, new nickname, new nickTS, old nickTS
#
sub rsfnc {
    my ($server, $msg, $source_serv, $serv_mask,
    $user, $new_nick, $new_nick_ts, $old_nick_ts) = @_;

    # forward if appropriate.
    $msg->{encap_forwarded}++;
    $msg->forward_to_mask($serv_mask,
        force_nick => $server, $user, $new_nick, $new_nick_ts, $old_nick_ts
    ) and return;

    # the target user has to be local.
    return if !$user->is_local;

    return server::linkage::handle_svsnick(
        $msg, $source_serv, $user, $new_nick,
        $new_nick_ts, $old_nick_ts
    );
}

# CONNECT
#
# source:       any
# parameters:   server to connect to, port, hunted
#
sub _connect {
    my ($server, $msg, $source, $connect_mask, $t_server) = @_;

    # if the target server is not me, forward it.
    if ($t_server != $me) {
        $msg->forward_to($t_server,
            connect => $source, $connect_mask, $t_server
        );
        return 1;
    }

    # otherwise, handle it locally.

    # this has to be a user in order to use ->handle_unsafe().
    if (!$source->isa('user')) {
        notice(server_protocol_warning =>
            $server->notice_info,
            'sent CONNECT with source '.$source->notice_info.
            ', but only users can issue CONNECT'
        );
        return;
    }

    return $source->handle_unsafe("CONNECT $connect_mask");

}

# GCAP
#
# encap only
# encap target: *
# source:       server
# parameters:   space separated capability list
#
sub gcap {
    my ($server, $msg, $source_serv, $serv_mask, $caps) = @_;
    # don't set $msg->{encap_forwarded} because this is TS6-specific
    $source_serv->add_cap(split /\s+/, $caps);
}

# REALHOST
#
# charybdis TS6
# encap only
# encap target: *
# source:       user
# parameters:   real hostname
#
sub realhost {
    my ($server, $msg, $user, $serv_mask, $host) = @_;
    $msg->{encap_forwarded}++;
    $user->{host} = $host;
    $msg->forward(realhost => $user, $host);
}

# SNOTE
#
# charybdis TS6
# encap only
# source:       server
# parameters:   snomask letter, text
#
my %snomask_names = (
    b => 'bot_warning',
    c => 'client_notice',
    C => 'client_notice',
    d => 'debug',
    f => 'connection_denied',
    F => 'remote_client_notice',
    k => 'kill_notice',
    n => 'user_nick_change',
    r => 'connection_denied',
    u => 'connection_denied',
    W => 'whois',
    x => 'new_server',
    y => 'spy',
    l => 'new_channel',
    Z => 'operspy'
);
sub snote {
    my ($server, $msg, $source_serv, $serv_mask, $letter, $message) = @_;
    my $notice = $snomask_names{$letter} || 'general';
    $msg->{encap_forwarded}++;

    # send to users with this notice flag.
    foreach my $user ($pool->real_users) {
        next unless blessed $user; # during destruction.
        next unless $user->is_mode('ircop');
        next unless $user->has_notice($notice);
        $user->server_notice($source_serv, Notice => $message);
    }

    # === Forward ===
    $msg->forward(snotice => $server, $notice, $message, undef, $letter);
}

$mod
