# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-MacBook-Pro.local
# Sat May 30 12:26:25 EST 2015
# TS6.pm
#
# @name:            'Ban::TS6'
# @package:         'M::Ban::TS6'
# @description:     'TS6 ban propagation'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
# depends on TS6::Base, but don't put that here.
# companion submodule loading takes care of it.
#
package M::Ban::TS6;

use warnings;
use strict;
use 5.010;

use utils qw(fnv v notice conf);
use M::TS6::Utils qw(ts6_id);

our ($api, $mod, $pool, $conf, $me);

# these ban types supported by this implementation
my %ts6_supports = map { $_ => 1 }
    qw(resv kline dline);

# these ban types can be sent in the ENCAP form
my %ts6_encap_ok = %ts6_supports;

# these ban types can be sent with the BAN command
my %ts6_ban_ok = (
    kline => 'K',
  # xline => 'X',
    resv  => 'R'
);

# this is the maximum duration permitted for global bans in charybdis.
# it is only currently used by the outgoing BAN command.
# charybdis@8fed90ba8a221642ae1f0fd450e8e580a79061fb/ircd/s_newconf.cc#L747
my $max_duration = 524160;

our %ts6_capabilities = (
    KLN   => { required => 0 },
    UNKLN => { required => 0 },
    BAN   => { required => 0 }
);

our %ts6_outgoing_commands = (
    ban     => \&out_ban,
    baninfo => \&out_baninfo,
    bandel  => \&out_bandel
);

our %ts6_incoming_commands = (
    ENCAP_DLINE => {
                  # :uid ENCAP    target DLINE duration ip_mask :reason
        params => '-source(user)  *      skip  *        *       :',
        code   => \&encap_dline
    },
    ENCAP_UNDLINE => {
                  # :uid ENCAP    target UNDLINE ip_mask
        params => '-source(user)  *      skip    *',
        code   => \&encap_undline
    },
    ENCAP_KLINE => {
                  # :<source> ENCAP <target> KLINE <time>   <user>     <host>    :<reason>
        params => '-source(user)    *        skip  *        *          *         :',
        code   => \&encap_kline
    },
    ENCAP_UNKLINE => {
                  # :<source> ENCAP <target> UNKLINE <user>     <host>
        params => '-source(user)    *        skip    *          *',
        code   => \&encap_unkline
    },
    KLINE => {
                  # :<source> KLINE <target> <time> <user> <host> :<reason>
        params => '-source(user)    *        *      *      *      :',
        code   => \&kline
    },
    UNKLINE => {
                  # :<source> KLINE <target> <user> <host>
        params => '-source(user)    *        *      *',
        code   => \&unkline
    },
    BAN => {
                  # :source BAN type user host creationTS duration lifetime oper reason
        params => '-source      *    *    *    ts         *        *        *    :',
        code   => \&ban
    },
    ENCAP_RESV => {
                  # :uid ENCAP   target RESV duration nick_chan_mask 0      :reason
        params => '-source(user) *      skip *        *              *(opt) *',
        code   => \&encap_resv
    },
    ENCAP_UNRESV => {
                  # :uid ENCAP   target UNRESV nick_chan_mask
        params => '-source(user) *      skip   *',
        code   => \&encap_unresv
    },
    RESV => {     # :uid RESV    target duration nick_chan_mask :reason
        params => '-source(user) *      *        *              :',
        code   => \&resv
    },
    UNRESV => {   # :uid UNRESV   target nick_chan_mask
        params => '-source(user)  *      *',
        code   => \&unresv
    },
    ENCAP_NICKDELAY => {
                  # :sid ENCAP     target NICKDELAY duration nick
        params => '-source(server) *      skip      *        *',
        code   => \&encap_nickdelay
    }
);

# TODO: (#145) handle the pipe in ban reasons to extract oper reason
# TODO: (#144) handle CIDR

