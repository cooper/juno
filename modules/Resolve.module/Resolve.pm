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

# peername -> human-readable hostname
sub resolve_address {
    my $connection = shift;
    return if $connection->{goodbye};
    
    # prevent connection registration from completing.
    $connection->reg_wait('resolve');
    
    # async lookup.
    $connection->{resolve_future} = $::loop->resolver->getnameinfo(
        addr        => $connection->sock->peername,
        on_resolved => sub { on_got_host1($connection, @_   ) },
        on_error    => sub { on_error    ($connection, shift) },
        timeout     => 3
    );
    
}

# got human-readable hostname
sub on_got_host1 {
    my ($connection, $host) = @_;
    $host = safe_ip($host);
    
    # temporarily store the host.
    $connection->{temp_host} = $host;

    # getnameinfo() spit out the IP.
    # we need better IP comparison probably.
    if ($connection->{ip} eq $host) {
        return on_error($connection, 'getnameinfo() spit out IP');
    }
    
    # human readable hostname -> binary address
    $connection->{resolve_future} = $::loop->resolver->getaddrinfo(
        host        => $host,
        service     => '',
        socktype    => Socket::SOCK_STREAM(),
        on_resolved => sub { on_got_addr($connection, @_   ) },
        on_error    => sub { on_error   ($connection, shift) },
        timeout     => 3
    );
    
}

# got binary representation of address
sub on_got_addr {
    my ($connection, $addr) = @_;
    
    # binary address -> human-readable hostname
    $connection->{resolve_future} = $::loop->resolver->getnameinfo(
        addr        => $addr->{addr},
        socktype    => Socket::SOCK_STREAM(),
        on_resolved => sub { on_got_host2($connection, @_   ) },
        on_error    => sub { on_error    ($connection, shift) },
        timeout     => 3
    );
}

# got human-readable hostname
sub on_got_host2 {
    my ($connection, $host) = @_;
    
    # they match.
    if ($connection->{temp_host} eq $host) {
        $connection->early_reply(NOTICE => ':*** Found your hostname');
        $connection->{host} = safe_ip(delete $connection->{temp_host});
        $connection->reg_continue('resolve');
        return 1;
    }
    
    # not the same.
    return on_error($connection, "No match ($host)");
    
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
