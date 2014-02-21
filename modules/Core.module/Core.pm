# Copyright (c) 2009-13, Mitchell Cooper
package API::Module::Core;

use warnings;
use strict;
use utf8;
use API::Module;

our $mod = API::Module->new(
    name        => 'Core',
    version     => $ircd::VERSION,
    description => 'provides a set of core commands, modes, and more.',
    initialize  => \&init
);

# initialize.
sub init {
    
    # load submodules.
    $mod->load_submodule($_) || return foreach qw(
        ServerCommands OutgoingCommands UserModes
        ChannelModes UserNumerics UserCommands
    );

    return 1;   
}

$mod
