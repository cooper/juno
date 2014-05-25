# Copyright (c) 2012-14, Mitchell Cooper
#
# @name:            "Ident"
# @package:         "M::Ident"
# @description:     "resolve idents"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Ident;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $me, $pool);

sub init {
    $pool->on('connection.new' => \&connection_new, with_evented_obj => 1) or return;
    return 1;
}

sub connection_new {
    my ($connection, $event) = @_;
    return if $connection->{goodbye};
    
    # postpone registration.
    $connection->sendfrom($me->full, 'NOTICE * :*** Checking ident...');
    $connection->reg_wait;
    use Socket qw(IPPROTO_TCP SOCK_STREAM AF_INET pack_sockaddr_in inet_aton);
    say $::loop->connect(
        addr => {
            family => AF_INET, #$connection->{stream}->write_handle->sockdomain,
            socktype => SOCK_STREAM, #'stream',
            #port => 143,
            protocol => IPPROTO_TCP,
            addr => pack_sockaddr_in(80, inet_aton('8.8.8.8'))#$connection->{ip}
            # for ipv6: $sockaddr = sockaddr_in6 $port, $ip6_address, [$scope_id, [$flowinfo]]
        },
        on_stream => sub {
            print "ON_STREAM: @_\n";
        },
        on_fail => sub {
            print "ON_FAIL: @_\n";
        },
        on_connect_error => sub {
            print "ON_FAIL: @_\n";
        }
    );
    
}

$mod