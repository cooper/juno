# Copyright (c) 2014, Mitchell Cooper
package API::Base::OperNotices;

use warnings;
use strict;
use v5.10;

use utils qw(log2);

our $VERSION = $ircd::VERSION;

sub register_oper_notice {
    my ($mod, %opts) = @_;

    # make sure all required options are present
    foreach my $what (qw|name format|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        log2("oper notice '$opts{name}' does not have '$what' option.");
        return
    }

    # register the mode block
    $::pool->register_notice(
        $mod->{name},
        $opts{name},
        $opts{format} // $opts{code}
    ) or return;

    push @{ $mod->{oper_notices} ||= [] }, $opts{name};
    return 1;
}

sub _unload {
    my ($class, $mod) = @_;
    log2("unloading oper notices registered by $$mod{name}");
    $::pool->delete_notice($mod->{name}, $_) foreach @{ $mod->{oper_notices} };
    log2("done unloading oper notices");
    return 1;
}

1
