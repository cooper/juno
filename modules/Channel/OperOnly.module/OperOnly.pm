# Copyright (c) 2014, matthew
#
# Created on mattbook
# Wed Oct 15 15:48:55 EDT 2014
# OperOnly.pm
#
# @name:            'Channel::OperOnly'
# @package:         'M::Channel::OperOnly'
# @description:     'adds oper only mode'
#
# @depends.modules: ['Base::ChannelModes', 'Base::UserNumerics']
#
# @author.name:     'Matthew Barksdale'
# @author.website:  'https://github.com/mattwb65'
#
package M::Channel::OperOnly;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

sub init {
    
    # register oper only mode block.
    $mod->register_channel_mode_block(
        name => 'oper_only',
        code => \&cmode_operonly
    ) or return;
    
    # register ERR_OPERONLY
    $mod->register_user_numeric(
        name   => 'ERR_OPERONLY',
        number => 520,
        format => '%s :Channel is IRC Operator only'
    ) or return;
    
    # Hook on the can_join event to prevent joining a channel that is oper only
    $pool->on('user.can_join' => \&on_user_can_join, with_eo => 1, name => 'is.oper.only');
    
    return 1;
}

# only opers can set
sub cmode_operonly {
    my ($channel, $mode) = @_;
    $mode->{has_basic_status} or return;
    return 1 if !$mode->{source}->isa('user');
    return $mode->{source}->is_mode('ircop');
}

sub on_user_can_join {
    my ($user, $event, $channel) = @_;
    return unless $channel->is_mode('oper_only');
    return if $user->is_mode('ircop');
    $user->numeric(ERR_OPERONLY => $channel->name);
    $event->stop('channel_operonly');
}



$mod

