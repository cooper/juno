# Copyright (c) 2016, Mitchell Cooper
#
# @name:            'Channel::ModeSync::JELP'
# @package:         'M::Channel::ModeSync::JELP'
# @description:     'JELP mode synchronization'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Channel::ModeSync::JELP;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

our %jelp_incoming_commands = (
    MODEREQ => {
                  # :<SID> MODEREQ <channel>|* <target SID>|* <modes>|*
        params => '-source(server) *           *              *',
        code   => \&in_modereq
    },
    MODEREP => {
                  # :<SID> MODEREP <channel> <target SID>|* :<mode string>
        params => '-source(server) channel   *              *',
        code   => \&in_moderep
    }
);

our %jelp_outgoing_commands = (
    MODEREQ => \&out_modereq,
    MODEREP => \&out_moderep
);

my ($handle_modereq, $handle_moderep);

sub init {
    $handle_modereq = M::Channel::ModeSync->can('handle_modereq') or return;
    $handle_moderep = M::Channel::ModeSync->can('handle_moderep') or return;
    return 1;
}

sub in_modereq {
    my ($server, $msg, $source_serv, $ch_name, $target, $modes) = @_;
    undef $ch_name if $ch_name eq '*';
    undef $target  if $target  eq '*';
    undef $modes   if $modes   eq '*';

    # find a target server maybe.
    $target = $pool->lookup_server($target) or return
        if defined $target;

    # find a channel maybe.
    # abort if a name was provided and we can't find it.
    my $ch_maybe = $pool->lookup_channel($ch_name) or return
        if defined $ch_name;

    return $handle_modereq->($msg, $source_serv, $ch_maybe, $target, $modes);
}

# :69 MODEREP #k 100 :+n
sub in_moderep {
    my ($server, $msg, $source_serv, $channel, $target, $mode_str) = @_;
    undef $target if $target eq '*';

    # find a target server maybe.
    $target = $pool->lookup_server($target) or return
        if defined $target;

    return $handle_moderep->($msg, $source_serv, $channel, $target, $mode_str);
}

sub out_modereq {
    my ($to_server, $source_serv, $ch_maybe, $serv_maybe, $modes_maybe) = @_;
    sprintf ':%s MODEREQ %s %s %s',
    $source_serv->id,
    $ch_maybe   ? $ch_maybe->name      : '*',
    $serv_maybe ?  $serv_maybe->id     : '*',
    length $modes_maybe ? $modes_maybe : '*';
}

sub out_moderep {
    my ($to_server, $source_serv, $channel, $serv_maybe, $mode_str) = @_;
    sprintf ':%s MODEREP %s %s :%s',
    $source_serv->id,
    $channel->name,
    $serv_maybe ? $serv_maybe->id : '*',
    $mode_str;
}

$mod
