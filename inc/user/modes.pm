#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
package user::modes;

use warnings;
use strict;

use utils 'log2';

my %blocks;

# this just tells the internal server what
# mode is associated with what letter as defined by the configuration
sub add_internal_modes {
    my $server = shift;
    return unless $utils::conf{modes}{user};
    log2("registering user mode letters");
    foreach my $name (keys %{$utils::conf{modes}{user}}) {
        $server->add_umode($name, $utils::conf{modes}{user}{$name});
    }
    log2("end of user mode letters");
}

# returns a string of every mode
sub mode_string {
    my @modes = sort { $a cmp $b } values %{$utils::conf{modes}{user}};
    return join '', @modes
}

# here we create the internal mode "blocks"
# which are called by a mode handler.
# if any blocks of a mode return false,
# the mode will not be set.
# they have unique names because some API
# modules might want to override or remove them.
# *** keep in mind that these are only used
# for local mode changes (the user MODE command),
# and changes from a user on a different server
# will not apply to these and must be handled
# separately

# register a block check to a mode
sub register_block {
    my ($name, $what, $code) = @_;

    # check if it is CODE
    if (ref $code ne 'CODE') {
        log2((caller)[0]." tried to register a block to $name that isn't CODE.");
        return
    }

    # make sure this one doesn't exist
    if (exists $blocks{$name}{$what}) {
        log2((caller)[0]." tried to register $what to $name which is already registered");
        return
    }

    # success
    $blocks{$name}{$what} = $code;
    log2("registered $name from $what");
    return 1
}

# delete a block
sub delete_block {
    my ($name, $what) = @_;
    if (exists $blocks{$name}{$what}) {
        delete $blocks{$name}{$what};
        log2("deleting user mode block for $name: $what");
        return 1
    }
    return
}

# call on mode change
sub fire {
    my ($user, $state, $name) = @_;
    if (!exists $blocks{$name}) {
        # nothing to do
        return 1
    }

    # call each block
    foreach my $block (values %{$blocks{$name}}) {
        return unless $block->($user, $state)
    }

    # all returned true
    return 1
}

1
