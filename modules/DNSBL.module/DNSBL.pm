# Copyright (c) 2015, Matthew Barksdale
#
# Created on mattmini
# Wed May 13 17:21:41 EDT 2015
# DNSBL.pm
#
# @name:            'DNSBL'
# @package:         'M::DNSBL'
# @description:     'Adds DNSBL checking on new connections'
#
# @author.name:     'Matthew Barksdale'
# @author.website:  'https://github.com/mattwb65'
#
package M::DNSBL;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool, $conf);

sub init {
    $pool->on('connection.new', \&connection_new, 'check.dnsbl');
}

sub connection_new {
    my ($connection, $event) = @_;
    return if $connection->{goodbye};

    my @lists = $conf->names_of_block('dnsbl');
    return if scalar(@lists) == 0;
    $connection->{dnsbl_checks} = 0;
    foreach my $name (@lists) {
        my %blacklist = $conf->hash_of_block(['dnsbl', $name]);
        my $host = $blacklist{host};
        my @octets = reverse(split('\.', $$connection{ip}));
        my $lookup = sprintf('%u.%u.%u.%u.%s', @octets, $host);
        do_lookup($connection, $name, $lookup);
        $connection->{dnsbl_checks}++;
    }
}

sub do_lookup {
    my ($connection, $dnsbl, $lookup) = @_;
    $connection->{dnsbl_futures} //= {};
    my $f = $connection->{dnsbl_futures}->{$dnsbl} = $::loop->resolver->getaddrinfo(
            host => $lookup,
            socktype => Socket::SOCK_RAW,
            timeout => 3
    );
    $f->on_done(sub { got_dnsbl_reply($connection, $dnsbl, @_); });
    $f->on_fail(sub { no_reply($connection, $dnsbl); });
}

sub got_dnsbl_reply {
    my ($connection, $dnsbl, $addr) = @_;
    my $f = $connection->{dnsbl_futures}->{$dnsbl} = $::loop->resolver->getnameinfo(
            addr => $addr->{addr},
            numerichost => 1
    );
    $f->on_done(sub { got_reply($connection, $dnsbl, @_); });
    $f->on_fail(sub { no_reply($connection, $dnsbl); });
}

sub got_reply {
    my ($connection, $dnsbl, $ip) = @_;
    delete $connection->{dnsbl_futures}->{$dnsbl};
    my (undef, undef, undef, $response) = split('\.', $ip);
    my @responses = @{$conf->get(['dnsbl', $dnsbl], 'responses')};
    my $win = 0;
    foreach (@responses) {
        $win = 1 if $_ eq $response;
    }
    if (!scalar(@responses) || $win) {
        $connection->done("You are listed on the $dnsbl blacklist.");
    } else {
        dnsbl_ok($connection);
    }
}

sub no_reply {
    my ($connection, $dnsbl, $ip) = @_;
    delete $connection->{dnsbl_futures}->{$dnsbl};
    dnsbl_ok($connection);
}

sub dnsbl_ok {
    my $connection = shift;
    $connection->{dnsbl_checks}--;
    if ($connection->{dnsbl_checks} == 0) {
        delete $connection->{dnsbl_futures};
        delete $connection->{dnsbl_checks};
        $connection->reg_continue('dnsbl');
    }
}


$mod
