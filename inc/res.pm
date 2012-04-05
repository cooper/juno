#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
package res;

use warnings;
use strict;

use utils qw/log2 gv/;

sub resolve_address {
    my $conn = shift;

    $main::loop->resolver->getnameinfo(
        addr        => $conn->{stream}->{write_handle}->peername,
        on_resolved => sub { on_resolved_ip($conn, @_) },
        on_error    => sub { on_error($conn) }
    );
}

sub on_resolved_ip {
    my ($conn, $host) = @_;

    # temporarily store the host
    $conn->{temp_host} = $host;

    # resolve the host back to an IP address
    $main::loop->resolver->getaddrinfo(
        host        => $host,
        service     => '',
        socktype    => Socket::SOCK_STREAM(),
        on_resolved => sub { on_resolved_host($conn, @_) },
        on_error    => sub { on_error($conn) }
    );

}

sub on_resolved_host {
    my ($conn, @addrs) = @_;

    # only accept exactly one record
    if (scalar @addrs != 1) {
        on_error($conn);
        return
    }

    # see if the result matches the original IP
    my $addr = (Socket::GetAddrInfo::getnameinfo($addrs[0]->{addr}))[1];

    if ($addr eq $conn->{temp_host}) {
        $conn->{host} = delete $conn->{temp_host};
        $conn->ready if $conn->somewhat_ready;
        return 1
    }

    # no match
    on_error($conn);
    return
}

sub on_error {
    my $conn = shift;
    $conn->{host} = $conn->{ip}; # give up
    delete $conn->{temp_host};
    $conn->ready if $conn->somewhat_ready
}

1
