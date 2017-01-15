# Copyright (c) 2016, Mitchell Cooper
#
# @name:            "Channel::Knock"
# @package:         "M::Channel::Knock"
# @description:     "request to join a restricted channel"
#
# @depends.bases+   'UserCommands', 'UserNumerics'
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Channel::Knock;

use warnings;
use strict;
use 5.010;

use List::Util qw(first);
use utils qw(ref_to_list broadcast);

our ($api, $mod, $me, $pool);

our %user_commands = (KNOCK => {
    desc   => 'request to join a restricted channel',
    params => 'channel',
    code   => \&knock
});

our %user_numerics = (
    RPL_KNOCKDLVR   => [ 711, '%s :Your knock was delivered'        ],
    RPL_KNOCK       => [ 710, '%s %s :has asked for an invite'      ],
    ERR_CHANOPEN    => [ 713, '%s :Channel is open'                 ],
    ERR_KNOCKONCHAN => [ 714, '%s :You\'re already on that channel' ]
);

sub init {

    # add KNOCK to RPL_ISUPPORT
    $me->on(supported => sub {
        my ($event, $supported, $yes) = @_;
        $supported->{KNOCK} = $yes;
    });

    # knock events
    $pool->on('user.can_knock' => \&on_user_can_knock, 'check.banned');
    $pool->on('channel.knock'  => \&on_channel_knock,  'notify.channel');

    return 1;
}

sub knock {
    my ($user, $event, $channel) = @_;

    # already there
    if ($channel->has_user($user)) {
        $user->numeric(ERR_KNOCKONCHAN => $channel->name);
        return;
    }

    # not restricted
    if (not first { $channel->is_mode($_ ) } qw(invite_only key limit)) {
        $user->numeric(ERR_CHANOPEN => $channel->name);
        return;
    }

    # fire can_knock. if canceled, we can't.
    # callbacks may set {error_reply} to a numeric.
    my $fire = $user->fire(can_knock => $channel);
    if ($fire->stopper) {
        my $err = $fire->{error_reply};
        $user->numeric(ref_to_list($err)) if $err;
        return;
    }

    # TODO: (#153) check for ridiculous knocking behavior.
    # too many knocks to the channel or too many from this user.
    # send ERR_TOOMANYKNOCK on fail.

    $channel->fire(knock => $user);
    broadcast(knock => $user, $channel);
}

sub on_user_can_knock {
    my ($user, $event, $channel) = @_;
    return unless $channel->user_is_banned($user);
    $event->{error_reply} =
        [ ERR_CANNOTSENDTOCHAN => $channel->name, "You're banned" ];
    $event->stop('banned');
}

sub on_channel_knock {
    my ($channel, $event, $user) = @_;

    # unless the channel is free invite, only notify ops
    my @notify = $channel->real_local_users;
    @notify = grep { $channel->user_has_basic_status($_) } @notify
        unless $channel->is_mode('free_invite');
    $_->numeric(RPL_KNOCK => $channel->name, $user->full) for @notify;

    # TODO: (#153) increment the knock count on this channel

    # notify the user that the knock was delivered if he's local
    $user->numeric(RPL_KNOCKDLVR => $channel->name)
        if $user->is_local;
}

$mod
