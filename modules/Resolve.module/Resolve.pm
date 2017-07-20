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
use Socket qw(SOCK_STREAM);

our ($api, $mod, $me, $pool);

sub init {

    # hook onto new connections to resolve host
    $pool->on('connection.new' => \&connection_new, 'resolve.hostname');

    return 1;
}

# on new connection, attempt to resolve
sub connection_new {
    my ($conn, $event) = @_;
    $conn->early_reply(NOTICE => ':*** Looking up your hostname...');
    resolve_address($conn);
}

# Step 1: getnameinfo()
sub resolve_address {
    my $conn = shift;
    return if $conn->{goodbye};

    # prevent connection registration from completing.
    $conn->reg_wait('resolve');

    # peername -> human-readable hostname
    my $resolve_future = $::loop->resolver->getnameinfo(
        addr => $conn->sock->peername
    );

    my $timeout_future = $::loop->timeout_future(after => 3);
    my $f = Future->wait_any($resolve_future, $timeout_future);

    $f->on_done(sub { on_got_host1($conn, @_   ) });
    $f->on_fail(sub { on_error    ($conn, shift) });
    $conn->adopt_future(resolve_host1 => $f);
}

# Step 2: getaddrinfo()
# got human-readable hostname
sub on_got_host1 {
    my ($conn, $host) = @_;
    $host = safe_ip($host);

    # temporarily store the host.
    $conn->{resolve_host} = $host;

    # getnameinfo() spit out the IP.
    # we need better IP comparison probably.
    if ($conn->{ip} eq $host) {
        return on_error($conn, 'getnameinfo() spit out IP');
    }

    # human readable hostname -> binary address
    my $resolve_future = $::loop->resolver->getaddrinfo(
        host        => $host,
        service     => '',
        socktype    => SOCK_STREAM,
        timeout     => 3
    );

    my $timeout_future = $::loop->timeout_future(after => 3);
    my $f = Future->wait_any($resolve_future, $timeout_future);

    $f->on_done(sub { on_got_addr($conn, @_   ) });
    $f->on_fail(sub { on_error   ($conn, shift) });
    $conn->adopt_future(resolve_addr => $f);
}

# Step 3: getnameinfo()
# got binary representation of address
sub on_got_addr {
    my ($conn, $addr) = @_;

    # binary address -> human-readable hostname
    my $resolve_future = $::loop->resolver->getnameinfo(
        addr        => $addr->{addr},
        socktype    => SOCK_STREAM
    );

    my $timeout_future = $::loop->timeout_future(after => 3);
    my $f = Future->wait_any($resolve_future, $timeout_future);

    $f->on_done(sub { on_got_host2($conn, @_   ) });
    $f->on_fail(sub { on_error    ($conn, shift) });
    $conn->adopt_future(resolve_host2 => $f);
}

# Step 4: Set the host
# got human-readable hostname
sub on_got_host2 {
    my ($conn, $host) = @_;

    # they match.
    if ($conn->{resolve_host} eq $host) {
        $conn->early_reply(NOTICE => ':*** Found your hostname');
        $conn->{host} = safe_ip(delete $conn->{resolve_host});
        $conn->fire('found_hostname');
        _finish($conn);
        return 1;
    }

    # not the same.
    return on_error($conn, "No match ($host)");

}

# called on error
sub on_error {
    my ($conn, $err) = (shift, shift // 'unknown error');
    $conn->early_reply(NOTICE => ":*** Couldn't resolve your hostname");
    D("Lookup for $$conn{ip} failed: $err");
    _finish($conn);
    return;
}

# call with either success or failure
sub _finish {
    my $conn = shift;
    return if $conn->{goodbye};

    # delete futures that might be left
    $conn->abandon_future($_)
        for qw(resolve_host1 resolve_host2 resolve_addr);

    delete $conn->{resolve_host};
    $conn->reg_continue('resolve');
}

$mod
