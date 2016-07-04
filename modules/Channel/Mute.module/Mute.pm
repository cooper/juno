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
my $banlike;

our %user_numerics = (
    RPL_QUIETLIST       => [ 728, '%s %s %s %s %d'                  ],
    RPL_ENDOFQUIETLIST  => [ 729, '%s %s :End of channel mute list' ]
);

sub init {

    # register block.
    my $ccm  = $api->get_module('Core::ChannelModes') or return;
    $banlike = $ccm->can('cmode_banlike_ext')         or return;
    $mod->register_channel_mode_block(
        name => 'mute',
        code => \&cmode_mute
    ) or return;

    # message blocking event - muted and no voice?
    $pool->on('user.can_message' => sub {
        my ($user, $event, $channel, $message, $type) = @_;

        # has voice.
        return if $channel->user_get_highest_level($user) >= -2;

        # not muted.
        return unless $channel->list_matches('mute', $user);

        # has an exception.
        return if $channel->list_matches('except', $user);

        $user->numeric(ERR_CANNOTSENDTOCHAN => $channel->name, "You're muted");
        $event->stop('muted');

    }, name => 'stop.muted.users', with_eo => 1, priority => 10);

    return 1;
}

sub cmode_mute {
    $banlike->(
        \@_,
        list      => 'mute',    # name of the list mode
        reply     => 'quiet',   # reply numerics to send
        show_mode => 1          # show the mode letter in replies
    );
}

$mod
