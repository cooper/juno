# Copyright (c) 2017, Mitchell Cooper
#
# @name:            "Channel::LargeList"
# @package:         "M::Channel::LargeList"
# @description:     "increase the number of bans permitted in a channel"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Channel::LargeList;

use warnings;
use strict;
use 5.010;

use utils qw(conf);

our ($api, $mod, $me, $pool);

# channel mode block
our %channel_modes = (
    large_banlist => { code => \&cmode_large_banlist }
);

sub init {
    $pool->on('channel.max_list_entries' =>
        \&channel_max_list_entries, 'large.ban.list');
    return 1;
}

sub channel_max_list_entries {
    my ($channel, $event) = @_;
    return unless $channel->is_mode('large_banlist');
    $event->{max} = conf('channels', 'max_bans_large');
}

sub cmode_large_banlist {
    my ($channel, $mode) = @_;
    
    # user must be a channel op
    $mode->{has_basic_status} or return;
    
    # always OK for non-users and if force enabled
    return 1 if $mode->{force} || !$mode->{source}->isa('user');
    
    # user must be an IRC cop with set_large_banlist
    return $mode->{source}->has_flag('set_large_banlist');
}

$mod
