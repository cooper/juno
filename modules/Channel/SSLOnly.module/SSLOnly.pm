# Copyright (c) 2016, matthew
#
# Created on MacBook-Pro
# Fri Jul 29 20:57:09 EDT 2016
# SSLOnly.pm
#
# @name:            'Channel::SSLOnly'
# @package:         'M::Channel::SSLOnly'
# @description:     'Adds mode to allow only ssl users to join'
#
# @depends.modules: ['Base::ChannelModes']
#
# @author.name:     'Matt Barksdale'
# @author.website:  'https://github.com/mattwb65'
#
package M::Channel::SSLOnly;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);


# channel modes 
our %channel_modes = (
    ssl_only => { type => 'normal' }
);


sub init {
    # Hook on to the can_join event to prevent joining a channel that is ssl users only.
    $pool->on('user.can_join' => \&on_user_can_join,
        with_eo => 1,
        name    => 'is.ssl.user'
    );

    return 1;
}

sub on_user_can_join {
    my ($user, $event, $channel) = @_;
    # A user can join a channel that isn't +S
    return unless $channel->is_mode('ssl_only');
    # User must be connected via ssl otherwise
    return if exists $user->{ssl};
    # Let them know they can't join if they're not on ssl
    $user->server_notice("Only users using SSL can join this channel!");
    $event->stop('channel_ssl_only');
}

$mod