sub init {

    # IRCd event for burst.
    $pool->on('server.send_ts6_burst' => \&burst_bans,
        name    => 'ts6.banburst',
        after   => 'ts6.mainburst',
        with_eo => 1
    );

    return 1;
}

sub void {
    undef *M::Ban::Info::ts6_duration;
    undef *M::Ban::Info::ts6_match;
}

# we can't propagate an expiration time over old TS commands, so we have to
# calculate how long the duration should be from the current time
sub M::Ban::Info::ts6_duration {
    my $ban = shift;
    return 0 if !$ban->expires;
    return $ban->expires - time;
}

# ts6_match is special for using in ts6 commands.
sub M::Ban::Info::ts6_match {
    my $ban = shift;

    # if it's a KLINE, it's match_user and match_host joined by a space.
    return join(' ', @$ban{'match_user', 'match_host'})
        if $ban->type eq 'kline';

    # if it's a RESV, it's the match_host followed by a zero.
    return join (' ', $ban->match_host, '0')
        if $ban->type eq 'resv';

    # if it's a DLINE, it's the match_host.
    return $ban->match_host;
}

# create and register a ban with a user and server
sub create_or_update_ban_server_source {
    my ($type, $server, $source, $mask, $duration, $reason) = @_;
    my $ban = M::Ban::create_or_update_ban(
        type         => $type,
        id           => $server->{sid}.'.'.fnv($mask),
        match        => $mask,
        reason       => $reason,
        duration     => $duration,
        aserver      => $source->isa('user')  ?
                        $source->server->name : $source->name,
        auser        => $source->isa('user')  ?
                        $source->full : $source->id.'!services@'.$source->full
    ) or return;
    $ban->set_recent_source($source);
    return $ban;
}

# find a ban for removing
sub _find_ban {
    my ($server, $type, $match) = @_;

    # find by ID
    my $ban = M::Ban::ban_by_id($server->{sid}.'.'.fnv($match));
    return $ban if $ban;

    # find by type and matcher
    $ban = M::Ban::ban_by_user_input($type, $match);
    return $ban if $ban;

    return;
}

################
### OUTGOING ###
################

# kdlines are NOT usually global and therefore are not bursted in TS6.
# so we can't assume that the server is going to give us any info about its
# local bans. that typically only happens when providing "ON <server>" to the
# KLINE or DKLINE command.
#
# however, because juno kdlines are global, we advertise them to TS6 servers
# here. at least ones set on juno should be global, as the oper likely intended.
#
sub burst_bans {
    my $server = shift;
    return 1 if $server->{bans_negotiated}++;
    _burst_bans($server, M::Ban::all_bans());
}
sub _burst_bans {
    my ($server, @bans) = @_;
    return 1 if !@bans;

    # create a fake user. ha! see issue #32.
    my $uid = $me->{sid}.$pool->{user_i};
    my $fake_user = $server->{ban_fake_user} = user->new(
        uid         => $uid,
        nick        => $uid,        # safe_nick() will convert to TS6
        ident       => 'bans',
        host        => $me->name,
        cloak       => $me->name,
        ip          => '0.0.0.0',
        real        => v('LNAME').' ban agent',
        nick_time   => time,
        server      => $me
    );
    $fake_user->set_mode('invisible');
    $fake_user->set_mode('ircop');
    $fake_user->set_mode('service');

    # send out bans
    $server->forward(ban => @bans);

    # delete fake user
    $server->forward(quit => $fake_user, 'Bans set')
        if $fake_user->{agent_introduced};
    delete $server->{ban_fake_user};
    %$fake_user = ();

    return 1;
}

# retrieve the fake user for a server
sub get_fake_user {
    my $to_server = shift;
    my $fake_user = $to_server->{ban_fake_user} or return;

    # it hasn't been introduced
    if (!$fake_user->{agent_introduced}++) {
        $to_server->forward(new_user => $fake_user);
    }

    return $fake_user;
}

