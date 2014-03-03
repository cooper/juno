# Copyright (c) 2014, Mitchell Cooper
# resolve hostnames.
package API::Module::Resolve;

use warnings;
use strict;

use utils qw(conf v match);

our $mod = API::Module->new(
    name        => 'Resolve',
    version     => '0.3',
    description => 'resolve hostnames',
    requires    => ['Events'],
    initialize  => \&init
);

sub init {
    $mod->register_ircd_event('connection.new' => \&connection_new) or return;
    return 1;
}

sub connection_new {
    my ($connection, $event) = @_;
    $connection->send(q(:).v('SERVER', 'name').' NOTICE * :*** Looking up your hostname...');
    resolve_address($connection);
}

sub resolve_address {
    my $connection = shift;
    return if $connection->{goodbye};
    
    # prevent connection registration from completing.
    $connection->reg_wait;

    # asynchronously resolve.
    $main::loop->resolver->getnameinfo(
        addr        => $connection->sock->peername,
        on_resolved => sub { on_resolved_ip($connection, @_) },
        on_error    => sub { on_error($connection) }
    );
    
}

sub on_resolved_ip {
    my ($connection, $host) = @_;
    return if $connection->{goodbye};

    # temporarily store the host
    $connection->{temp_host} = $host;

    # resolve the host back to an IP address
    $main::loop->resolver->getaddrinfo(
        host        => $host,
        service     => '',
        socktype    => Socket::SOCK_STREAM(),
        on_resolved => sub { on_resolved_host($connection, @_) },
        on_error    => sub { on_error($connection) }
    );

}

sub on_resolved_host {
    my ($connection, @addrs) = @_;
    return if $connection->{goodbye};

    # see if any result matches.
    foreach my $a (@addrs) {
        my $addr = (Socket::GetAddrInfo::getnameinfo($a->{addr}))[1] or next;
        next unless $addr eq $connection->{temp_host};
        
        $connection->send(q(:).v('SERVER', 'name').' NOTICE * :*** Found your hostname');
        $connection->{host} = delete $connection->{temp_host};
        $connection->reg_continue;
        return 1;
    }

    # no match
    on_error($connection);
    
    return;
}

sub on_error {
    my $connection = shift;
    return if $connection->{goodbye};

    $connection->send(q(:).v('SERVER', 'name').' NOTICE * :*** Couldn\'t resolve your hostname');
    delete $connection->{temp_host};
    $connection->reg_continue;
}

$mod
