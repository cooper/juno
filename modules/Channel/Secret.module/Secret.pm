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
# @depends.modules: ['Base::ChannelModes']
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

# channel mode blocks
our %channel_modes = (
    secret  => { type => 'normal' },
    private => { type => 'normal' }
);

sub init {

    # Hook on the show_in_list, show_in_whois, and show_in_names events to
    # prevent secret or private channels from showing
    $pool->on('channel.show_in_list' =>
        \&show_in_list,
        'channel.secret.show_in_list'
    );
    $pool->on('channel.show_in_whois' =>
        \&show_in_whois,
        'channel.secret.show_in_whois'
    );

    # names_character allows us to change the "=" in NAMES to "@" or "*"
    # for secret and private channels respectively
    $pool->on('channel.names_character' =>
        \&names_character,
        'channel.secret.names_character'
    );

    return 1;
}

my $SHOW_IT;

sub show_in_list {
    my ($channel, $event, $user) = @_;

    # if it's neither secret nor private, we are not concerned with this.
    return $SHOW_IT
        if !$channel->is_mode('secret') && !$channel->is_mode('private');

    # if the user asking has super powers, show it.
    return $SHOW_IT
        if $user->has_flag('see_secret');

    # if it is secret or private, but this guy's in there, show it.
    return $SHOW_IT
        if $channel->has_user($user);

    $event->stop;
}

sub show_in_whois {
    my ($channel, $event, $quser, $ruser) = @_;

    # $quser = the one being queried
    # $ruser = the one requesting the info

    # if it's not secret, we are not concerned with this
    # because private channels show up in WHOIS.
    return $SHOW_IT
        unless $channel->is_mode('secret');

    # if the user asking has super powers, show it.
    return $SHOW_IT
        if $ruser->has_flag('see_secret');

    # if it is secret, but the one requesting it is in there, show it.
    return $SHOW_IT
        if $channel->has_user($ruser);

    $event->stop;
}

sub show_in_names {
    my ($channel, $event, $quser, $ruser) = @_;

    # $quser = the one being queried
    # $ruser = the one requesting the info

    # if it's neither secret nor private, we are not concerned with this.
    return $SHOW_IT
        if !$channel->is_mode('secret') && !$channel->is_mode('private');

    # if it is secret or private, but this guy's in there, show it.
    return $SHOW_IT
        if $channel->has_user($ruser);

    $event->stop;
}

# override the character in NAMES
sub names_character {
    my ($channel, $event, $c) = @_;
    # $c is a string reference with the current character
    $$c = "*" if $channel->is_mode('private');
    $$c = "@" if $channel->is_mode('secret'); # more important than private
}

$mod