# find who to send an outgoing command from
# when only a user can be used
sub find_from {
    my ($to_server, $ban, $postpone_ok) = @_;

    # if there's no user, this is probably during burst.
    my $from = $ban->recent_user;
    $from  ||= get_fake_user($to_server);

    # still nothing...
    if (!$from) {

        # OK maybe there is a server bursting. we will postpone sending
        # the ban out until the burst is done. see issue #119.
        my $server = $ban->recent_source;
        undef $server if !$server || !$server->isa('server') || !$postpone_ok;
        if ($server && $server->{is_burst}) {

            # none postponed yet. add a callback to send them out after burst.
            $server->on(end_burst =>
                \&_send_postponed_bans,
                'send.postponed.bans'
            ) if !$server->{postponed_bans};

            # push to postponed ban list.
            push @{ $server->{postponed_bans}{$to_server} ||= [] }, $ban;
            push @{ $server->{postponed_ban_servers}      ||= [] }, $to_server;

            return;
        }

        # this shouldn't happen.
        notice(server_protocol_warning =>
            $to_server->notice_info,
            'cannot be sent ban info because no source user was specified '.
            "and the ban agent is not available ($$ban{type} $$ban{match})"
        );

        return;
    }

    return $from;
}

# callback to send postponed bans.
sub _send_postponed_bans {
    my $server = shift;
    my $bans = delete $server->{postponed_bans}        or return;
    my $to   = delete $server->{postponed_ban_servers} or return;
    foreach my $to_server (@$to) {
        my $my_bans = delete $bans->{$to_server} or next;
        _burst_bans($to_server, @$my_bans);
    }
}

# find who to send an outgoing command. only server
sub find_from_serv {
    my ($to_server, $ban) = @_;
    my $from = $ban->recent_source;
    undef $from if $from && !$from->isa('server');
    return $from || $me;
}

# find who to send an outgoing command. any user/server
sub find_from_any {
    my ($to_server, $ban) = @_;
    my $from = $ban->recent_source;
    return $from || $me;
}

# this outgoing command is used in JELP for advertising ban identifiers
# and modification times. in TS6, we use it to construct several burst commands.
sub out_ban {
    my $to_server = shift;
    @_ or return;
    return map {
        $_->clear_recent_source;
        out_baninfo($to_server, $_);
    } @_;
}

# baninfo is the advertisement of a ban. in TS6, use ENCAP K/DLINE
sub out_baninfo {
    my ($to_server, $ban) = @_;
    return if !$ts6_supports{ $ban->type };

    # for reserves, it might be a NICKDELAY.
    # we have to check this before the below BAN command check.
    if ($ban->type eq 'resv' && $ban->{_is_nickdelay}) {
        my $maybe = _out_nickdelay($to_server, $ban);
        return $maybe if length $maybe;
    }

    # CAP BAN
    # we might be able to use BAN. if available, this cannot fail.
    if ($ts6_ban_ok{ $ban->type } && $to_server->has_cap('BAN')) {
        my $from = find_from_any($to_server, $ban);
        return _out_capab_ban($to_server, $from, $ban);
    }

    # CAP CLUSTER
    # other reserves might be able to use the non-encap RESV command.
    if ($ban->type eq 'resv') {
        my $maybe = _out_resv($to_server, $ban);
        return $maybe if length $maybe;
    }

    # CAP KLN
    # we might be able to use non-encap KLINE for K-Lines.
    if ($ban->type eq 'kline') {
        my $maybe = _out_kline($to_server, $ban);
        return $maybe if length $maybe;
    }

    # fallback to ENCAP form.
    return _out_encap_generic($to_server, $ban);
}

