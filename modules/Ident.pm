# Copyright (c) 2014, Mitchell Cooper
# looks up idents.
package API::Module::Ident;

use warnings;
use strict;

use utils qw(conf v match);

our $mod = API::Module->new(
    name        => 'Ident',
    version     => '0.1',
    description => 'resolve user identification',
    requires    => ['Events'],
    initialize  => \&init
);

sub init {

    return 1;
}

$mod
