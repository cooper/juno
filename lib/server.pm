#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
package server;

use warnings;
use strict;
use feature 'switch';
use parent qw(Evented::Object server::mine);

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
    $why //= $server->{name}.q( ).$server->{parent}{name};

    log2("server $$server{name} has quit: $reason");

    # all children must be disposed of.
    foreach my $serv (@{ $server->{children} }) {
        next if $serv == $server;
        $serv->quit('parent server has disconnected', $why);
    }

    # delete all of the server's users.
    my @users = @{ $server->{users} };
    foreach my $user (@users) {
        $user->quit($why);
    }

    $server->{pool}->delete_server($server) if $server->{pool};
    return 1;
}

# add a user mode
sub add_umode {
    my ($server, $name, $mode) = @_;
    $server->{umodes}{$name} = {
        letter => $mode
    };
    log2("$$server{name} registered $mode:$name");
    return 1
}

# umode letter to name
sub umode_name {
    my ($server, $mode) = @_;
    foreach my $name (keys %{ $server->{umodes} }) {
        return $name if $mode eq $server->{umodes}{$name}{letter}
    }
    return
}

# umode name to letter
sub umode_letter {
    my ($server, $name) = @_;
    return $server->{umodes}{$name}{letter}
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
    $server->{cmodes}{$name} = {
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
    foreach my $name (keys %{ $server->{cmodes} }) {
        next unless defined $server->{cmodes}{$name}{letter};
        return $name if $mode eq $server->{cmodes}{$name}{letter}
    }
    return
}

# cmode name to letter
sub cmode_letter {
    my ($server, $name) = @_;
    return $server->{cmodes}{$name}{letter}
}

# type
sub cmode_type {
    my ($server, $name) = @_;
    return $server->{cmodes}{$name}{type}
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
    given ($server->{cmodes}{$name}{type}) {
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

#
# takes a channel mode string and compares
# it with another, returning the difference.
# basically, for example,
#
#   given
#       $o_modestr = +ntb *!*@*
#       $n_modestr = +nibe *!*@* mitch!*@*
#   result
#       +ie-t mitch!*@*
#
# o_modestr = original, the original.
# n_modestr = new, the primary one that dictates.
#
# note that this is intended to be used for strings
# produced by the ircd, such as in the CUM command,
# and this does not handle stupidity well.
#
# specifically, it does not check if multiple
# parameters exist for a mode type intended to
# have only a single parameter such as +l.
#
sub cmode_string_difference {
    my ($server, $o_modestr, $n_modestr) = @_;

    # split into +something, @params
    my ($o_modes, @o_params) = split ' ', $o_modestr;
    my ($n_modes, @n_params) = split ' ', $n_modestr;
    
    # determine the original values.
    my $state = 1;
    my (@o_modes, %o_modes_p);
    foreach my $letter (split //, $o_modes) {
        $state   = 1, next if $letter eq '+';
        $state   = 0, next if $letter eq '-';
        my $name = $server->cmode_name($letter);
        
        # this type takes a parameter.
        if ($server->cmode_takes_parameter($name)) {
            my $value = shift @o_params;
            my $a     = $o_modes_p{$letter} ||= [];
            
            push @$a, $value                    if  $state;
            @$a = grep { $_ ne $value } @$a     if !$state;
        
            next;
        }
        
        # no parameter.
        push @o_modes, $letter if $state;
        @o_modes = grep { $_ ne $letter } if not $state;
        
    }

    # search for differences.
    $state = 1;
    my (@n_modes, %n_modes_p);
    foreach my $letter (split //, $n_modes) {
        $state   = 1, next if $letter eq '+';
        $state   = 0, next if $letter eq '-';
        my $name = $server->cmode_name($letter);
        
        # this type takes a parameter.
        if ($server->cmode_takes_parameter($name)) {
            my $value = shift @n_params;
            my $b     = $n_modes_p{$letter} ||= [];

            if ($state) {

                # already there.
                my $a = $o_modes_p{$letter};
                next if $a && $value ~~ @$a;
                
                # not there.
                push @$b, $value;
                
            }
            
            else {
            
                # not there.
                my $a = $o_modes_p{$letter};
                next if not $a && $value ~~ @$a;
            
                # is there.
                @$b = grep { $_ ne $value } @$b;
                
            }
            
            next;
        }
        
        # no parameter.
        
        if ($state) {
            next if $letter ~~ @o_modes; # already have it.
            push @n_modes, $letter;
        }
        
        else {
            next if $letter ~~ @o_modes; # don't have it.
            push @n_modes, $letter;
        }
        
        
    }

    my $f_str = join(' ', '+'.join('', @n_modes, keys %n_modes_p), values %n_modes_p);
    return $f_str eq '+' ? '' : $f_str;
}

sub is_local {
    return shift == v('SERVER')
}

sub DESTROY {
    my $server = shift;
    log2("$server destroyed");
}

# shortcuts
sub id       { shift->{sid}      }
sub full     { shift->{name}     }
sub name     { shift->{name}     }
sub children { shift->{children} }


1

