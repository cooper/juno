# Copyright (c) 2014, matthew
#
# Created on mattbook
# Wed Jul  2 02:28:01 EDT 2014
# Secret.pm
#
# @name:            'Channel::Secret'
# @package:         'M::Channel::Secret'
# @description:     'allows a channel to be marked secret or private'
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

# TODO: once KNOCKing is implemented, make sure it's not permitted
# for channels with +p set (ERR_CANNOTSENDTOCHAN) but is for +s

sub init {

    # register secret mode block.
    $mod->register_channel_mode_block(
        name => 'secret',
        code => \&M::Core::ChannelModes::cmode_normal
    ) or return;

    # register private mode block.
    $mod->register_channel_mode_block(
        name => 'secret',
        code => \&M::Core::ChannelModes::cmode_normal
    ) or return;

    # Hook on the show_in_list and show_in_whois events to prevent secret
    # channels from showing in list or WHOIS
    $pool->on('channel.show_in_list' => \&show_in_list,
        with_eo => 1,
        name => 'channel.secret.show_in_list'
    );
    $pool->on('channel.show_in_whois' => \&show_in_whois,
        with_eo => 1,
        name => 'channel.secret.show_in_whois'
    );

    return 1;
}

my $SHOW_IT;

sub show_in_list {
    my ($channel, $event, $user) = @_;

    # if it's neither secret not private, we are not concerned with this.
    return $SHOW_IT if
        !$channel->is_mode('secret') && !$channel->is_mode('private');

    # if the user asking has super powers, show it.
    return $SHOW_IT if
        $user->has_flag('see_secret');

    # if it is secret or private, but this guy's in there, show it.
    return $SHOW_IT
        if $channel->has_user($user);

    $event->stop;
}

sub show_in_whois {
    my ($channel, $event, $user) = @_;

    # if it's not secret, we are not concerned with this
    # because private channels show up in WHOIS.
    return $SHOW_IT
        unless $channel->is_mode('secret');

    # if the user asking has super powers, show it.
    return $SHOW_IT
        if $user->has_flag('see_secret');

    # if it is secret, but this guy's in there, show it.
    return $SHOW_IT
        if $channel->has_user($user);

    $event->stop;
}

$mod
