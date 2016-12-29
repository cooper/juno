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
    free_forward => { type => 'normal'          },
    no_forward   => { type => 'normal'          }
);

sub init {

    # Hook on the cant_join event to forward users if needed.
    $pool->on('user.cant_join' => \&on_user_cant_join, 'join.fail.forward');

    return 1;
}

sub cmode_forward {
    my ($channel, $mode) = @_;
    $mode->{has_basic_status} or return;

    # setting.
    if ($mode->{state}) {

        # sanity checking
        my $f_ch_name = $mode->{param} =
            cols(cut_to_limit('forward', $mode->{param}));
        return if !length $f_ch_name;

        # first thing's first. make sure the channel name is valid.
        if (!utils::validchan($f_ch_name)) {
            L("Invalid forward channel name for $$channel{name}: $f_ch_name");
            return;
        }

        # when the source is a user, we have to check that the channel exists
        # and that the user is permitted to set it as a forward target.
        my $source = $mode->{source};
        if ($source->isa('user')) {
            my $f_chan = $pool->lookup_channel($f_ch_name);

            # channel does not exist.
            if (!$f_chan) {
                $source->numeric(ERR_NOSUCHCHANNEL => $mode->{param});
                return;
            }

            # forwarding to the same channel.
            return if $f_chan == $channel;

            # make sure that, unless the channel is marked as free forward,
            # the user has the necessary status.
            my $permission_ok =
                $mode->{force} || $f_chan->user_has_basic_status($source);
            if (!$f_chan->is_mode('free_forward') && !$permission_ok) {
                $source->numeric(ERR_CHANOPRIVSNEEDED => $f_chan->name);
                return;
            }
        }

        $channel->set_mode('forward', $mode->{param});
    }

    # unsetting.
    else {
        return unless $channel->is_mode('forward');
        $channel->unset_mode('forward');
    }

    return 1;
}

# attempt to do a forward maybe.
sub on_user_cant_join {
    my ($user, $event, $channel) = @_;
    return unless $channel->is_mode('forward');
    my $f_ch_name = $channel->mode_parameter('forward');

    # We need the channel object, unfortunately it is not always the case that
    # we are being forwarded to a channel that already exists.
    my ($f_chan, $new) = $pool->lookup_or_create_channel($f_ch_name);

    # Check if the forward channel is the same as the original
    return if $f_chan == $channel;

    # Check if the forward channel is marked as no forward
    if ($f_chan->is_mode('no_forward')) {
        # if we just created this channel, dispose of it.
        $channel->destroy_maybe;
        return;
    }

    # Check if we're even able to join the channel to be forwarded to
    my $can_fire = $user->fire(can_join => $f_chan);
    if ($can_fire->stopper) {
        # if we just created this channel, dispose of it.
        $channel->destroy_maybe;
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
