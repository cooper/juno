# Copyright (c) 2012, Mitchell Cooper
package API::Module;

use warnings;
use strict;

use utils qw(log2);

our @ISA;

sub new {
    my ($class, %opts) = @_;
    $opts{requires} ||= [];

    # make sure all required options are present
    foreach my $what (qw|name version description initialize|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        log2("module $opts{name} does not have '$what' option.");
        return
    }

    # initialize and void must be code
    if (not defined ref $opts{initialize} or ref $opts{initialize} ne 'CODE') {
        log2("module $opts{name} didn't supply CODE");
        return
    }
    if ((defined $opts{void}) && (not defined ref $opts{void} or ref $opts{void} ne 'CODE')) {
        log2("module $opts{name} provided void, but it is not CODE.");
        return
    }

    # package name
    $opts{package} = caller;

    return bless my $mod = \%opts, $class;
}

1
