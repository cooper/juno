# Copyright (c) 2016, matthew
#
# Created on MacBook-Pro
# Fri Jul 29 20:57:09 EDT 2016
# RegisteredOnly.pm
#
# @name:            'Channel::RegisteredOnly'
# @package:         'M::Channel::RegisteredOnly'
# @description:     'Adds mode to allow only registered users to join'
#
# @depends.modules: ['Base::ChannelModes', 'Base::UserNumerics']
#
# @author.name:     'Matt Barksdale'
# @author.website:  'https://github.com/mattwb65.com'
#
package M::Channel::RegisteredOnly;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

# numerics
our %user_numerics = (
    ERR_NEEDREGGEDNICK => [ 477, '%s :Cannot join channel (+r) - you need to be identified with services']
);

# channel modes
our %channel_modes = (
    reg_only => { type => 'normal' }
);


sub init {
    # Hook on to the can_join event to prevent joining a channel that is registered users only.
    $pool->on('user.can_join' => \&on_user_can_join,
        with_eo => 1,
        name    => 'is.registered.user'
    );

    return 1;
}

sub on_user_can_join {
    my ($user, $event, $channel) = @_;
    # A user can join a channel that isn't +r
    return unless $channel->is_mode('reg_only');
    # User must be registered otherwise
    return if exists $user->{account};
    # Let them know they can't join if they're not registered
    $user->numeric(ERR_NEEDREGGEDNICK => $channel->name);
    $event->stop('channel_reg_only');
}

$mod

