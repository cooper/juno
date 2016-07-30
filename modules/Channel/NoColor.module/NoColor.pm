# Copyright (c) 2016, matthew
#
# Created on MacBook-Pro
# Fri Jul 29 20:57:09 EDT 2016
# NoColor.pm
#
# @name:            'Channel::NoColor'
# @package:         'M::Channel::NoColor'
# @description:     'Adds mode to strip colors from channel messages'
#
# @depends.modules: ['Base::ChannelModes']
#
# @author.name:     'Matt Barksdale'
# @author.website:  'https://github.com/mattwb65'
#
package M::Channel::NoColor;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

# channel modes
our %channel_modes = (
    strip_colors => { type => 'normal' }
);


sub init {
    # Hook on to the can_message event to strip colors.
    $pool->on('user.can_message' => \&on_user_can_message,
        with_eo => 1,
        name    => 'strip.colors'
    );

    return 1;
}

sub on_user_can_message {
    my ($user, $event, $channel, $message) = @_;
    # No need to strip color if the channel isn't +c
    return unless $channel->is_mode('strip_colors');
    # Borrowed from IRC::Utils
    $message =~ s/\x03(?:,\d{1,2}|\d{1,2}(?:,\d{1,2})?)?//g; # mIRC
    $message =~ s/\x04[0-9a-fA-F]{0,6}//ig; # RGB
    $message =~ s/\x1B\[.*?[\x00-\x1F\x40-\x7E]//g; # ECMA-48
    $message =~ s/[\x02\x1f\x16\x1d\x11\x06]//g; # Formatting
    $message =~ s/\x0f//g; # Cancellation
    $event->{new_message} = $message;
}

$mod

