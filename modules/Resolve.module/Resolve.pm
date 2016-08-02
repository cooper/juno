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
    my ($connection, $event) = @_;
    $connection->early_reply(NOTICE => ':*** Looking up your hostname...');
    resolve_address($connection);
}

# Step 1: getnameinfo()
sub resolve_address {
    my $connection = shift;
    return if $connection->{goodbye};

    # prevent connection registration from completing.
    $connection->reg_wait('resolve');

    # peername -> human-readable hostname
    my $f = $::loop->resolver->getnameinfo(
        addr    => $connection->sock->peername,
        timeout => 3
    );

    $f->on_done(sub { on_got_host1($connection, @_   ) });
    $f->on_fail(sub { on_error    ($connection, shift) });
    $connection->adopt_future(resolve_host1 => $f);
}

# Step 2: getaddrinfo()
# got human-readable hostname
sub on_got_host1 {
    my ($connection, $host) = @_;
    $host = safe_ip($host);

    # temporarily store the host.
    $connection->{resolve_host} = $host;

    # getnameinfo() spit out the IP.
    # we need better IP comparison probably.
    if ($connection->{ip} eq $host) {
        return on_error($connection, 'getnameinfo() spit out IP');
    }

    # human readable hostname -> binary address
    my $f = $::loop->resolver->getaddrinfo(
        host        => $host,
        service     => '',
        socktype    => SOCK_STREAM,
        timeout     => 3
    );

    $f->on_done(sub { on_got_addr($connection, @_   ) });
    $f->on_fail(sub { on_error   ($connection, shift) });
    $connection->adopt_future(resolve_addr => $f);
}

# Step 3: getnameinfo()
# got binary representation of address
sub on_got_addr {
    my ($connection, $addr) = @_;

    # binary address -> human-readable hostname
    my $f = $connection->{resolve_future} = $::loop->resolver->getnameinfo(
        addr        => $addr->{addr},
        socktype    => SOCK_STREAM,
        timeout     => 3
    );

    $f->on_done(sub { on_got_host2($connection, @_   ) });
    $f->on_fail(sub { on_error    ($connection, shift) });
    $connection->adopt_future(resolve_host2 => $f);
}

# Step 4: Set the host
# got human-readable hostname
sub on_got_host2 {
    my ($connection, $host) = @_;

    # they match.
    if ($connection->{resolve_host} eq $host) {
        $connection->early_reply(NOTICE => ':*** Found your hostname');
        $connection->{host} = safe_ip(delete $connection->{resolve_host});
        $connection->fire('found_hostname');
        _finish($connection);
        return 1;
    }

    # not the same.
    return on_error($connection, "No match ($host)");

}

# called on error
sub on_error {
    my ($connection, $err) = (shift, shift // 'unknown error');
    $connection->early_reply(NOTICE => ":*** Couldn't resolve your hostname");
    L("Lookup for $$connection{ip} failed: $err");
    _finish($connection);
    return;
}

# call with either success or failure
sub _finish {
    my $connection = shift;
    return if $connection->{goodbye};

    # delete futures that might be left
    $connection->abandon_future($_)
        for qw(resolve_host1 resolve_host2 resolve_addr);

    delete $connection->{resolve_host};
    $connection->reg_continue('resolve');
}

$mod