# returns ENCAP NICKDELAY when possible to use it (with EUID).
# overrides the source user to NickServ when using (ENCAP) RESV command.
sub _out_nickdelay {
    my ($to_server, $ban) = @_;
    return if $ban->has_expired || $ban->ts6_duration < 0;

    # if EUID is available, the server should support ENCAP NICKDELAY.
    if ($to_server->has_cap('EUID')) {

        # this can come from only a server
        my $from = find_from_serv($to_server, $ban) or return;

        return sprintf ':%s ENCAP * NICKDELAY %d %s',
        ts6_id($from),
        $ban->ts6_duration,
        $ban->match;
    }

    # otherwise, we might be able to send out a RESV from NickServ
    # (since ENCAP RESV can only come from a user source).
    my $nickserv = $pool->lookup_user_nick(conf('services', 'nickserv'));
    if ($nickserv && $nickserv->is_mode('service') && !$nickserv->is_local) {

        # set the recent source to NickServ.
        $ban->set_recent_source($nickserv);

        # return false such that out_bandel() will fall back to either
        # CLUSTER RESV or ENCAP RESV with the newly set source.
        return;
    }

    # use either RESV (with CLUSTER) or ENCAP RESV (for anything else).
    return;
}

# CAP CLUSTER
sub _out_resv {
    my ($to_server, $ban) = @_;
    return if !$to_server->has_cap('CLUSTER');
    return if $ban->has_expired || $ban->ts6_duration < 0;

    # RESV can only come from a user
    my $from = find_from($to_server, $ban, 1) or return;

    # :<source> RESV <target> <duration> <mask> :<reason>
    return sprintf ':%s RESV * %d %s :%s',
    ts6_id($from),
    $ban->ts6_duration,
    $ban->match_host,
    $ban->hr_reason;
}

# CAP BAN
# returns the BAN command when possible to use it (with BAN).
# accepts $deleting to indicate that this is a ban removal.
sub _out_capab_ban {
    my ($to_server, $from, $ban, $deleting) = @_;
    return if !$ts6_supports{ $ban->type };
    my $letter = $ts6_ban_ok{ $ban->type } or return;

    # nick!user@host{server} that added it
    # or * if this is being set by a real-time user
    my $added_by = $ban->auser ? "$$ban{auser}\{$$ban{aserver}\}" : '*';
    $added_by = '*' if $from->isa('user');

    # always send the duration as zero if the ban has been expired already
    $deleting++ if $ban->has_expired;

    return sprintf ':%s BAN %s %s %s %d %d %d %s :%s',
    ts6_id($from),          # user or server
    $letter,                # ban type
    $ban->match_user,       # user mask or *
    $ban->match_host,       # host mask
    $ban->modified,         # creationTS (modified time)
    $deleting ? 0 : $ban->duration || $max_duration, # REAL duration (not ts6_duration)
    $ban->lifetime_duration        || $max_duration, # lifetime, relative to creationTS
    $added_by,              # oper field
    $ban->hr_reason;        # reason
}

# CAP KLN
# returns the KLINE command when possible to use it (with KLN).
sub _out_kline {
    my ($to_server, $ban) = @_;
    return if !$to_server->has_cap('KLN');
    return if $ban->has_expired || $ban->ts6_duration < 0;

    # KLINE can only come from a user
    my $from = find_from($to_server, $ban, 1) or return;

    # :<source> KLINE <target> <time> <user> <host> :<reason>
    return sprintf ':%s KLINE * %d %s %s :%s',
    ts6_id($from),
    $ban->ts6_duration,
    $ban->match_user,
    $ban->match_host,
    $ban->hr_reason;
}

# returns the ENCAP form as a last resort. used for kline, resv, dline.
sub _out_encap_generic {
    my ($to_server, $ban) = @_;
    return if !$ts6_encap_ok{ $ban->type };
    return if $ban->has_expired || $ban->ts6_duration < 0;

    # at this point, we have to have a user source
    my $from = find_from($to_server, $ban, 1) or return;

    # encap fallback
    return sprintf ':%s ENCAP * %s %d %s :%s',
    ts6_id($from),
    uc $ban->type,
    $ban->ts6_duration,
    $ban->ts6_match,
    $ban->hr_reason;
}

