# Copyright (c) 2014, mitchellcooper
#
# Created on Mitchells-MacBook-Pro.local
# Thu Oct 16 16:15:38 EDT 2014
# Mute.pm
#
# @name:            'Channel::Mute'
# @package:         'M::Channel::Mute'
# @description:     'adds channel mute ban'
#
# @depends.modules: ['Core::ChannelModes', 'Base::UserNumerics']
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Channel::Mute;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);
my $ccm;

sub init {
    
    # add numerics.
    $mod->register_user_numeric(
        name   => 'RPL_QUIETLIST',
        number => 728,
        format => '%s %s %s %s %d'
                  # (channel, mode, mask, banner, ban time)
    ) and
    $mod->register_user_numeric(
        name   => 'RPL_ENDOFQUIETLIST',
        number => 729,
        format => '%s %s :End of Channel Quiet List'
                  # (channel, mode)
    ) or return;
    
    # register block.
    $ccm = $api->get_module('Core::ChannelModes') or return;
    $mod->register_channel_mode_block(
        name => 'mute',
        code => \&cmode_mute
    ) or return;

    # message blocking event - muted and no voice?
    $pool->on('user.can_message' => sub {
        my ($user, $event, $channel, $message, $type) = @_;
        
        # not moderated, or the user has proper status.
        return if $channel->user_get_highest_level($user) >= -2;
        return unless $channel->list_matches('mute', $user);
        return if $channel->list_matches('except', $user);
        
        $user->numeric(ERR_CANNOTSENDTOCHAN => $channel->name, "You're muted");
        $event->stop('muted');
        
    }, name => 'stop.muted.users', with_eo => 1, priority => 10);
    
    
    return 1;
}

sub cmode_mute {
    $ccm or return;
    $ccm->can('cmode_banlike_ext')->(
        \@_,
        list      => 'mute',    # name of the list mode
        reply     => 'quiet',   # reply numerics to send
        show_mode => 1          # show the mode letter in replies
    );
}

$mod

