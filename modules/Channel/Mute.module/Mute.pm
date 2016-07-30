# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-MacBook-Pro.local
# Thu Oct 16 16:15:38 EDT 2014
# Mute.pm
#
# @name:            'Channel::Mute'
# @package:         'M::Channel::Mute'
# @description:     'adds channel mute ban'
#
# @depends.modules: ['Base::ChannelModes', 'Base::UserNumerics']
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Channel::Mute;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

# numerics
our %user_numerics = (
    RPL_QUIETLIST       => [ 728, '%s %s %s %s %d'                  ],
    RPL_ENDOFQUIETLIST  => [ 729, '%s %s :End of channel mute list' ]
);

# channel mode block
our %channel_modes = (
    mute => {
        type        => 'banlike',
        list        => 'mute',    # name of the list mode
        reply       => 'quiet',   # reply numerics to send
        show_mode   => 1          # show the mode letter in replies
    }
);

sub init {

    # message blocking event - muted and no voice?
    $pool->on('user.can_message' => \&on_user_can_message,
        name        => 'stop.muted.users',
        with_eo     => 1,
        priority    => 10
    );

    return 1;
}

sub on_user_can_message {
    my ($user, $event, $channel, $message, $type) = @_;

    # has voice.
    return if $channel->user_get_highest_level($user) >= -2;

    # not muted.
    return unless $channel->list_matches('mute', $user);

    # has an exception.
    return if $channel->list_matches('except', $user);

    $event->{error_reply} =
        [ ERR_CANNOTSENDTOCHAN => $channel->name, "You're muted" ];
    $event->stop('muted');
}

$mod
