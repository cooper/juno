# Copyright (c) 2014, matthew
#
# Created on mattbook
# Wed Jul 2 01:25:56 EDT 2014
# Key.pm
#
# @name:            'Channel::Key'
# @package:         'M::Channel::Key'
# @description:     'adds channel key mode'
#
# @depends.modules: ['Base::ChannelModes', 'Base::UserNumerics']
#
# @author.name:     'Matthew Barksdale'
# @author.website:  'https://github.com/mattwb65'
#
package M::Channel::Key;

use warnings;
use strict;
use 5.010;

use utils qw(cut_to_limit);

our ($api, $mod, $pool);

sub init {
    # register limit mode block.
    $mod->register_channel_mode_block(
        name => 'key',
        code => \&cmode_key
    ) or return;
    # register ERR_BADCHANNELKEY
    $mod->register_user_numeric(
        name   => shift @$_,
        number => shift @$_,
        format => shift @$_
    ) or return foreach (
        [ ERR_BADCHANNELKEY => 481, '%s :Invalid channel key' ],
        [ ERR_KEYSET        => 467, '%s :Channel key already set' ]
    );
    # Hook on the can_join event to prevent joining a channel without valid key
    $pool->on('user.can_join' => \&on_user_can_join, with_eo => 1, name => 'has.key');
    return 1;
}

sub cmode_key {
    my ($channel, $mode) = @_;
    $mode->{has_basic_status} or return;
    # if we're unsetting...
    if (!$mode->{setting} && $channel->is_mode('key')) {
        # if we unset without a parameter (the key), we need to push the current key to params
        push @{ $mode->{params} }, $channel->mode_parameter('key') if !defined $mode->{param};
        $channel->unset_mode('key');
    } else {
        # sanity checking
        $mode->{param} = cut_to_limit('key', $mode->{param});
        $channel->set_mode('key', $mode->{param});
    }
    return 1;
}

sub on_user_can_join {
    my ($user, $event, $channel, $key) = @_;
    return unless $channel->is_mode('key');
    return unless $channel->mode_parameter('key') ne $key;
    $user->numeric(ERR_BADCHANNELKEY => $channel->name);
    $event->stop;
}



$mod

