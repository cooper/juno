# Copyright (c) 2016, Mitchell Cooper
#
# @name:            'Channel::ModeSync::Desync'
# @package:         'M::Channel::ModeSync::Desync'
# @description:     'provides the MODESYNC user command to fix desyncs'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Channel::ModeSync::Desync;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool, $me);

our %user_commands = (MODESYNC => {
    code   => \&modesync,
    desc   => 'fix channel mode desyncs',
    params => '-oper(modesync) channel'
});

sub modesync {
    my ($user, $event, $channel) = @_;
    # ($source_serv, $ch_maybe, $serv_maybe, $modes_maybe)
    $pool->fire_command_all(modereq => $me, $channel, undef, undef);
}

$mod
