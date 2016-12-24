# Copyright (c) 2014, matthew
#
# Created on mattbook
# Wed Oct 15 12:16:56 EDT 2014
# Forward.pm
#
# @name:            'Channel::Forward'
# @package:         'M::Channel::Forward'
# @description:     'adds channel forwarding abilities'
#
# @depends.modules: ['Base::ChannelModes', 'Base::UserNumerics']
#
# @author.name:     'Matthew Barksdale'
# @author.website:  'https://github.com/mattwb65'
#
package M::Channel::Forward;

use warnings;
use strict;
use 5.010;

use utils qw(cut_to_limit cols);

our ($api, $mod, $pool);

our %user_numerics = (
    ERR_LINKCHAN => [ 470, '%s %s :Forwarding to another channel' ]
);

our %channel_modes = (
    forward      => { code => \&cmode_forward   },
    free_forward => { type => 'normal'          }
);

sub init {

    # Hook on the cant_join event to forward users if needed.
    $pool->on('user.cant_join' => \&on_user_cant_join, 'join.fail.forward');

    return 1;
}

sub cmode_forward {
    my ($channel, $mode) = @_;
    $mode->{has_basic_status} or return;

    # if we're unsetting...
    if (!$mode->{state}) {
        return unless $channel->is_mode('forward');
        $channel->unset_mode('forward');
    }

    # setting.
    else {

        # sanity checking
        $mode->{param} = cols(cut_to_limit('forward', $mode->{param}));

        # no length, don't set
        if (!length $mode->{param}) {
            return;
        }

        # if the channel is free forward, anybody can forward to it. However,
        # if the channel is not free forward, only people opped in the channel
        # to be forwarded to can forward.
        my $f_channel = $pool->lookup_channel($mode->{param});
        my $source = $mode->{source};

        # channel does not exist.
        if (!$f_channel) {
            $source->numeric(ERR_NOSUCHCHANNEL => $mode->{param})
                if $source->isa('user');
            return;
        }

        # forwarding to the same channel.
        return if $f_channel == $channel;

        # is the channel free forward or is the user opped?
        if (!$source->isa('user') || $f_channel->is_mode('free_forward')
            || $f_channel->user_has_basic_status($source) || $mode->{force})
        {
            $channel->set_mode('forward', $mode->{param});
        } else {
            $source->numeric(ERR_CHANOPRIVSNEEDED => $f_channel->name);
            return;
        }
    }

    return 1;
}

# attempt to do a forward maybe.
sub on_user_cant_join {
    my ($user, $event, $channel) = @_;
    return unless $channel->is_mode('forward');
    my $f_ch_name = $channel->mode_parameter('forward');

    # this was already checked once, but this is just in case it was
    # set by a pseudoserver or something and is invalid.
    if (!utils::validchan($f_ch_name)) {
        L("Invalid forward channel name for $$channel{name}: $f_ch_name");
        return;
    }

    # We need the channel object, unfortunately it is not always the case that
    # we are being forwarded to a channel that already exists.
    my ($f_chan, $new) = $pool->lookup_or_create_channel($f_ch_name);

    # Check if we're even able to join the channel to be forwarded to
    my $can_fire = $user->fire(can_join => $f_chan);
    if ($can_fire->stopper) {

        # we can't...
        # if we just created this channel, dispose of it.
        if ($new) {
            $pool->delete_channel($f_chan);
            $f_chan->delete_all_events();
        }

        return;
    }

    # Safe point - we are definitely joining the forward channel.

    # Let the user know we're forwarding...
    $user->numeric(ERR_LINKCHAN => $channel->name, $f_chan->name);

    # force the join.
    $f_chan->attempt_local_join($user, $new, undef, 1);

    # stopping cant_join cancels the original channel's error message.
    $event->stop;
}

$mod
