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
    my $string = '';
    my @m      = split /\s+/, $modestr;
    my $modes  = shift @m;
    
    foreach my $letter (split //, $modes) {
        my $new = $letter;

        # translate it.
        my $name = $server->cmode_name($letter);
        $new     = $server2->cmode_letter($name) // $new if $name;
        $string .= $new;
        
    }

    my $newstring = join ' ', $string, @m;
    log2("converted $modes to $string");
    return $newstring;
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
# both mode strings should only be +modes and have
# no - states because CUM only shows current modes.
#
# also, it will not work correctly if multiple
# instances of the same parameter are in either
# string; ex. +bb *!*@* *!*@*
#
sub cmode_string_difference {
    my ($server, $o_modestr, $n_modestr) = @_;

    # split into modes, @params
    my ($o_modes, @o_params) = split ' ', $o_modestr;
    my ($n_modes, @n_params) = split ' ', $n_modestr;
    substr($o_modes, 0, 1) = substr($n_modes, 0, 1) = '';

    # determine the original values. ex. $o_modes_p{b}{'hi!*@*'} = 1
    my (@o_modes, %o_modes_p);
    foreach my $letter (split //, $o_modes) {
    
        # find mode name and type.
        my $name = $server->cmode_name($letter) or next;
        my $type = $server->cmode_type($name);
        
        # this type takes a parameter.
        if ($server->cmode_takes_parameter($name, 1)) {
            defined(my $param = shift @o_params) or next;
            $o_modes_p{$letter}{$param} = 1;
            next;
        }
        
        # no parameter.
        push @o_modes, $letter;
       
    }

    # find the new modes.
    # modes_added   = modes present in the new string but not old
    # modes_added_p = same as above but with parameters

    my (@modes_added, %modes_added_p);
    foreach my $letter (split //, $n_modes) {

        # find mode name and type.
        my $name = $server->cmode_name($letter) or next;
        my $type = $server->cmode_type($name);
        
        # this type takes a parameter.
        if ($server->cmode_takes_parameter($name, 1)) {
            defined(my $param = shift @n_params) or next;

            # it's in the original.
            my $m = $o_modes_p{$letter};
            if ($m && $m->{$param}) {
                delete $m->{$param};
                delete $o_modes_p{$letter} if !scalar keys %$m;
            }
            
            # not there.
            else {
                $modes_added_p{$letter}{$param} = 1;
            }
            
            next;
        }
        
        # no parameter.

        # it's in the original.
        if ($letter ~~ @o_modes) {
            @o_modes = grep { $_ ne $letter } @o_modes;
        }
        
        # not there.
        else {
            push @modes_added, $letter;
        }
        
    }
    
    # at this point, anything in @o_modes or %o_modes_p is not
    # present in the new mode string but is in the old.

    # create the mode string with all added modes.
    my ($final_str, @final_p) = '';

    # add new modes found in new string but not old.
    $final_str .= '+' if scalar @modes_added || scalar keys %modes_added_p;
    $final_str .= join '', @modes_added;
    foreach my $letter (keys %modes_added_p) {
        foreach my $param (keys %{ $modes_added_p{$letter} }) {
            $final_str .= $letter;
            push @final_p, $param;
        }
    }
    
    # remove modes from original not found in new.
    $final_str .= '-' if scalar @o_modes || scalar keys %o_modes_p;
    $final_str .= join '', @o_modes;
    foreach my $letter (keys %o_modes_p) {
        foreach my $param (keys %{ $o_modes_p{$letter} }) {
            $final_str .= $letter;
            push @final_p, $param;
        }
    }
  
    return join ' ', $final_str, @final_p;
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

