# Copyright (c) 2016, Mitchell Cooper
#
# Based on ip_cloaking_4.0.c from charybdis:
# Written originally by nenolod, altered to use FNV by Elizabeth in 2008
#
# @name:            'Cloak::Charybdis'
# @package:         'M::Cloak::Charybdis'
# @description:     'hostname cloaking compatible with charybdis'
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Cloak::Charybdis;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool, $me);

my @ip_char_table = 'g'..'z';
my @b26_alphabet  = 'a'..'z';

sub cloak {
    my ($host, $user) = @_;
    return do_host_cloak_ip($host) if $host eq $user->{ip};
    return do_host_cloak_host($host);
}

sub fnv {
    my ($string) = @_;
    my $h = 0x811c9dc5;
    foreach my $c (split //, $string) {
        $h ^= ord($c);
        $h += ($h << 1) + ($h << 4) + ($h << 7) + ($h << 8) + ($h << 24);
        $h &= 0xffffffff;
    }
    return $h;
}

sub do_host_cloak_ip {
    my $in = shift;
    my $accum = fnv($in);
    my ($sepcount, $totalcount, $ipv6) = (0, 0);

    # ipv6, count colons
    if (index($in, ':') != -1) {
        $ipv6++;
        $totalcount = () = $in =~ /:/g
    }

    # has to be ipv4, then
    elsif (index($in, '.') == -1) {
        return;
    }

    my ($i, $out) = (-1, $in);
    for my $char (split //, $out) { $i++;

        if ($char eq ':' || $char eq '.') {
            $sepcount++;
            next;
        }

        if ($ipv6 && $sepcount < $totalcount / 2) {
            next;
        }

        if (!$ipv6 && $sepcount < 2) {
            next;
        }

        substr($out, $i, 1) = $ip_char_table[ (ord($char) + $accum) % 20 ];
        $accum = ($accum << 1) | ($accum >> 31);
        $accum &= 0xffffffff;
    }

    return $out;
}

sub do_host_cloak_host {
    my $in = shift;
    my $accum = fnv($in);

    # pass 1: scramble first section of hostname using base26
    # alphabet toasted against the FNV hash of the string.
    #
    # numbers are not changed at this time, only letters.
    #
    my ($i, $out) = (-1, $in);
    for my $char (split //, $out) { $i++;
        last if $char eq '.';
        next if $char =~ m/\d/ || $char eq '-';

        substr($out, $i, 1) = $b26_alphabet[ (ord($char) + $accum) % 26 ];

        # Rotate one bit to avoid all digits being turned odd or even
        $accum = ($accum << 1) | ($accum >> 31);
        $accum &= 0xffffffff;
    }

    # pass 2: scramble each number in the address
    $i = -1;
    for my $char (split //, $out) { $i++;
        if ($char =~ m/\d/) {
            my $c = ord('0') + (ord($char) + $accum) % 10;
            substr($out, $i, 1) = chr $c;
        }
        $accum = ($accum << 1) | ($accum >> 31);
        $accum &= 0xffffffff;
    }

    return $out;
}

$mod
