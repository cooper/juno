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

use M::TS6::Utils qw(ts6_id);

M::Ban->import(qw(
    enforce_ban         activate_ban        enforce_ban
    get_all_bans        ban_by_id
    add_or_update_ban   delete_ban_by_id
));

our ($api, $mod, $pool, $conf, $me);

###########
### TS6 ###
###########

sub init {

    # IRCd event for burst.
    $pool->on('server.send_ts6_burst' => \&burst_bans,
        name    => 'ts6.banburst',
        after   => 'ts6.mainburst',
        with_eo => 1
    );

    return 1;
}

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
    if (!$server->{bans_negotiated}) {
        $server->fire_command(ban => get_all_bans());
        $server->{bans_negotiated}++;
    }
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
    my ($to_server, $ban, $from) = @_;

    # TS6 only supports kdlines
    return unless $ban->{type} eq 'kline' || $ban->{type} eq 'dline';

    # FIXME: LOL! ENCAP K/DLINE can only come from a user.
    # if there's no user, this is probably during burst.
    if (!$from || !$from->isa('user')) {
        $from = ($pool->local_users)[0];
        return if !$from;
    }

    # TS6 durations are in minutes rather than seconds, so convert this.
    # (if it's permanent it will be zero which is the same)
    my $duration = $ban->{duration};
    if ($duration) {
        $duration = int($duration / 60 + 0.5);
        $duration = 1 if $duration < 1;
    }

    # charybdis will send the encap target as it is received from the oper.
    # we don't care about that though. juno bans are global.

    return sprintf ':%s ENCAP * %s %d %s :%s',
    ts6_id($from),
    uc $ban->{type},
    $duration,
    $ban->{match},
    $ban->{reason};
}


$mod
