# Copyright (c) 2016, Mitchell Cooper
#
# @name:            'Channel::ModeSync::Desync'
# @package:         'M::Channel::ModeSync::Desync'
# @description:     'provides the MODESYNC user command to fix desyncs'
#
# @depends.bases+   'UserCommands', 'OperNotices'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Channel::ModeSync::Desync;

use warnings;
use strict;
use 5.010;

use utils qw(gnotice broadcast);

our ($api, $mod, $pool, $me);

our %user_commands = (MODESYNC => {
    code   => \&modesync,
    desc   => 'fix channel mode desyncs',
    params => '-oper(modesync) channel'
});

our %oper_notices = (
    modesync => '%s issued MODESYNC for %s'
);

sub modesync {
    my ($user, $event, $channel) = @_;
    gnotice($user, modesync => $user->notice_info, $channel->name);

    # send a MODEREQ to *
    # ($source_serv, $ch_maybe, $serv_maybe, $modes_maybe)
    broadcast(modereq => $me, $channel, undef, undef);

    # send a MODEREP with my own modes to *
    # ($source_serv, $channel, $serv_maybe, $mode_string)
    my (undef, $mode_str) = $channel->mode_string_all($me);
    broadcast(moderep =>
        $me, $channel,
        undef, # reply to *
        $mode_str
    );
}

$mod
