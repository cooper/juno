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
# @depends.modules: ['Base::ChannelModes', 'Base::UserNumerics', 'Core::UserCommands']
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
my $cjoin;

sub init {
    
    # register forward mode block.
    $mod->register_channel_mode_block(
        name => 'forward',
        code => \&cmode_forward
    ) or return;
    
    # register free forward mode block
    $mod->register_channel_mode_block(
        name => 'free_forward',
        code => \&M::Core::ChannelModes::cmode_normal
    ) or return;
    
    # register ERR_LINKCHAN
    $mod->register_user_numeric(
        name   => 'ERR_LINKCHAN',
        number => 470,
        format => '%s %s :Forwarding to another channel'
    ) or return;
    
    # Hook on the can_join and join_failed events to forward users if needed.
    $pool->on('user.can_join' => \&on_user_can_join,
        after=> 'in.channel',
        name => 'check.forward'
    );
    $pool->on('user.join_failed' => \&on_user_join_failed,
        with_eo => 1,
        name    => 'join.failed'
    );
    
    # grab cjoin from UserCommands.
    my $ucmds = $api->get_module('Core::UserCommands') or return;
       $cjoin = $ucmds->can('_cjoin')                  or return;

    return 1;
}

sub cmode_forward {
    my ($channel, $mode) = @_;
    $mode->{has_basic_status} or return;
    
    # if we're unsetting...
    if (!$mode->{setting}) {
        return unless $channel->is_mode('forward');
        
        # if we unset without a parameter (the channel to forward to),
        # we need to push the current channel to forward to to params
        push @{ $mode->{params} }, $channel->mode_parameter('forward')
          if !defined $mode->{param};
        
        $channel->unset_mode('forward');
    }
    
    # setting.
    else {
    
        # sanity checking
        $mode->{param} = cols(cut_to_limit('forward', $mode->{param}));
        
        # no length, don't set
        if (!length $mode->{param}) {
            $mode->{do_not_set} = 1;
            return;
        }
        
        # if the channel is free forward, anybody can forward to it. However,              
        # if the channel is not free forward, only people opped in the channel
        # to be forwarded to can forward.
        my $f_channel = $pool->lookup_channel($mode->{param});
        my $source = $mode->{source};
        $source->numeric(ERR_NOSUCHCHANNEL => $mode->{param}) and return
            if (!$f_channel && $source->isa('user'));
        
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

# setting silent_errors tells +i, +l to not send errors.
sub on_user_can_join {
    my ($event, $channel) = @_;
    return unless $channel->is_mode('forward');
    $event->{silent_errors} = 1;
}

# attempt to do a forward maybe.
sub on_user_join_failed {
    my ($user, $event, $channel) = @_;
    return unless $channel->is_mode('forward');
    my $f_ch_name = $channel->mode_parameter('forward');
    
    # We need the channel object, unfortunately it is not always the case that
    # we are being forwarded to a channel that already exists.
    my ($f_chan, $new) = $pool->lookup_or_create_channel($f_ch_name);
    
    # Let the user know we're forwarding...
    $user->numeric(ERR_LINKCHAN => $channel->name, $f_chan->name);
    
    # Check if we're even able to join the channel to be forwarded to
    if ($user->fire('can_join' => $f_chan)->stopper) {
        # we can't...
        # if we just created this channel, dispose of it.
        if ($new) {
            $pool->delete_channel($f_chan);
            $f_chan->delete_all_events();
        }
        return;
    }
    
    # We can join
    $cjoin->(1, $user, undef, $f_chan->name);
    
}

$mod

