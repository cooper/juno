#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
package channel;

use warnings;
use strict;
use feature 'switch';
use parent qw(Evented::Object channel::mine);

use utils qw(log2 v match);

sub new {
    my ($class, %opts) = @_;
    return bless {
        users => [],
        modes => {},
        %opts
    }, $class;
}

# named mode stuff

sub is_mode {
    my ($channel, $name) = @_;
    return exists $channel->{modes}{$name}
}

sub unset_mode {
    my ($channel, $name) = @_;

    # is the channel set to this mode?
    if (!$channel->is_mode($name)) {
        log2("attempted to unset mode $name on that is not set on $$channel{name}; ignoring.")
    }

    # it is, so remove it
    delete $channel->{modes}{$name};
    log2("$$channel{name} -$name");
    return 1
}

# set channel modes
# takes an optional parameter
# $channel->set_mode('moderated');
sub set_mode {
    my ($channel, $name, $parameter) = @_;
    $channel->{modes}{$name} = {
        parameter => $parameter,
        time      => time
        # list for list modes and status
    };
    log2("$$channel{name} +$name");
    return 1
}

# list has something
sub list_has {
    my ($channel, $name, $what) = @_;
    return unless exists $channel->{modes}{$name};
    foreach my $thing ($channel->list_elements($name)) {
        return 1 if $thing eq $what
    }
    return
}

# something matches in an expression list
# returns the match if there is one.
sub list_matches {
    my ($channel, $name, $what) = @_;
    return unless exists $channel->{modes}{$name};
    foreach my $mask ($channel->list_elements($name)) {
        my $realmask = $mask;
        $realmask = (split ':', $mask, 2)[1] if $mask =~ m/^(.+?):(.+)!(.+)\@(.+)/;
        return $mask if match($what, $realmask);
    }
    return;
}

# returns an array of list elements
sub list_elements {
    my ($channel, $name) = @_;
    return unless exists $channel->{modes}{$name};
    return map { $_->[0] } @{ $channel->{modes}{$name}{list} }
}

# adds something to a list mode (such as ban)
sub add_to_list {
    my ($channel, $name, $parameter, %opts) = @_;
    $channel->{modes}{$name} = {
        time => time,
        list => []
    } unless exists $channel->{modes}{$name};

    # no duplicates plz
    if ($channel->list_has($name, $parameter)) {
        return;
    }

    log2("$$channel{name}: adding $parameter to $name list");
    my $array = [$parameter, \%opts];
    push @{ $channel->{modes}{$name}{list} }, $array;
    
    return 1;
}

# removes something from a list
sub remove_from_list {
    my ($channel, $name, $what) = @_;
    return unless $channel->list_has($name, $what);

    my @new = grep { $_->[0] ne $what } @{ $channel->{modes}{$name}{list} };
    $channel->{modes}{$name}{list} = \@new;
    
    log2("$$channel{name}: removing $what from $name list");
    return 1;
}

# user joins channel
sub cjoin {
    my ($channel, $user, $time) = @_;

    # fire before join event.
    my $e = $channel->fire_event(user_will_join => $user);
    
    # a handler suggested that the join should not occur.
    return if $e->{join_fail};
    
    log2("adding $$user{nick} to $$channel{name}");
    
    # the channel TS will change
    # if the join time is older than the channel time
    if ($time < $channel->{time}) {
        $channel->set_time($time);
    }
    
    # add the user to the channel
    push @{ $channel->{users} }, $user;
    
    # note: as of 5.91, after-join event is fired in
    # mine.pm:           for locals
    # core_scommands.pm: for nonlocals.
 
    return $channel->{time}

}

# remove a user
sub remove {
    my ($channel, $user) = @_;

    # remove the user from status lists
    foreach my $name (keys %{ $channel->{modes} }) {
        if (v('SERVER')->cmode_type($name) == 4) {
            $channel->remove_from_list($name, $user);
        }
    }

    # remove the user.
    my @new = grep { $_ != $user } @{ $channel->{users} };
    $channel->{users} = \@new;
    
    # delete the channel if this is the last user
    if (!scalar @{ $channel->{users} }) {
        $channel->{pool}->delete_channel($channel);
    }
    
    log2("removed $$user{nick} from $$channel{name}");

    return 1;
}

# alias remove_user.
sub remove_user;
*remove_user = *remove;

# user is on channel
sub has_user {
    my ($channel, $user) = @_;
    foreach my $usr (@{ $channel->{users} }) {
        return 1 if $usr == $user
    }
    return
}

# set the channel time
sub set_time {
    my ($channel, $time) = @_;
    if ($time > $channel->{time}) {
        log2("warning: setting time to a lower time from $$channel{time} to $time");
    }
    $channel->{time} = $time
}

