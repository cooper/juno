# Copyright (c) 2014 Mitchell Cooper
#
# @name:            "Resolve"
# @package:         "M::Resolve"
# @description:     "resolve hostnames"
# 
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Resolve;

use warnings;
use strict;

use utils 'safe_ip';

our ($api, $mod, $me, $pool);

sub init {
    $pool->on('connection.new' => \&connection_new, with_eo => 1) or return;
    return 1;
}

sub connection_new {
    my ($connection, $event) = @_;
    $connection->early_reply(NOTICE => ':*** Looking up your hostname...');
    resolve_address($connection);
}

# IP -> hostname
sub resolve_address {
    my $connection = shift;
    return if $connection->{goodbye};
    
    # prevent connection registration from completing.
    $connection->reg_wait('resolve');
    
    # async lookup.
    $connection->{resolve_future} = $::loop->resolver->getnameinfo(
        addr        => $connection->sock->peername,
        on_resolved => sub { on_got_hosts($connection, @_   ) },
        on_error    => sub { on_error    ($connection, shift) },
        timeout     => 3
    );
    
}

sub on_got_hosts {
    my ($connection, $host) = @_;
    
    # temporarily store the host.
    $connection->{temp_host} = $host;

    # getnameinfo() spit out the IP.
    # we need better IP comparison probably.
    if ($connection->{ip} eq safe_ip($host)) {
        return on_error($connection, 'getnameinfo() spit out IP');
    }
    
    # try to resolve the host back to the IP.
    $connection->{resolve_future} = $::loop->resolver->getaddrinfo(
        host        => $host,
        service     => '',
        socktype    => Socket::SOCK_STREAM(),
        on_resolved => sub { on_got_addr($connection, @_   ) },
        on_error    => sub { on_error   ($connection, shift) },
        timeout     => 3
    );
    
}

sub on_got_addr {
    my ($connection, $addr) = @_;

    # got the addr, now resolve it to human-readable form.
    $connection->{resolve_future} = $::loop->resolver->getnameinfo(
        addr        => $addr->{addr},
        socktype    => Socket::SOCK_STREAM(),
        on_resolved => sub { on_got_ip($connection, @_   ) },
        on_error    => sub { on_error ($connection, shift) },
        timeout     => 3
    );
    
}

sub on_got_ip {
    my ($connection, $ip) = @_;
    
    # we need better IP comparison.
    if ($connection->{ip} eq safe_ip($ip)) {
        $connection->early_reply(NOTICE => ':*** Found your hostname');
        $connection->{host} = safe_ip(delete $connection->{temp_host});
        $connection->reg_continue('resolve');
        return 1;
    }
    
    # not the same!
    return on_error($connection, 'no match');
    
}

sub on_error {
    my ($connection, $err) = (shift, shift // 'unknown error');
    delete $connection->{resolve_future};
    return if $connection->{goodbye};
    $connection->early_reply(NOTICE => ":*** Couldn't resolve your hostname");
    L("Lookup for $$connection{ip} failed: $err");
    delete $connection->{temp_host};
    $connection->reg_continue('resolve');
    return;
}

$mod
