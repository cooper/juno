# Copyright (c) 2014, Mitchell Cooper
# channel fantasy commands.
package API::Module::Fantasy;

use warnings;
use strict;

use utils qw(conf v match);

our $mod = API::Module->new(
    name        => 'Fantasy',
    version     => '0.1',
    description => 'channel fantasy commands',
    requires    => ['Events'],
    initialize  => \&init
);

sub init {
    $mod->register_ircd_event('channel.privmsg' => \&channel_privmsg) or return;
    return 1;
}

sub channel_privmsg {
    my ($channel, $event, $source, $message) = @_;
    return unless $source->isa('user') && $source->is_local;
    return unless $message =~ m/^!(\w+)\s*(.*)$/;
    my ($cmd, $args) = ($1, $2);
    $cmd = "$cmd $$channel{name}";
    $source->handle(length $args ? "$cmd $args" : $cmd);
}

$mod
