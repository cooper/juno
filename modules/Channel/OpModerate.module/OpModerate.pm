# Copyright (c) 2016, Mitchell Cooper
#
# @name:            'Channel::OpModerate'
# @package:         'M::Channel::OpModerate'
# @description:     'adds a channel mode to send blocked messages to ops'
#
# @depends.modules: ['Base::ChannelModes']
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Channel::OpModerate;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

our %channel_modes = (
    op_moderated => { type => 'normal' }
);

sub init {

    # catch blocked messages
    $pool->on('user.cant_message' => \&message_blocked,
        name    => 'op.moderate',
        with_eo => 1
    );

    return 1;
}

sub message_blocked {
    my ($user, $event, $channel, $message, $lccommand, $can_fire) = @_;

    # we only care if the user is local and the channel is +z
    return unless $channel->is_mode('op_moderated');
    return unless $user->is_local;

    $channel->do_privmsgnotice(
        $lccommand,                 # command
        $user,                      # source
        $message,                   # text
        force => 1,                 # force it! we know it got blocked once
        op_moderated => 1           # send to ops only
    );

    # stopping the event tells can_message callbacks NOT to send error
    # numerics to the user.
    $event->stop;
}

$mod
