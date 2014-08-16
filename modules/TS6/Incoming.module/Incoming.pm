# Copyright (c) 2014, mitchellcooper
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

use M::TS6::Utils qw(uid_from_ts6 user_from_ts6 mode_from_prefix_ts6 sid_from_ts6);

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
    }
);

# SID
#
# source:       server
# propagation:  broadcast
# parameters:   server name, hopcount, sid, server description
sub sid {
    my ($server, $msg, $source_serv, $s_name, $hops, $sid, $desc) = @_;
    my %s = (
        parent   => $source_serv,       # the server which is the actual parent
        source   => $server->{sid},     # SID of the server who told us about him
        location => $server,            # nearest server we have a physical link to
        ircd     => -1,                 # not applicable in TS6
        proto    => -1,                 # not applicable in TS6
        time     => time                # first time server became known (best bet)
    );
    @s{ qw(name desc ts6_sid sid) } = ($s_name, $desc, $sid, sid_from_ts6($sid));

    # do not allow SID or server name collisions.
    if ($pool->lookup_server($s{sid}) || $pool->lookup_server_name($s{name})) {
        L("duplicate SID $s{sid} or server name $s{name}; dropping $$server{name}");
        $server->conn->done('attempted to introduce existing server');
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

    # uid collision?
    if ($pool->lookup_user($u{uid})) {
        # can't tolerate this.
        # the server is bugged/mentally unstable.
        L("duplicate UID $u{uid}; dropping $$server{name}");
        $server->conn->done('UID collision') if $server->conn;
    }

    # nick collision!
    my $used = $pool->lookup_user_nick($u{nick});
    if ($used) {
        # TODO: this.
        return; # don't actually return
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
    my ($server, $msg, $serv, $ts, $ch_name, $mode_str, @mode_params) = @_;

    # maybe we have a channel by this name, otherwise create one.
    my $channel = $pool->lookup_channel($ch_name) || $pool->new_channel(
        name => $ch_name,
        time => $ts
    );

    # store mode string before any possible changes.
    my @after_params;       # params after changes.
    my $after_modestr = ''; # mode string after changes.
    my $old_modestr   = $channel->mode_string_hidden($serv, 1); # all but status and lists
    my $old_s_modestr = $channel->mode_string_status($serv);    # status only
    
    # take the new time if it's less recent.
    my $old_time = $channel->{time};
    my $new_time = $channel->take_lower_time($ts, 1);
    my $accept_new_modes;
    
    # their TS is either older or the same.
    #
    # 1. wipe out our old modes. (already done by ->take_lower_time())
    # 2. accept all new modes.
    # 3. propagate all simple modes (not just the difference).
    #
    $accept_new_modes++ if $new_time <= $old_time;


    # handle the nick list.
    #
    # add users to channel.
    # determine prefix mode string.
    #
    my ($uids_modes, @uids, @good_users) = '';
    foreach my $str (split /\s+/, $nicklist) {
        my ($prefixes, $uid) = ($str =~ m/^(\W*)([0-9A-Z]+)$/) or next;
        my $user     = user_from_ts6($uid) or next;
        my @prefixes = split //, $prefixes;

        # this user does not physically belong to this server.
        next if $user->{location} != $server;
        push @good_users, $user;
        
        # join the new users.
        unless ($channel->has_user($user)) {
            $channel->cjoin($user, $channel->{time});
            $channel->sendfrom_all($user->full, "JOIN $$channel{name}");
            $channel->fire_event(user_joined => $user);
        }

        # no prefixes or not accepting the prefixes.
        next unless length $prefixes && $accept_new_modes;

        # determine the modes and add them to the mode string / parameters.
        my $modes    = join '', map { mode_from_prefix_ts6($server, $_) } @prefixes;
        $uids_modes .= $modes;
        push @uids, $user->{uid} for 1 .. length $modes;
        
    }
    
    # combine this with the other modes in the message.
    my $command_modestr = join(' ', '+'.$mode_str.$uids_modes, @mode_params, @uids);
    
    # okay, now we're ready to apply the modes.
    if ($accept_new_modes) {
    
        # determine the difference between
        my $difference = $serv->cmode_string_difference(
            $old_modestr,       # $old_modestr     (all former simple modes)
            $command_modestr,   # $command_modestr (all new modes including status)
            1,                  # $combine_lists   (all list modes will be accepted)
            1                   # $remove_none     (no modes will be unset)
        );
        
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
        # note: do not supply a $over_protocol sub. this generated string uses juno UIDs.
        $channel->do_mode_string_local($serv, $serv, $difference, 1, 1) if $difference;
        
    }
    
    # === Forward DURING BURST ===
    #
    #   during burst, all channel modes will be propagated,
    #   regardless of whether they were present or absent
    #   in this particular SJOIN message.
    #
    #   all users will be sent with their current statuses,
    #   if any apply, also without regard to this message.
    #
    #   JELP:   CUM
    #   TS6:    SJOIN
    #   
    if ($server->{is_burst}) {
        $msg->forward(channel_burst => $channel, $serv, @good_users);
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
        $serv,          # $serv      = server source of the message
        $mode_str,      # $mode_str  = mode string being sent
        $serv,          # $mode_serv = server object for mode perspective
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
        $msg->forward_to($tuser->{location}, privmsgnotice =>
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
    # then, do the mode string from the perspective of this server.
    #
    $mode_str = $server->convert_cmode_string($me, $mode_str, 1);
    $channel->do_mode_string_local($me, $source, $mode_str, 1, 1);
    
    # === Forward ===
    #
    #   mode changes will be propagated only if the TS was good.
    #
    #   JELP:   JOIN, CMODE
    #   TS6:    SJOIN
    #
    # $source, $channel, $time, $perspective, $mode_str
    # the perspective is $me because it was converted.
    #
    $msg->forward(cmode => $source, $channel, $channel->{time}, $me, $mode_str);
    
}

$mod