# bandel is sent out when a ban is removed. in TS6, use ENCAP UNK/DLINE
sub out_bandel {
    my ($to_server, $ban) = @_;
    return if !$ts6_supports{ $ban->type };
    my $from = find_from($to_server, $ban) or return;

    # for reserves, it might be a NICKDELAY.
    # NICKDELAY is certainly supported if EUID is, but even if we don't
    # have EUID, still send this. charybdis does not forward it differently.
    #
    # we have to check this before the below BAN command check
    #
    if ($ban->type eq 'resv' && $ban->{_is_nickdelay}) {
        return if $ban->has_expired;
        return if $ban->ts6_duration < 0;

        # this can come from only a server
        my $from = find_from_serv($to_server, $ban) or return;

        return sprintf ':%s ENCAP * NICKDELAY 0 %s',
        ts6_id($from),
        $ban->match;
    }

    # CAP BAN
    # we might be able to use BAN. if available, this cannot fail.
    if ($ts6_ban_ok{ $ban->type } && $to_server->has_cap('BAN')) {
        my $from = find_from_any($to_server, $ban);
        return _out_capab_ban($to_server, $from, $ban, 1);
    }

    # we might be able to use BAN or non-encap UNKLINE for K-Lines.
    if ($ban->type eq 'kline') {

        # CAP UNKLN
        if ($to_server->has_cap('UNKLN')) {

            # KLINE can only come from a user
            my $from = find_from($to_server, $ban) or return;

            # CAP_UNKLN: :<source> UNKLINE <target> <user> <host>
            return sprintf ':%s UNKLINE * %s %s',
            ts6_id($from),
            $ban->ts6_duration,
            $ban->match_user,
            $ban->match_host;
        }
    }

    # encap fallback
    return if !$ts6_encap_ok{ $ban->type };

    return sprintf ':%s ENCAP * UN%s %s',
    ts6_id($from),
    uc $ban->type,
    $ban->ts6_match;
}

################
### INCOMING ###
################

sub encap_kline   {   kline(@_[0..8]) }
sub encap_unkline { unkline(@_[0..6]) }

# KLINE
#
# 1.
# encap only
# source:       user
# parameters:   duration, user mask, host mask, reason
#
# 2.
# capab: KLN
# source:       user
# parameters:   target server mask, duration, user mask, host mask, reason
#
# From cluster.txt: CAP_KLN:
# :<source> KLINE <target> <time> <user> <host> :<reason>
# :<source> ENCAP <target> KLINE <time> <user> <host> :<reason>
#
sub kline {
    my ($server, $msg, $user, $serv_mask,
    $duration, $ident_mask, $host_mask, $reason) = @_;
    $msg->{encap_forwarded}++;

    # create and activate the ban
    my $match = "$ident_mask\@$host_mask";
    my $ban = create_or_update_ban_server_source(
        # ($type, $server, $user, $mask, $duration, $reason)
        'kline',
        $server, $user, $match, $duration, $reason
    ) or return;

    $ban->notify_new($user);

    #=== Forward ===#
    #
    # we ignore the target mask. juno bans are global, so let's pretend
    # this was intended to be global too.
    #
    $msg->broadcast(baninfo => $ban);
}

# UNKLINE
#
# 1.
# encap only
# source:       user
# parameters:   user mask, host mask
#
# 2.
# capab:        UNKLN
# source:       user
# parameters:   target server mask, user mask, host mask
#
# From cluster.txt: CAP_UNKLN:
# :<source> UNKLINE <target> <user> <host>
# :<source> ENCAP <target> UNKLINE <user> <host>
#
sub unkline {
    my ($server, $msg, $source, $serv_mask, $ident_mask, $host_mask) = @_;
    $msg->{encap_forwarded}++;

    # find and remove ban
    my $ban = _find_ban($server, 'kline', "$ident_mask\@$host_mask") or return;
    $ban->set_recent_source($source);
    $ban->disable or return;

    $ban->notify_delete($source);

    #=== Forward ===#
    $msg->broadcast(bandel => $ban);

}

