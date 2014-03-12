# Copyright (c) 2014, Mitchell Cooper
# channel fantasy commands.
package API::Module::Fantasy;

use warnings;
use strict;

our $mod = API::Module->new(
    name        => 'Fantasy',
    version     => '0.41',
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
    
    # prevents e.g. !privmsg !privmsg or !lolcat !kick
    my $second_p = (split /\s+/, $message)[1];
    return if substr($second_p, 0, 1) eq '!';
    
    my @handlers = $main::pool->user_handlers($cmd) or return;
    
    my $line = length $args ? "$cmd $$channel{name} $args" : "$cmd $$channel{name}";
    my @s    = split /\s+/, $line;
    foreach my $handler (@handlers) {
        next unless $handler->{fantasy};
        next unless $#s >= $handler->{params};
        $handler->{code}($source, $line, @s);
    }

    return 1;
}

$mod
