# Copyright (c) 2016, Mitchell Cooper
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
use List::Util 'min';
use utils qw(import ref_to_list);

our ($api, $mod, $pool, $conf);

###################
### juno -> TS6 ###
###################

*ts6_message = *M::TS6::Base::ts6_message;

# convert an object to its ID.
sub ts6_id {
    my $obj = shift;
    blessed $obj or return;

    # cached.
    return $obj->{ts6_id}  if length $obj->{ts6_id};
    return $obj->{ts6_uid} if length $obj->{ts6_uid};
    return $obj->{ts6_sid} if length $obj->{ts6_sid};

    my $r;
    if    ($obj->isa('user'))    { $r = ts6_uid($obj->{uid}) }
    elsif ($obj->isa('server'))  { $r = ts6_sid($obj->{sid}) }
    elsif ($obj->isa('channel')) { $r = $obj->{name}         }

    $obj->{ts6_id} = $r if length $r;
    return $r;
}

# convert an SID.
sub ts6_sid {
    my $sid = shift;

    # short SIDs can be represented normally.
    if (length $sid < 8) {
        return sprintf '%03d', $sid;
    }

    # longer SIDs are assumed to be generated by sid_from_ts6().
    # convert them back to juno format.
    my $new = '';
    while ($sid =~ s/(\d{1,3})$//) {
        $new = chr($1).$new;
    }

    return $new;
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

# TS6 SID or UID -> object
sub obj_from_ts6 {
    my $id = shift;
    if (length $id == 3) { return $pool->lookup_server(sid_from_ts6($id)) }
    if (length $id == 9) { return $pool->lookup_user  (uid_from_ts6($id)) }
    return;
}

# TS6 UID -> user
sub user_from_ts6 {
    my $user = obj_from_ts6(shift);
    return unless blessed $user && $user->isa('user');
    return $user;
}

# TS6 SID -> server
sub server_from_ts6 {
    my $server = obj_from_ts6(shift);
    return unless blessed $server && $server->isa('server');
    return $server;
}

# TS6 SID -> juno SID
sub sid_from_ts6 {
    my $sid = shift;
    return unless $sid =~ m/^[0-9A-Z]{3}$/;
    if ($sid =~ m/[A-Z]/) {
        return join('', map { sprintf '%03d', ord } split //, $sid) + 0;
    }
    return $sid + 0;
}

# TS6 UID -> juno UID
# e.g. 000AAAAAA -> 0a
sub uid_from_ts6 {
    my $uid = shift;
    my ($sid, $id) = ($uid =~ m/^([0-9A-Z]{3})([0-9A-Z]{6})$/);
    defined $sid && defined $id or return;
    return sid_from_ts6($sid).uid_u_from_ts6($id);
}

# TS6 ID -> juno ID
# e.g. AAAAAA -> a
# thanks to @Hakkin for helping with this
sub uid_u_from_ts6 { utils::n2a(&uid_n_from_ts6) }
sub uid_n_from_ts6 {
    my $dec   = 0;
    my @chars = split //, shift or return;
    for my $i (0..5) {
        my $ord = ord $chars[$i];
        my $add = $ord > 57 ? -65 : -22;
        my $p   = $ord + $add;
           $p  *= 36 ** (5 - $i) if $i < 5;
         $dec  += $p;
    }
    return ++$dec;
}


# convert juno level to prefix.
# returns empty string if there is no equivalent.
sub ts6_prefix {
    my ($server, $level) = @_;
    foreach my $prefix (keys %{ $server->{ircd_prefixes} || {} }) {
        my ($letter, $lvl) = ref_to_list($server->{ircd_prefixes}{$prefix});
        next unless $level == $lvl;
        return $prefix;
    }
    return '';
}

# returns the first level which is less than or equal to the prefix's level.
# e.g. 2 (owner) to charybdis would be 0 (op).
sub ts6_closest_level {
    my ($server, $level) = @_;

    # find the lowest supported level.
    my %supported_levels = map { $_->[1] => 1 }
        values %{ $server->{ircd_prefixes} || {} };
    my $lowest = min keys %supported_levels;

    # if the requested level is lower than the lowest supported,
    # we cannot do anything.
    return -inf if $level < $lowest;

    # starting with $level, go backwards to $lowest
    for (reverse $lowest .. $level) {
        return $_ if $supported_levels{$_};
    }

    return -inf;
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

# TS6 prefix -> mode letter
sub mode_from_prefix_ts6 {
    my ($server, $prefix) = @_;
    my $p = $server->{ircd_prefixes}{$prefix};
    return $p ? $p->[0] : '';
}

# TS6 prefix -> level
sub level_from_prefix_ts6 {
    my ($server, $prefix) = @_;
    my $p = $server->{ircd_prefixes}{$prefix};
    return $p ? $p->[1] : -inf;
}

$mod
