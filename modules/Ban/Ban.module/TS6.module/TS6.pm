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

use utils qw(fnv v notice);
use M::TS6::Utils qw(ts6_id);

M::Ban->import(qw(
    notify_new_ban  notify_delete_ban
    get_all_bans    delete_ban_by_id
    ban_by_id       ban_by_type_match
    add_update_enforce_activate_ban
));

our ($api, $mod, $pool, $conf, $me);

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
        params => '-source(user)  *      *     *        *       :rest',
        code   => \&encap_dline
    },
    ENCAP_UNDLINE => {
                  # :uid ENCAP    target UNDLINE ip_mask
        params => '-source(user)  *      *       *',
        code   => \&encap_undline
    },
    ENCAP_KLINE => {
                  # :<source> ENCAP <target> KLINE <time>   <user>     <host>    :<reason>
        params => '-source(user)    *        *     *        *          *         :rest',
        code   => \&encap_kline
    },
    ENCAP_UNKLINE => {
                  # :<source> ENCAP <target> UNKLINE <user>     <host>
        params => '-source(user)    *        *       *          *',
        code   => \&encap_unkline
    },
    KLINE => {
                  # :<source> KLINE <target> <time> <user> <host> :<reason>
        params => '-source(user)    *        *      *      *      :rest',
        code   => \&kline
    },
    UNKLINE => {
                  # :<source> KLINE <target> <user> <host>
        params => '-source(user)    *        *      *',
        code   => \&unkline
    },
    BAN => {
                  # :source BAN type user host creationTS duration lifetime oper reason
        params => '-source      *    *    *    ts         *        *        *    :rest',
        code   => \&ban
    },
);

sub init {

    # IRCd event for burst.
    $pool->on('server.send_ts6_burst' => \&burst_bans,
        name    => 'ts6.banburst',
        after   => 'ts6.mainburst',
        with_eo => 1
    );

    return 1;
}

# takes a ban hash and returns one ready for ts6 use
sub ts6_ban {
    my %ban = @_;

    # TS6 only supports kdlines
    return unless $ban{type} eq 'kline' || $ban{type} eq 'dline';

    # create an ID based on the fnv hash of the mask
    # this is a last resort... it should already be set
    $ban{id} //= $me->{sid}.'.'.fnv($ban{match});

    # TS6 bans have to have a reason
    $ban{reason} = 'no reason' if !length $ban{reason};

    # prepare the duration for TS6
    if ($ban{duration} || $ban{expires}) {
        my $duration = $ban{duration} || 0;

        # we can't propagate an expiration time over TS6, so we have to
        # calculate how long the duration should be from the current time
        $duration = $ban{expires} - time
            if $ban{expires};

        $ban{ts6_duration} = $duration;
    }
    else {
        $ban{ts6_duration} = 0;
    }

    # add user and host if there's an @
    if ($ban{match} =~ m/^(.*?)\@(.*)$/) {
        $ban{match_user} = $1;
        $ban{match_host} = $2;
    }
    else {
        $ban{match_user} = '*';
        $ban{match_host} = $ban{match};
    }

    # match_ts6 is special for using in ts6 commands.
    # if it's a KLINE, it's match_user and match_host joined by a space.
    # if it's a DLINE, it's the match_host.
    $ban{match_ts6} = $ban{type} eq 'kline' ?
        join(' ', @ban{'match_user', 'match_host'}) : $ban{match_host};

    # this is a safety check for dumb things like a DLINE on someone@*
    return if $ban{match_ts6} eq '*';

    return %ban;
}

# create and register a ban
sub add_update_enforce_activate_ts6_ban {
    my %ban = ts6_ban(@_) or return;
    %ban = add_update_enforce_activate_ban(%ban);
    return %ban;
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
    my ($server, $event, $time) = @_;

    # if there are no bans, stop here
    return 1 if $server->{bans_negotiated}++;
    my @bans = get_all_bans() or return 1;

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
    $server->fire_command(ban => @bans);

    # delete fake user
    $server->fire_command(quit => $fake_user, 'Bans set')
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
        $to_server->fire_command(new_user => $fake_user);
    }

    return $fake_user;
}

