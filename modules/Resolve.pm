# Copyright (c) 2014, Mitchell Cooper
# resolve hostnames.
package API::Module::Resolve;

use warnings;
use strict;

use utils qw(conf v match);

our $mod = API::Module->new(
    name        => 'Resolve',
    version     => '0.1',
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

    # only accept exactly one record.
    # TODO: this needs to be specific to the IP version.
    if (scalar @addrs != 1) {
        on_error($connection);
        return;
    }

    # see if the result matches the original IP
    my $addr = (Socket::GetAddrInfo::getnameinfo($addrs[0]->{addr}))[1];

    if ($addr eq $connection->{temp_host}) {
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
    $connection->send(q(:).v('SERVER', 'name').' NOTICE * :*** Couldn\'t resolve your hostname');
    delete $connection->{temp_host};
    $connection->reg_continue;
}

$mod
