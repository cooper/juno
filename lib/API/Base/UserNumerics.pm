# Copyright (c) 2012, Mitchell Cooper
package API::Base::UserNumerics;

use warnings;
use strict;
use v5.10;

use utils qw(log2 col trim);

use Scalar::Util 'looks_like_number';

sub register_user_numeric {
}

sub _unload {
    my ($class, $mod) = @_;
    log2("unloading user numerics registered by $$mod{name}");
    user::mine::delete_handler($_) foreach @{$mod->{user_numerics}};
    log2("done unloading numerics");
    return 1
}

1
