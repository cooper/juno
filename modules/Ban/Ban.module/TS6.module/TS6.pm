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

use utils qw(fnv v);
use M::TS6::Utils qw(ts6_id);

M::Ban->import(qw(
    enforce_ban         activate_ban        enforce_ban
    get_all_bans        ban_by_id
    add_or_update_ban   delete_ban_by_id
));

our ($api, $mod, $pool, $conf, $me);

our %ts6_capabilities = (
    KLN   => { required => 0 },
    UNKLN => { required => 0 }
);

our %ts6_outgoing_commands = (
    ban     => \&out_ban,
    baninfo => \&out_baninfo,
    bandel  => \&out_bandel
);

our %ts6_incoming_commands = (
    ENCAP_KLINE => {
                  # :uid ENCAP    target KLINE duration ident_mask host_mask :reason
        params => '-source(user)  *      *     *        *          *         *',
        code   => \&encap_kline
    },
    ENCAP_DLINE => {
                  # :uid ENCAP    target DLINE duration ip_mask :reason
        params => '-source(user)  *      *     *        *       *',
        code   => \encap_&dline
    }
);

sub init {

    # IRCd event for burst.
    $pool->on('server.send_ts6_burst' => \&burst_bans,
        name    => 'ts6.banburst',
        after   => 'ts6.endburst',
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
    $ban{id} //= fnv($ban{match});

    # TS6 durations are in minutes rather than seconds, so convert this.
    # (if it's permanent it will be zero which is the same)
    my $duration = $ban{duration};
    if ($duration) {
        $duration = int($duration / 60 + 0.5);
        $duration = 1 if $duration < 1;
        $ban{duration} = $duration;
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
sub create_ts6_ban {
    my %ban = ts6_ban(@_);
    add_or_update_ban(%ban);
    enforce_ban(%ban);
    activate_ban(%ban);
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

    # if there's no user, this is probably during burst.
    my $from = $pool->lookup_user($ban{_just_set_by})
        || get_fake_user($to_server) or return;

    # charybdis will send the encap target as it is received from the oper.
    # we don't care about that though. juno bans are global.

    return sprintf ':%s ENCAP * %s %d %s :%s',
    ts6_id($from),
    uc $ban{type},
    $ban{duration} || 0,
    $ban{match_ts6},
    $ban{reason} // 'no reason';
}

# bandel is sent out when a ban is removed. in TS6, use ENCAP UNK/DLINE
sub out_bandel {
    my ($to_server, $ban_) = @_;
    my %ban = ts6_ban(%$ban_) or return;

    # if there's no user, this is probably during burst.
    my $from = $pool->lookup_user($ban{_just_set_by})
        || get_fake_user($to_server) or return;

    return sprintf ':%s ENCAP * UN%s %s',
    ts6_id($from),
    uc $ban{type},
    $ban{match_ts6};
}

################
### INCOMING ###
################

sub encap_kline {
    my ($server, $msg, $user, $serv_mask, undef,
    $duration, $ident_mask, $host_mask, $reason) = @_;
    # forward and/or
    # call kline(stuff)
}

sub encap_dline {
    my ($server, $msg, $user, $serv_mask, undef,
    $duration, $ip_mask, $reason) = @_;
    # forward and/or
    # call dline(stuff)
}

$mod
