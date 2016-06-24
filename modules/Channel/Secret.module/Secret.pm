# Copyright (c) 2014, matthew
#
# Created on mattbook
# Wed Jul  2 02:28:01 EDT 2014
# Secret.pm
#
# @name:            'Channel::Secret'
# @package:         'M::Channel::Secret'
# @description:     'Allows a channel to be marked secret'
#
# @depends.modules: ['Base::ChannelModes', 'Core::ChannelModes']
#
# @author.name:     'Matthew Barksdale'
# @author.website:  'https://github.com/mattwb65'
#
package M::Channel::Secret;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

sub init {

    # register secret mode block.
    $mod->register_channel_mode_block(
        name => 'secret',
        code => \&M::Core::ChannelModes::cmode_normal
    ) or return;

    # Hook on the show_in_list and show_in_whois events to prevent secret
    # channels from showing in list or WHOIS
    $pool->on('channel.show_in_list' => \&show_in_things,
        with_eo => 1,
        name => 'channel.secret.show_in_list'
    );
    $pool->on('channel.show_in_whois' => \&show_in_things,
        with_eo => 1,
        name => 'channel.secret.show_in_whois'
    );

    return 1;
}

sub show_in_things {
    my ($channel, $event, $user) = @_;

    # if it's not secret, show it.
    return unless $channel->is_mode('secret');

    # if the user asking has super powers, show it.
    return if $user->has_flag('see_secret');

    # if it is secret, but this guy's in there, show it.
    return if $channel->has_user($user);

    $event->stop;
}

$mod