sub encap_dline   {   dline(@_[0..7]) }
sub encap_undline { undline(@_[0..5]) }

# DLINE
#
# charybdis TS6
# encap only
# source:       user
# parameters:   duration, mask, reason
#
sub dline {
    my ($server, $msg, $user, $serv_mask,
    $duration, $ip_mask, $reason) = @_;
    $msg->{encap_forwarded}++;

    # create and activate the ban
    my $ban = create_or_update_ban_server_source(
        # ($type, $server, $user, $mask, $duration, $reason)
        'dline',
        $server, $user, $ip_mask, $duration, $reason
    ) or return;

    $ban->notify_new($user);

    #=== Forward ===#
    #
    # we ignore the target mask. juno bans are global, so let's pretend
    # this was intended to be global too.
    #
    $msg->broadcast(baninfo => $ban);
}

# UNDLINE
#
# charybdis TS6
# encap only
# source:       user
# parameters:   mask
#
sub undline {
    my ($server, $msg, $user, $serv_mask, $ip_mask) = @_;
    $msg->{encap_forwarded}++;

    # find and remove ban
    my $ban = _find_ban($server, 'dline', $ip_mask) or return;
    $ban->set_recent_source($user);
    $ban->disable or return;

    $ban->notify_delete($user);

    #=== Forward ===#
    $msg->broadcast(bandel => $ban);

}

# ENCAP RESV has a parameter before the reason which charybdis always sends
# as '0', so we're just gonna ignore that and pop the reason off the back.
# [ratbox.ruin.rlygd.net] :903AAAAAY ENCAP * RESV 600 aasaddfsadf 0 :ruded
#                :uid ENCAP   target RESV duration nick_chan_mask 0      :reason
#    params => '-source(user) *      *    *        *              *(opt) *',
sub encap_resv   {   resv(@_[0..6], pop) }
sub encap_unresv { unresv(@_[0..5]     ) }

# RESV
#
# 1.
# encap only
# source:       user
# parameters:   duration, mask, reason
#
# 2.
# capab:        CLUSTER
# source:       user
# parameters:   target server mask, duration, mask, reason
#
# From cluster.txt: CAP_CLUSTER:
# :<source> RESV <target> <name> :<reason>
# :<source> ENCAP <target> RESV <time> <name> 0 :<reason>
#
sub resv  { _resv(0, @_) }
sub _resv {
    my ($is_nickdelay, $server, $msg, $source, $serv_mask,
    $duration, $nick_chan_mask, $reason) = @_;
    $msg->{encap_forwarded}++;

    # create and activate the ban
    my $ban = create_or_update_ban_server_source(
        # ($type, $server, $user, $mask, $duration, $reason)
        'resv',
        $server, $source, $nick_chan_mask, $duration, $reason
    ) or return;

    $ban->notify_new($source);

    #=== Forward ===#
    #
    # we ignore the target mask. juno bans are global, so let's pretend
    # this was intended to be global too.
    # the _is_nickdelay is used for TS6 outgoing.
    #
    $ban->{_is_nickdelay} = $is_nickdelay;
    $msg->broadcast(baninfo => $ban);

    return 1;
}

# UNRESV
#
# 1.
# encap only
# source:       user
# parameters:   mask
#
# 2.
# capab:        CLUSTER
# source:       user
# parameters:   target server mask, mask
#
# From cluster.txt: CAP_CLUSTER:
# :<source> UNRESV <target> <name>
# :<source> ENCAP <target> UNRESV <name>
#
sub unresv  { _unresv(0, @_) }
sub _unresv {
    my ($is_nickdelay, $server, $msg, $source, $serv_mask, $nick_chan_mask) = @_;
    $msg->{encap_forwarded}++;

    # find and remove ban
    my $ban = _find_ban($server, 'resv', $nick_chan_mask) or return;
    $ban->set_recent_source($source);
    $ban->disable or return;

    $ban->notify_delete($source);

    #=== Forward ===#
    #
    # the _is_nickdelay is used for TS6 outgoing.
    #
    $ban->{_is_nickdelay} = $is_nickdelay;
    $msg->broadcast(bandel => $ban);

    return 1;
}