# find who to send an outgoing command from
sub find_from {
    my ($to_server, %ban) = @_;

    # if there's no user, this is probably during burst.
    my $from = $pool->lookup_user($ban{_just_set_by})
        || get_fake_user($to_server);

    # this shouldn't happen.
    if (!$from) {
        notice(server_protocol_warning =>
            $to_server->notice_info,
            'cannot be sent ban info because no source user was specified and '.
            'the ban agent is not available'
        );
        return;
    }

    return $from;
}

# this outgoing command is used in JELP for advertising ban identifiers
# and modification times. in TS6, we use it to construct several burst commands.
sub out_ban {
    my $to_server = shift;
    @_ or return;
    return map out_baninfo($to_server, $_), @_;
}

# baninfo is the advertisement of a ban. in TS6, use ENCAP K/DLINE
sub out_baninfo {
    my ($to_server, $ban_) = @_;
    my %ban = ts6_ban(%$ban_) or return;

    # charybdis will send the encap target as it is received from the oper.
    # we don't care about that though. juno bans are global.

    # we might be able to use BAN or non-encap KLINE for K-Lines.
    if ($ban{type} eq 'kline') {

        # CAP BAN
        if ($to_server->has_cap('BAN')) {

            # this can come from either a user or a server
            my $from = $pool->lookup_user($ban{_just_set_by}) || $me;

            return _capab_ban($to_server, $from, \%ban);
        }

        # CAP KLN
        if ($to_server->has_cap('KLN')) {

            # KLINE can only come from a user
            my $from = find_from($to_server, %ban) or return;

            # :<source> KLINE <target> <time> <user> <host> :<reason>
            return sprintf ':%s KLINE * %d %s %s :%s',
            ts6_id($from),
            $ban{ts6_duration},
            $ban{match_user},
            $ban{match_host},
            $ban{reason};
        }
    }

    # at this point, we have to have a user source
    my $from = find_from($to_server, %ban) or return;

    # encap fallback
    return sprintf ':%s ENCAP * %s %d %s :%s',
    ts6_id($from),
    uc $ban{type},
    $ban{ts6_duration},
    $ban{match_ts6},
    $ban{reason};
}

# bandel is sent out when a ban is removed. in TS6, use ENCAP UNK/DLINE
sub out_bandel {
    my ($to_server, $ban_) = @_;
    my %ban = ts6_ban(%$ban_) or return;
    my $from = find_from($to_server, %ban) or return;

    # we might be able to use BAN or non-encap UNKLINE for K-Lines.
    if ($ban{type} eq 'kline') {

        # CAP BAN
        if ($to_server->has_cap('BAN')) {

            # this can come from either a user or a server
            my $from = $pool->lookup_user($ban{_just_set_by}) || $me;

            $ban{duration} = 0; # indicates deletion
            return _capab_ban($to_server, $from, \%ban);
        }

        # CAP UNKLN
        if ($to_server->has_cap('UNKLN')) {

            # KLINE can only come from a user
            my $from = find_from($to_server, %ban) or return;

            # CAP_UNKLN: :<source> UNKLINE <target> <user> <host>
            return sprintf ':%s UNKLINE * %s %s',
            ts6_id($from),
            $ban{ts6_duration},
            $ban{match_user},
            $ban{match_host};
        }
    }

    # encap fallback
    return sprintf ':%s ENCAP * UN%s %s',
    ts6_id($from),
    uc $ban{type},
    $ban{match_ts6};
}

sub _capab_ban {
    my ($to_server, $from, $ban_) = @_;

    # the ban has already been validated
    # the {duration} may be 0 if this is an unban
    my %ban = %$ban_;

    # only these are supported
    my %possible = (
        kline => 'K',
      # xline => 'X',
      # resv  => 'R'
    );
    my $letter = $possible{ $ban{type} } or return;

    # nick!user@host{server} that added it
    # or * if this is being set by a real-time user
    my $added_by = $ban{auser} ? "$ban{auser}\{$ban{aserver}\}" : '*';
    $added_by = '*' if $from->isa('user');

    return sprintf ':%s BAN %s %s %s %d %d %d %s :%s',
    ts6_id($from),          # user or server
    $letter,                # ban type
    $ban{match_user},       # user mask or *
    $ban{match_host},       # host mask
    $ban{modified},         # creationTS (modified time)
    $ban{duration},         # REAL duration (not ts6_duration)
    $ban{duration},         # FIXME: lifetime
    $added_by,              # oper field
    $ban{reason};           # reason
}

