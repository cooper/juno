#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
package server;

use warnings;
use strict;
use feature 'switch';
use parent 'Evented::Object';

use utils qw[log2 v];

sub new {
    my ($class, %opts) = @_;
    return bless {
        umodes   => {},
        cmodes   => {},
        users    => [],
        children => [],
        %opts
    }, $class;
}

sub quit {
    my ($server, $reason, $why) = @_;
    $why //= $server->{name}.q( ).$server->{parent}->{name};

    log2("server $$server{name} has quit: $reason");

    # all children must be disposed of.
    foreach my $serv (@{ $server->{children} }) {
        next if $serv == $server;
        $serv->quit('parent server has disconnected', $why);
    }

    # delete all of the server's users.
    foreach my $user (@{ $server->{users} }) {
        $user->quit($why);
    }

    $server->{pool}->delete_server($server);
    return 1;
}

# add a user mode
sub add_umode {
    my ($server, $name, $mode) = @_;
    $server->{umodes}->{$name} = {
        letter => $mode
    };
    log2("$$server{name} registered $mode:$name");
    return 1
}

# umode letter to name
sub umode_name {
    my ($server, $mode) = @_;
    foreach my $name (keys %{$server->{umodes}}) {
        return $name if $mode eq $server->{umodes}->{$name}->{letter}
    }
    return
}

# umode name to letter
sub umode_letter {
    my ($server, $name) = @_;
    return $server->{umodes}->{$name}->{letter}
}

# add a channel mode
# types:
#   0: normal
#   1: parameter
#   2: parameter only when set
#   3: list
#   4: status
# I was gonna make a separate type for status modes but
# i don't if that's necessary
sub add_cmode {
    my ($server, $name, $mode, $type) = @_;
    $server->{cmodes}->{$name} = {
        letter => $mode,
        type   => $type
    };
    log2("$$server{name} registered $mode:$name");
    return 1
}

# cmode letter to name
sub cmode_name {
    my ($server, $mode) = @_;
    return unless defined $mode;
    foreach my $name (keys %{$server->{cmodes}}) {
        next unless defined $server->{cmodes}->{$name}->{letter};
        return $name if $mode eq $server->{cmodes}->{$name}->{letter}
    }
    return
}

# cmode name to letter
sub cmode_letter {
    my ($server, $name) = @_;
    return $server->{cmodes}->{$name}->{letter}
}

# type
sub cmode_type {
    my ($server, $name) = @_;
    return $server->{cmodes}->{$name}->{type}
}

# change 1 server's mode string to another server's
sub convert_cmode_string {
    my ($server, $server2, $modestr) = @_;
    my $string = q..;
    my @m      = split / /, $modestr;

    foreach my $letter (split //, shift @m) {
        my $new = $letter;

        # translate it
        my $name = $server->cmode_name($letter);
        if ($name) { $new = $server2->cmode_letter($name) || $new }
        $string .= $new
    }

    my $newstring = join ' ', $string, @m;
    log2("converted \"$modestr\" to \"$newstring\"");
    return $newstring
}

sub cmode_takes_parameter {
    my ($server, $name, $state) = @_;
    given ($server->{cmodes}->{$name}->{type}) {
        # always give a parameter
        when (1) {
            return 1
        }

        # only give a parameter when setting
        when (2) {
            return $state
        }

        # lists like +b always want a parameter
        # keep in mind that these view lists when there isn't one, though
        # REVISION: blocks for these modes must check for parameters manually.
        # if there is a parameter, it will set or unset. it should send a numerical
        # list otherwise.
        when (3) {
            return 2 # 2 means yes if present but still valid if not present
        }

        # status modes always want a parameter
        when (4) {
            return 1
        }
    }

    # or give nothing
    return
}

sub is_local {
    return shift == v('SERVER')
}

sub DESTROY {
    my $server = shift;
    log2("$server destroyed");
}

# local shortcuts
sub handle   { &server::mine::handle   }
sub send     { &server::mine::send     }
sub sendfrom { &server::mine::sendfrom }
sub sendme   { &server::mine::sendme   }

# other
sub id       { shift->{sid}      }
sub full     { shift->{name}     }
sub name     { shift->{name}     }
sub children { shift->{children} }


1

