# Copyright (c) 2014, Mitchell Cooper
# channel fantasy commands.
package API::Module::Fantasy;

use warnings;
use strict;

our $mod = API::Module->new(
    name        => 'Fantasy',
    version     => '0.2',
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
    my ($cmd, $args) = (lc $1, $2);
    
    # ignore stupid commands.
    return if $cmd eq 'privmsg';
    return if $cmd eq 'notice';
    
    # ex: !privmsg !privmsg
    my @a = split /\s/, $message;
    for (my $i = 1; $i <= $#a; $i++) {
        return if lc $a[0] eq lc $a[$i];
    }
    
    my @handlers = $main::pool->user_handlers($cmd) or return;
    
    my $line = length $args ? "$cmd $$channel{name} $args" : "$cmd $$channel{name}";
    my @s    = split /\s/, $line;
    foreach my $handler (@handlers) {
        $handler->{code}($source, $line, @s) if $#s >= $handler->{params};
    }

    return 1;
}

$mod
