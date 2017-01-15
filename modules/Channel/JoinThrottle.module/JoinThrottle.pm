# Copyright (c) 2009-16, Mitchell Cooper
#
# @name:            "Channel::JoinThrottle"
# @package:         "M::Channel::JoinThrottle"
# @description:     "channel mode to prevent join flooding"
#
# @depends.bases+   'ChannelModes', 'UserNumerics'
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Channel::JoinThrottle;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $me, $pool);

our %channel_modes = (
    join_throttle => { code => \&cmode_throttle },
);

our %user_numerics = (
    ERR_THROTTLE => [ 480,
        '%s :Cannot join channel - throttle exceeded, try again later' ]
);

sub init {
    $pool->on('channel.user_joined' =>
        \&on_user_joined, 'update.join.throttle');
    $pool->on('user.can_join' =>
        \&on_user_can_join, 'check.join.throttle');
    return 1;
}

# $channel->{throttle} = {
#   joins       => number of joins permitted
#   secs        => in this number of seconds
#   time        => number of seconds to lock the channel (optional)
#   count       => number of joins since the last reset
#   reset       => time at which the counter should be reset
#   locked      => time at which the channel should be unlocked
# }
#
sub cmode_throttle {
    my ($channel, $mode) = @_;
    $mode->{has_basic_status} or return;

    # always allow unsetting.
    if (!$mode->{state}) {
        delete $channel->{throttle};
        return 1;
    }

    # normalize/check if valid.
    if ($mode->{param} =~ m/^(\d+):(\d+)(?::(\d+))?$/) {
        @{ $channel->{throttle} }{ qw(joins secs time) } = ($1, $2, $3);
        return 1;
    }

    return;
}

sub on_user_joined {
    my ($channel, $event, $user) = @_;

    # we're not interested in joins during burst.
    return if $user->location->{is_burst};

    # we're not interested if the channel has no throttle
    # or if the channel is already locked.
    my $throttle = $channel->{throttle};
    return if !$throttle || $throttle->{locked};

    # time to reset the counter.
    if (time >= ($throttle->{reset} || 0)) {
        $throttle->{count} = 0;
        $throttle->{reset} = time() + $throttle->{secs};
    }

    # increment the counter. if it is more than the max number of joins,
    # lock the channel.
    if (++$throttle->{count} >= $throttle->{joins}) {
        my $secs_to_lock = $throttle->{time} || 60;
        $throttle->{count}  = 0;
        $throttle->{locked} = time() + $secs_to_lock;
        L("join throttle: locking $$channel{name} for $secs_to_lock seconds")
    }
}

sub on_user_can_join {
    my ($user, $event, $channel, $key) = @_;

    # we're only interested when the channel is locked.
    my $throttle = $channel->{throttle};
    return if !$throttle || !$throttle->{locked};

    # time to unlock the channel.
    if (time >= $throttle->{locked}) {
        L("join throttle: unlocking $$channel{name}");
        delete $throttle->{locked};
        return;
    }

    # user has invite.
    return if $channel->user_has_invite($user);

    $event->{error_reply} = [ ERR_THROTTLE => $channel->name ];
    $event->stop('join throttle active');
}

$mod