# NICKDELAY
#
# charybdis TS6
# encap only
# encap target: *
# source:       services server
# parameters:   duration, nickname
#
sub encap_nickdelay {
    my ($server, $msg, $source, $serv_mask, $duration, $nick) = @_;

    # no duration means it is a removal
    if (!$duration) {
        return _unresv(1, @_[0..3], $nick);
    }

    my $reason = 'Nickname reserved by services';
    return _resv(1, @_[0..3], $duration, $nick, $reason);
}

# BAN
#
# charybdis TS6
# capab:        BAN
# source:       any
# propagation:  broadcast (restricted)
# parameters:   type, user mask, host mask, creation TS, duration, lifetime,
#               oper, reason
#
# In real-time:
# :900AAAAAB BAN K hahahah google.com 1469473716 300 300 * :bye
#
# During burst:
# :900 BAN K hahahah google.com 1469473716 300 300
# mad__!~mad@opgnrivu.rlygd.net{charybdis.notroll.net} :bye
#
sub ban {
    my ($server, $msg, $source,
        $type,          # 'K' for K-Lines, 'R' for RESVs, 'X' for X-Lines
        $ident_mask,    # user mask or '*' if not applicable
        $host_mask,     # host mask
        $modified,      # the creationTS, which is the time of modification
        $duration,      # the ban duration relative to the creationTS
        $lifetime,      # the ban lifetime relative to creationTS
        $oper,          # nick!user@host{server.name} or '*'
        $reason         # ban reason
    ) = @_;

    # extract server name and oper mask
    my ($found_server_name, $found_oper_mask);
    if ($oper ne '*') {
        ($found_server_name, $found_oper_mask) = ($oper =~ m/^(.*)\{(.*)\}$/);
    }

    # fallbacks for this info
    my $source_serv = $source->isa('user') ? $source->server : $source;
    $found_server_name ||= $source_serv->name;
    $found_oper_mask   ||= $source->full;

    # info used in all ban types
    my $ban;
    my @common = (
        reason       => $reason,
        duration     => $duration,
        added        => $modified,
        modified     => $modified,
        expires      => $modified + $duration,
        lifetime     => $modified + $lifetime,
        aserver      => $found_server_name,
        auser        => $found_oper_mask
    );

    # K-Line
    if ($type eq 'K') {

        # if the duration is 0, this is a deletion
        if (!$duration) {
            # ($server, $msg, $user, $serv_mask, $ident_mask, $host_mask)
            return unkline(@_[0..2], '*', $ident_mask, $host_mask);
        }

        # create and activate the ban
        my $match = "$ident_mask\@$host_mask";
        $ban = M::Ban::create_or_update_ban(
            @common,
            type         => 'kline',
            id           => $server->{sid}.'.'.fnv($match),
            match        => $match
        ) or return;

    }

    # reserves
    elsif ($type eq 'R') {

        # if the duration is 0, this is a deletion
        if (!$duration) {
            # ($server, $msg, $user, $serv_mask, $nick_chan_mask)
            return unresv(@_[0..2], '*', $host_mask);
        }

        # create and activate the ban
        $ban = M::Ban::create_or_update_ban(
            @common,
            type         => 'resv',
            id           => $server->{sid}.'.'.fnv($host_mask),
            match        => $host_mask
        ) or return;

    }

    # unknown type
    else {
        notice(server_protocol_warning =>
            $server->notice_info,
            "sent BAN message with type '$type' which is unknown"
        ) unless $server->{told_missing_bantype}{$type}++;
        return;
    }

    $ban->set_recent_source($source);
    $ban->notify_new($source);

    #=== Forward ===#
    $msg->broadcast(baninfo => $ban);

    return 1;
}

$mod