################
### INCOMING ###
################

sub encap_kline   {   kline(@_[0..3, 5..8]) }
sub encap_dline   {   dline(@_[0..3, 5..7]) }
sub encap_unkline { unkline(@_[0..3, 5, 6]) }
sub encap_undline { undline(@_[0..3, 5   ]) }

sub kline {
    my ($server, $msg, $user, $serv_mask,
    $duration, $ident_mask, $host_mask, $reason) = @_;
    $msg->{encap_forwarded} = 1;

    # create and activate the ban
    my $match = "$ident_mask\@$host_mask";
    my %ban = add_update_enforce_activate_ts6_ban(
        type         => 'kline',
        id           => $server->{sid}.'.'.fnv($match),
        match        => $match,
        reason       => $reason,
        duration     => $duration,
        aserver      => $user->server->name,
        auser        => $user->full,
        _just_set_by => $user->id
    ) or return;

    notify_new_ban($user, %ban);

    #=== Forward ===#
    #
    # we ignore the target mask. juno bans are global, so let's pretend
    # this was intended to be global too.
    #
    $msg->forward(baninfo => \%ban);
}

sub dline {
    my ($server, $msg, $user, $serv_mask,
    $duration, $ip_mask, $reason) = @_;
    $msg->{encap_forwarded} = 1;

    # create and activate the ban
    my %ban = add_update_enforce_activate_ts6_ban(
        type         => 'dline',
        id           => $server->{sid}.'.'.fnv($ip_mask),
        match        => $ip_mask,
        reason       => $reason,
        duration     => $duration,
        aserver      => $user->server->name,
        auser        => $user->full,
        _just_set_by => $user->id
    ) or return;

    notify_new_ban($user, %ban);

    #=== Forward ===#
    #
    # we ignore the target mask. juno bans are global, so let's pretend
    # this was intended to be global too.
    #
    $msg->forward(baninfo => \%ban);
}

# find a ban for removing
sub _find_ban {
    my ($server, $type, $match) = @_;
    my $id_maybe = $server->{sid}.'.'.fnv($match);
    my %ban = ban_by_id($id_maybe);
    return %ban if %ban;
    %ban = ban_by_type_match($type, $match);
    return %ban if %ban;
    return;
}

sub unkline {
    my ($server, $msg, $source, $serv_mask, $ident_mask, $host_mask) = @_;
    $msg->{encap_forwarded} = 1;

    # find and remove ban
    my %ban = _find_ban($server, 'kline', "$ident_mask\@$host_mask") or return;
    delete_ban_by_id($ban{id});

    notify_delete_ban($source, %ban);

    #=== Forward ===#
    $msg->forward(bandel => \%ban);

}

sub undline {
    my ($server, $msg, $user, $serv_mask, $ip_mask) = @_;
    $msg->{encap_forwarded} = 1;

    # find and remove ban
    my %ban = _find_ban($server, 'dline', $ip_mask) or return;
    delete_ban_by_id($ban{id});

    notify_delete_ban($user, %ban);

    #=== Forward ===#
    $msg->forward(bandel => \%ban);

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

    # K-Line
    if ($type eq 'K') {

        # if the duration is 0, this is a deletion
        if (!$duration) {
            # ($server, $msg, $user, $serv_mask, $ident_mask, $host_mask)
            return unkline(@_[0..2], '*', $ident_mask, $host_mask);
        }

        # create and activate the ban
        my $match = "$ident_mask\@$host_mask";
        my %ban = add_update_enforce_activate_ts6_ban(
            type         => 'kline',
            id           => $server->{sid}.'.'.fnv($match),
            match        => $match,
            reason       => $reason,
            duration     => $duration,
            aserver      => $found_server_name,
            auser        => $found_oper_mask,
            _just_set_by => $source->{uid} # or undef if it's a server
        ) or return;

        notify_new_ban($source, %ban);

        #=== Forward ===#
        $msg->forward(baninfo => \%ban);

        return 1;
    }

    notice(server_protocol_warning =>
        $server->notice_info,
        "sent BAN message with type '$type' which is unknown"
    ) unless $server->{told_missing_bantype}{$type}++;
    return;
}

$mod
