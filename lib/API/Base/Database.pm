# Copyright (c) 2014, Mitchell Cooper
package API::Base::Database;

use warnings;
use strict;
use 5.010;

use utils 'log2';

sub database {
}

sub _unload {
    my ($class, $mod) = @_;
    return 1;
}

1
