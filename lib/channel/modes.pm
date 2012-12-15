#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
package channel::modes;

use warnings;
use strict;

use utils qw(log2 conf);

# constants
#sub normal        () { 0 }
#sub parameter     () { 1 }
#sub parameter_set () { 2 }
#sub list          () { 3 }
#sub status        () { 4 }

# types:
#   normal (0)
#   parameter (1)
#   parameter_set (2)
#   list (3)
#   status (4)

our (%blocks, %prefixes);

# this just tells the internal server what
# mode is associated with what letter and type by configuration
sub add_internal_modes {
    my $server = shift;
    log2('registering channel status modes');

    # [letter, symbol, name]
    foreach my $name ($ircd::conf->keys_of_block('prefixes')) {
        my $p = conf('prefixes', $name);
        $server->add_cmode($name, $p->[0], 4);
        $prefixes{$p->[2]} = [ $p->[0], $p->[1], $name ]
    }

    log2("registering channel mode letters");

    foreach my $name ($ircd::conf->keys_of_block(['modes', 'channel'])) {
        $server->add_cmode(
            $name,
            (conf(['modes', 'channel'], $name))->[1],
            (conf(['modes', 'channel'], $name))->[0]
        );

    }

    log2("end of internal modes");
}

# register a block check to a mode
sub register_block {
    my ($name, $what, $code) = @_;
    if (ref $code ne 'CODE') {
        log2((caller)[0]." tried to register a block to $name that isn't CODE.");
        return
    }
    if (exists $blocks{$name}{$what}) {
        log2((caller)[0]." tried to register $name to $what which is already registered");
        return
    }
    log2("registered $name from $what");
    $blocks{$name}{$what} = $code;
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


sub fire {
    my (
        $channel, $server,
        $source, $state,
        $name, $parameter,
        $parameters, $force,
        $over_protocol
    ) = @_;

    if (!exists $blocks{$name}) {
        # nothing to do
        return 1
    }

    # create a hashref with info
    my $this = {
        channel => $channel,
        server  => $server,
        source  => $source,
        state   => $state,
        param   => $parameter,
        params  => $parameters,
        force   => $force,
        proto   => $over_protocol
    };

    foreach my $block (values %{$blocks{$name}}) {
        return (undef, $this) unless $block->($channel, $this)
    }
    return (1, $this)
}

# get a +modes string
sub mode_string {
    my @modes = sort { $a cmp $b } map { $_->[1] } $ircd::conf->values_of_block('modes', 'channel');
    return join '', @modes
}

1
