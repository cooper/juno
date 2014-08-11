# Copyright (c) 2014, mitchellcooper
#
# Created on Mitchells-Mac-mini.local
# Sat Aug  9 16:03:41 EDT 2014
# Utils.pm
#
# @name:            'TS6::Utils'
# @package:         'M::TS6::Utils'
# @description:     'utilities for the TS6 protocol'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::TS6::Utils;

use warnings;
use strict;
use 5.010;

use Scalar::Util 'blessed';
use utils 'import';

our ($api, $mod, $pool, $conf);

###################
### juno -> TS6 ###
###################

# convert an object to its ID.
sub ts6_id {
    my $obj = shift;
    blessed $obj or return;
    if ($obj->isa('user'))   { return ts6_uid($obj->{uid}) }
    if ($obj->isa('server')) { return ts6_sid($obj->{sid}) }
    return;
}

# convert an SID.
sub ts6_sid {
    my $sid = shift;
    return sprintf '%03d', $sid;
}

# convert a full UID.
sub ts6_uid {
    my $uid = shift;
    my ($sid, $id) = ($uid =~ m/^([0-9]+)([a-z]+)$/);
    return ts6_sid($sid).ts6_uid_u($id);
}

# convert just the alphabetic portion of a UID.
sub ts6_uid_u {
    my $id = shift;
    return ts6_id_n(utils::a2n($id));
}

# convert juno level to prefix.
sub ts6_prefix {
    my ($server, $level) = @_;
    my @pfx = $conf->values_of_block(['ts6_prefixes', $server->{ts6_ircd}]);
    foreach (@pfx) {
        my ($letter, $prefix, $lvl) = @$_;
        next unless $level == $lvl;
        return $prefix;
    }
    return '';
}

# convert juno levels to prefixes, removing duplicates.
sub ts6_prefixes {
    my ($server, @levels) = @_;
    my ($prefixes, %done) = '';
    foreach my $level (@levels) {
        my $prefix = ts6_prefix($server, $level);
        next if $done{$prefix};
        $prefixes .= $prefix;
        $done{$prefix} = 1;
    }
    return $prefixes;
}

# get nth ts6 ID.
sub ts6_id_n {
    my $n = shift() - 1;
    my @chars = ('A') x 6;
    my $i = 0;
    for my $pow (reverse 0..5) {
        my $amnt = 36 ** $pow;
        while ($n >= $amnt) {
            if    ($chars[$i] eq 'Z') { $chars[$i] = '0' }
            elsif ($chars[$i] eq '9') { $chars[$i] = 'A' }
            else  { $chars[$i]++ }
            $n -= $amnt;
        }
        $i++;
    }
    return join '', @chars;
}

###################
### TS6 -> juno ###
###################

# TS6 SID -> juno SID
# e.g. 000 -> 0
sub sid_from_ts6 {
    my $sid = shift;
    return $sid + 0;
}

# TS6 UID -> juno UID
# e.g. 000AAAAAA -> 0a
sub uid_from_ts6 {
    my $uid = shift;
    my ($sid, $id) = ($uid =~ m/^([0-9]+)([A-Z]+)$/);
    return sid_from_ts6($sid).uid_u_from_ts6($id);
}

# TS6 ID -> juno ID
# e.g. AAAAAA -> a
# thanks to @Hakkin for helping with this
sub uid_u_from_ts6 { utils::n2a(&uid_n_from_ts6) }
sub uid_n_from_ts6 {
    my $dec   = 0;
    my @chars = split //, shift;
    for my $i (0..5) {
        my $ord = ord $chars[$i];
        my $add = $ord > 57 ? -65 : -22;
        my $p   = $ord + $add;
           $p  *= 36 ** (5 - $i) if $i < 5;
         $dec  += $p;
    }
    return ++$dec;
}

$mod

