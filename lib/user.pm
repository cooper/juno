#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
package user;

use warnings;
use strict;
use overload
    fallback => 1,
    '""'     => sub { shift->id },
    '0+'     => sub { shift     },
    bool     => sub { 1         };

use user::mine;
use user::numerics;
use user::modes;
use utils qw[log2 v set];

our %user;

# create a new user

sub new {

    my ($class, $ref) = @_;
    
    # create the user object
    bless my $user      = {}, $class;
    $user->{$_}         = $ref->{$_} foreach qw[nick ident real host ip ssl uid time server cloak source location];
    $user->{modes}      = []; # named modes!
    $user->{flags}      = []; # oper flags
    $user{$user->{uid}} = $user;
    log2("new user from $$user{server}{name}: $$user{uid} $$user{nick}!$$user{ident}\@$$user{host} [$$user{real}]");

    # update max local and global user counts
    my $max_l = v('max_local_user_count');
    my $max_g = v('max_global_user_count');
    my $c_l   = scalar grep { $_->is_local } values %user;
    my $c_g   = scalar values %user;
    v('max_local_user_count')  = $c_l if $c_l > $max_l;
    v('max_global_user_count') = $c_g if $c_g > $max_g;

    return $user

}

# named mode stuff

sub is_mode {
    my ($user, $mode) = @_;
    $mode ~~ @{$user->{modes}}
}

sub unset_mode {
    my ($user, $name) = @_;

    # is the user set to this mode?
    if (!$user->is_mode($name)) {
        log2("attempted to unset mode $name on that is not set on $$user{nick}; ignoring.")
    }

    # he is, so remove it
    log2("$$user{nick} -$name");
    @{$user->{modes}} = grep { $_ ne $name } @{$user->{modes}}

}

sub set_mode {
    my ($user, $name) = @_;
    return if $user->is_mode($name);
    log2("$$user{nick} +$name");
    push @{$user->{modes}}, $name
}

sub quit {
    my ($user, $reason) = @_;
    log2("user quit from $$user{server}{name} uid:$$user{uid} $$user{nick}!$$user{ident}\@$$user{host} [$$user{real}] ($reason)");

    my %sent = ( $user => 1 );
    $user->sendfrom($user->full, "QUIT :$reason") if $user->is_local;

    # search for local users that know this client
    # and send the quit to them.

    foreach my $channel (values %channel::channels) {
        next unless $channel->has_user($user);
        $channel->remove($user);
        foreach my $usr (@{$channel->{users}}) {
            next unless $usr->is_local;
            next if $sent{$usr};
            $usr->sendfrom($user->full, "QUIT :$reason");
            $sent{$usr} = 1
        }
    }

    delete $user{$user->{uid}};
    undef $user;
}

sub change_nick {
    my ($user, $newnick) = @_;

    # make sure it doesn't exist first
    if (lookup_by_nick($newnick)) {
        log2("attempted to change nicks to a nickname that already exists! $newnick");
        return
    }

    log2("$$user{nick} -> $newnick");
    $user->{nick} = $newnick
}

# handle a mode string and convert the mode letters to their mode
# names by searching the user's server's modes. returns the mode
# string, or '+' if no changes were made.
sub handle_mode_string {
    my ($user, $modestr, $force) = @_;
    log2("set $modestr on $$user{nick}");
    my $state = 1;
    my $str   = '+';
    letter: foreach my $letter (split //, $modestr) {
        if ($letter eq '+') {
            $str .= '+' unless $state;
            $state = 1
        }
        elsif ($letter eq '-') {
            $str .= '-' if $state;
            $state = 0
        }
        else {
            my $name = $user->{server}->umode_name($letter);
            if (!defined $name) {
                log2("unknown mode $letter!");
                next
            }

            # ignore stupid mode changes
            if ($state && $user->is_mode($name) ||
              !$state && !$user->is_mode($name)) {
                next
            }

            # don't allow this mode to be changed if the test fails
            # *unless* force is provided. generally ou want to use
            # tests only is local, since servers can do whatever.
            my $win = user::modes::fire($user, $state, $name);
            if (!$force) {
                next unless $win
            }

            my $do = $state ? 'set_mode' : 'unset_mode';
            $user->$do($name);
            $str .= $letter
        }
    }

    # it's easier to do this than it is to
    # keep track of them
    $str =~ s/\+\+/\+/g;
    $str =~ s/\-\-/\-/g; 
    $str =~ s/\+\-/\-/g;
    $str =~ s/\-\+/\+/g;

    log2("end of mode handle");
    return $str
}

# returns a +modes string
sub mode_string {
    my $user = shift;
    my $string = '+';
    foreach my $name (@{$user->{modes}}) {
        $string .= $user->{server}->umode_letter($name)
    }
    return $string
}

# add oper flags
sub add_flags {
    my $user  = shift;
    my @flags = grep { !$user->has_flag($_) } @_;
    log2("adding flags to $$user{nick}: @flags");
    push @{$user->{flags}}, @flags
}

# remove oper flags
sub remove_flags {
    my $user   = shift;
    my @remove = @_;
    my %r;
    log2("removing flags from $$user{nick}: @remove");

    @r{@remove}++;

    my @new        = grep { !exists $r{$_} } @{$user->{flags}};
    $user->{flags} = \@new;
}

# has oper flag
sub has_flag {
    my ($user, $flag) = @_;
    return $flag ~~ @{$user->{flags}}
}

# set away msg
sub set_away {
    my ($user, $reason) = @_;
    $user->{away} = $reason;
    log2("$$user{nick} is now away: $reason");
}

# return from away
sub unset_away {
    my $user = shift;
    log2("$$user{nick} has returned from being away: $$user{away}");
    delete $user->{away};
}

# lookup functions

sub lookup_by_nick {
    my $nick = lc shift;
    foreach my $user (values %user) {
        return $user if lc $user->{nick} eq $nick
    }
    return
}

sub lookup_by_id {
    my $uid = shift;
    return $user{$uid} if exists $user{$uid};
    return
}

sub is_local {
    return shift->{server} == v('SERVER')
}

sub full {
    my $user = shift;
    "$$user{nick}!$$user{ident}\@$$user{host}"
}

sub fullcloak {
    my $user = shift;
    "$$user{nick}!$$user{ident}\@$$user{cloak}"
}

sub DESTROY {
    my $user = shift;
    log2("$user destroyed");
}

# local shortcuts

sub handle        { &user::mine::handle        }
sub send          { &user::mine::send          }
sub sendfrom      { &user::mine::sendfrom      }
sub sendserv      { &user::mine::sendserv      }
sub server_notice { &user::mine::server_notice }
sub numeric       { &user::mine::numeric       }
sub id            { shift->{uid}               }
sub name          { shift->{nick}              }

1
