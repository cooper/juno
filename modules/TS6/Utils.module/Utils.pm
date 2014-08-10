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
    my $id  = uc shift;
    my $pfx = 'A' x (6 - length $id);
    return $pfx.$id;
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

$mod

