# Copyright (c) 2012, Mitchell Cooper
package API::Base::UserNumerics;

use warnings;
use strict;
use v5.10;

use utils qw(log2 col trim);

use Scalar::Util 'looks_like_number';

sub register_user_numeric {
    my ($mod, %opts) = @_;

    # make sure all required options are present
    foreach my $what (qw|name number format|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        log2("user mode block $opts{name} does not have '$what' option.");
        return
    }

    # register the mode block
    user::modes::register_numeric(
        $mod->{name},
        $opts{name},
        $opts{number},
        $opts{format}
    ) or return;

    $mod->{user_numerics} ||= [];
    push @{ $mod->{user_numerics} }, $opts{name};
    
    return 1;
}

sub _unload {
    my ($class, $mod) = @_;
    log2("unloading user numerics registered by $$mod{name}");
    user::mine::delete_numeric($_) foreach @{ $mod->{user_numerics} };
    log2("done unloading numerics");
    return 1
}

1
