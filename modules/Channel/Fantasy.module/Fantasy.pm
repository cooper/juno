# Copyright (c) 2012-14, Mitchell Cooper
#
# @name:            "Channel::Fantasy"
# @package:         "M::Channel::Fantasy"
# @description:     "channel fantasy commands"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Channel::Fantasy;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

sub init {
    $pool->on('channel.privmsg' => \&channel_privmsg, with_eo => 1);
    return 1;
}

sub channel_privmsg {
    my ($channel, $event, $source, $message) = @_;
    return unless $source->isa('user') && $source->is_local;
    return unless $message =~ m/^!(\w+)\s*(.*)$/;
    my ($cmd, $args) = (lc $1, $2);
    
    # prevents e.g. !privmsg !privmsg or !lolcat !kick
    my $second_p = (split /\s+/, $message, 2)[1];
    return if defined $second_p && substr($second_p, 0, 1) eq '!';
    
    my @handlers = $pool->user_handlers($cmd) or return;
    
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