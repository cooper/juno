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

use Socket qw(AF_INET AF_INET6 SOCK_STREAM inet_pton);
use List::Util qw(first);
use utils qw(looks_like_ipv6 string_to_seconds ref_to_list);

our ($api, $mod, $pool, $conf, %cache);

sub init {
    $pool->on('connection.new', \&connection_new, 'check.dnsbl');
}

# on new connection, check each applicable DNSBL
sub connection_new {
    my ($conn, $event) = @_;
    return if $conn->{goodbye};
    my @lists = $conf->names_of_block('dnsbl') or return;

    my ($expanded, $ipv6);
    my $ip = $conn->ip;

    # check if the IP has already been cached
    if (my $cached = $cache{$ip}) {
        my ($expire_time, $list_name, $reason) = @$cached;
        return dnsbl_bad($conn, $list_name, $reason)
            if time < $expire_time;
        delete $cache{$ip};
    }

    # IPv6
    if ($ipv6 = looks_like_ipv6($ip)) {
        my $addr  = inet_pton(AF_INET6, $ip);
        $expanded = join '.', reverse map { split // } unpack('H4' x 8, $addr);
    }

    # IPv4
    else {
        my $addr = inet_pton(AF_INET, $ip);
        $expanded = join '.', reverse unpack('C' x 4, $addr);
    }

    check_conn_against_list($conn, $expanded, $ipv6, $_) for @lists;
}

sub check_conn_against_list {
    my ($conn, $expanded, $ipv6, $list_name) = @_;
    my %blacklist = $conf->hash_of_block([ 'dnsbl', $list_name ]);
    my $full_host = "$expanded.$blacklist{host}";

    # stop here if the DNSBL does not support the address family
    my $n = $ipv6 ? 6 : 4;
    return if !$blacklist{"ipv$n"};

    # postpone registration until this is done
    $conn->reg_wait("dnsbl_$list_name");

    # do the initial request
    my $f = $::loop->resolver->getaddrinfo(
        host     => $full_host,
        service  => '',
        socktype => SOCK_STREAM,
        timeout  => $blacklist{timeout} || 3
    );

    $conn->adopt_future("dnsbl1_$list_name" => $f);
    $f->on_done(sub { got_reply1($conn, $list_name, @_) });
    $f->on_fail(sub { dnsbl_ok($conn, $list_name)       });
}

# got first reply
sub got_reply1 {
    my ($conn, $list_name, $addr) = @_;

    # do the second request
    my $f = $::loop->resolver->getnameinfo(
        addr => $addr->{addr},
        numerichost => 1
    );

    $conn->adopt_future("dnsbl2_$list_name" => $f);
    $f->on_done(sub { got_reply2($conn, $list_name, @_) });
    $f->on_fail(sub { dnsbl_ok($conn, $list_name)       });
}

# got second reply
sub got_reply2 {
    my ($conn, $list_name, $ip) = @_;
    my %blacklist = $conf->hash_of_block([ 'dnsbl', $list_name ]);

    # extract the last portion of the IP address
    my $response = (unpack('C' x 4, $ip))[-1];
    my @matches  = ref_to_list($blacklist{matches});

    # if no responses are specified, any response works.
    # otherwise, see if any of the provided responses are the one we got.
    if (!@matches || first { $_ == $response } @matches) {
        return dnsbl_bad(
            $conn, $list_name,
            $blacklist{reason}, $blacklist{duration}
        );
    }

    dnsbl_ok($conn);
}

# called when the connection is good-to-go.
sub dnsbl_ok {
    my ($conn, $list_name) = @_;
    D("$$conn{ip} is not listed on $list_name");
    finish($conn, $list_name);
}

# called when the connection is blacklisted.
sub dnsbl_bad {
    my ($conn, $list_name, $reason, $duration) = @_;
    L("$$conn{ip} is listed on $list_name!");

    # inject variables in reason
    $reason ||= "Your host is listed on $list_name.";
    $reason =~ s/%ip/$$conn{ip}/g;
    $reason =~ s/%host/$$conn{host}/g;

    # store in cache
    if ($duration) {
        my $expire_time = time() + string_to_seconds($duration);
        $cache{ $conn->ip } = [ $expire_time, $list_name, $reason ];
    }

    # drop the connection
    $conn->done($reason);

    finish($conn, $list_name);
}

# called when a DNSBL lookup is complete, regardless of status.
sub finish {
    my ($conn, $list_name) = @_;
    $conn->abandon_future("dnsbl1_$list_name");
    $conn->abandon_future("dnsbl2_$list_name");
    $conn->reg_continue("dnsbl_$list_name");
}

$mod