# returns the mode string,
# or '+' if no changes were made.
sub handle_mode_string {
    my ($channel, $server, $source, $modestr, $force, $over_protocol) = @_;
    log2("set $modestr on $$channel{name} from $$server{name}");

    # array reference passed to mode blocks and used in the return
    my $parameters = [];

    my $state = 1;
    my $str   = '+';
    my @m     = split /\s+/, $modestr;

    letter: foreach my $letter (split //, shift @m) {
        if ($letter eq '+') {
            $str  .= '+' unless $state;
            $state = 1
        }
        elsif ($letter eq '-') {
            $str  .= '-' if $state;
            $state = 0
        }
        else {
            my $name = $server->cmode_name($letter);
            if (!defined $name) {
                log2("unknown mode $letter!");
                next
            }
            my $parameter = undef;
            if (my $takes = $server->cmode_takes_parameter($name, $state)) {
                $parameter = shift @m;
                next letter if !defined $parameter && $takes == 1
            }

            # don't allow this mode to be changed if the test fails
            # *unless* force is provided.
            my ($win, $moderef) = $main::pool->fire_channel_mode(
                $channel, $server, $source, $state, $name, $parameter,
                $parameters, $force, $over_protocol
            );

            # block says to send ERR_CHANOPRIVSNEEDED
            if ($moderef->{send_no_privs} && $source->isa('user') && $source->is_local) {
                $source->numeric(ERR_CHANOPRIVSNEEDED => $channel->{name});
            }

            # blocks failed.
            if (!$force) { next letter unless $win }

            # block says not to set.
            next letter if $moderef->{do_not_set};

            # if it is just a normal mode, set it
            if ($server->cmode_type($name) == 0) {
                my $do = $state ? 'set_mode' : 'unset_mode';
                $channel->$do($name);
            }
            $str .= $letter
        }
    }

    # it's easier to do this than it is to keep track of them
    $str =~ s/\+\+/\+/g;
    $str =~ s/\-\+/\+/g;
    $str =~ s/\-\-/\-/g; 
    $str =~ s/\+\-/\-/g;
    $str =~ s/(\-|\+)$//;

    # make it change array refs to separate params for servers
    # [USER RESPONSE, SERVER RESPONSE]
    my @user_params;
    my @server_params;
    foreach my $param (@$parameters) {
        if (ref $param eq 'ARRAY') {
            push @user_params,   $param->[0];
            push @server_params, $param->[1]
        }

        # not an array ref
        else {
            push @user_params,  $param;
            push @server_params, $param
        }
    }

    my $user_string   = join ' ', $str, @user_params;
    my $server_string = join ' ', $str, @server_params;

    log2("end of mode handle");
    return ($user_string, $server_string)
}

# returns a +modes string
#   normal (0)
#   parameter (1)
#   parameter_set (2)
#   list (3)
#   status (4)
sub mode_string {
    my ($channel, $server) = @_;
    my (@modes, @params);
    my @set_modes = sort { $a cmp $b } keys %{ $channel->{modes} };
    foreach my $name (@set_modes) {
        given ($server->cmode_type($name)) {
            when (0) { }
            when (1) { }
            when (2) { }
            default  { next }
        }
        push @modes, $server->cmode_letter($name);
        if (my $param = $channel->{modes}{$name}{parameter}) {
            push @params, $param
        }
    }

    return '+'.join(' ', join('', @modes), @params)
}

# includes ALL modes
# returns a string for users and a string for servers
sub mode_string_all {
    my ($channel, $server) = @_;
    my (@modes, @user_params, @server_params);
    my @set_modes = sort { $a cmp $b } keys %{ $channel->{modes} };

    foreach my $name (@set_modes) {
        my $letter = $server->cmode_letter($name);
        given ($server->cmode_type($name)) {

            # modes with 0 or 1 parameters
            when ([0, 1, 2]) {
                push @modes, $letter;
                continue
            }

            # modes with ONE parameter
            when ([1, 2]) {
                push @user_params,   $channel->{modes}{$name}{parameter};
                push @server_params, $channel->{modes}{$name}{parameter}
            }

            # lists
            when (3) {
                foreach my $thing ($channel->list_elements($name)) {
                    push @modes,         $letter;
                    push @user_params,   $thing;
                    push @server_params, $thing
                }
            }

            # lists of users
            when (4) {
                foreach my $user ($channel->list_elements($name)) {
                    push @modes,         $letter;
                    push @user_params,   $user->{nick};
                    push @server_params, $user->{uid}
                }
            }

            # idk
            default  { next }
        }
    }

    # make +modes params strings
    my $user_string   = '+'.join(' ', join('', @modes), @user_params);
    my $server_string = '+'.join(' ', join('', @modes), @server_params);

    # returns both a user string and a server string
    return ($user_string, $server_string)
}

# returns true only if the passed user is in
# the passed status list.
sub user_is {
    my ($channel, $user, $what) = @_;
    return 1 if $channel->list_has($what, $user);
    return
}

# returns true value only if the passed user has status
# greater than voice (halfop, op, admin, owner)
sub user_has_basic_status {
    my ($channel, $user) = @_;
    foreach my $status (qw|owner admin op halfop|) {
        return 1 if $channel->user_is($user, $status);
    }
    return
}

# get the highest level of a user
# [letter, symbol, name]
sub user_get_highest_level {
    my ($channel, $user) = @_;
    my $biggest = -'inf';
    foreach my $level (keys %ircd::channel_mode_prefixes) {
        my ($letter, $symbol, $name) = @{ $ircd::channel_mode_prefixes{$level} };
        $biggest = $level if $level > $biggest && $channel->list_has($name, $user);
    }
    return $biggest;
}

sub id   { shift->{name} }
sub name { shift->{name} }

1
