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
    
    # Hook on the show_in_list event to prevent secret channels frm showing in list
    $pool->on('channel.show_in_list' => \&on_show_in_list, with_eo => 1, name => 'show.list');
    
    return 1;
}

sub on_show_in_list {
    my ($channel, $event, $user) = @_;
    return unless $channel->is_mode('secret');
    return unless !$channel->has_user($user);
    $event->stop;
}

$mod

