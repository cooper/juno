# Copyright (c) 2016, Mitchell Cooper
#
# @name:            'Channel::Permanent'
# @package:         'M::Channel::Permanent'
# @description:     'adds permanent channel support'
#
# @depends.modules: ['Base::ChannelModes']
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Channel::Permanent;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

our %channel_modes = (
    permanent => { code => \&cmode_permanent }
);

sub init {
    $pool->on('channel.can_destroy' => \&on_can_destroy,
        with_eo => 1,
        name    => 'channel.permanent'
    );
}

# prevent non-opers from (un)setting the mode
sub cmode_permanent {
    my ($channel, $mode) = @_;
    $mode->{has_basic_status} or return;

    # if not force, user must have set_permanent
    my $user = $mode->{source};
    undef $user if !$user || !$user->isa('user');
    if (!$mode->{force} && $user && !$user->has_flag('set_permanent')) {
        return;
    }

    return 1;
}

# stop channel destruction if permanent
sub on_can_destroy {
    my ($channel, $event) = @_;
    $event->stop('permanent') if $channel->is_mode('permanent');
}

$mod
