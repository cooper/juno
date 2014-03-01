# Copyright (c) 2014, Mitchell Cooper
# looks up idents.
package API::Module::Ident;

use warnings;
use strict;

use Net::Ident; # TODO: load dynamically

use utils qw(conf v match);

our $mod = API::Module->new(
    name        => 'Ident',
    version     => '0.1',
    description => 'resolve user identification',
    requires    => ['Events'],
    initialize  => \&init
);

sub init {
    $mod->register_ircd_event('connection.new' => \&connection_new) or return;
    return 1;
}

sub connection_new {
    my ($connection, $event) = @_;

    # prevent connection registration from completing.
    #$connection->reg_wait();

    
}

$mod
