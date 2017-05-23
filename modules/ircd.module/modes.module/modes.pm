# Copyright (c) 2009-16, Mitchell Cooper
#
# @name:            "ircd::modes"
# @package:         "modes"
# @description:     "represents a sequence of IRC mode changes"
# @version:         ircd->VERSION
#
# @no_bless
# @preserve_sym
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package modes;

use warnings;
use strict;
use 5.010;
use utf8;

use Scalar::Util qw(blessed looks_like_number);
use List::Util qw(first);
use utils qw(conf notice);

our ($mod, $me, $pool);

# Mode types
sub MODE_UNKNOWN () { -1 }
sub MODE_NORMAL  () {  0 }
sub MODE_PARAM   () {  1 }
sub MODE_PSET    () {  2 }
sub MODE_LIST    () {  3 }
sub MODE_STATUS  () {  4 }
sub MODE_KEY     () {  5 }

sub import {
    my $this_package = shift;
    my $package = caller;
    no strict 'refs';
    *{$package.'::'.$_} = *{$this_package.'::'.$_} foreach qw(
        MODE_UNKNOWN MODE_NORMAL MODE_PARAM
        MODE_PSET MODE_LIST MODE_STATUS MODE_KEY
    );
}

# modes->new(...)
# my $modes = modes->new(owner => 'mitch', op => 'mitch', -no_ext => undef)
sub new {
    my $class = shift;
    return bless [ @_ ], $class;
}

# modes->new_from_string(...)
# my $modes = modes->new_from_string($server, '+qo-n mitch mitch')
#
# fetches named modes from a mode string in a certain perspective.
#
# $server           the server perspective
# $mode_str         the mode string
# $over_protocol    true if the string has UIDs rather than nicks
#
# See issue #77 for the original idea.
#
sub new_from_string {
    my ($class, $server, $mode_str, $over_protocol) = @_;
    return modes->new if !length $mode_str;
    my @changes;

    # split into +modes, arguments.
    my ($parameters, $state, $str, @m) = ([], 1, '', split /\s+/, $mode_str);
    MODE: foreach my $letter (split //, shift @m) {

        # state change.
        if ($letter eq '+' || $letter eq '-') {
            $state = $letter eq '+';
            next MODE;
        }

        # unknown mode?
        my $name = $server->cmode_name($letter);
        my $type = $server->cmode_type($name);
        if (!defined $name || !defined $type) {
            notice(channel_mode_unknown =>
                ($state ? '+' : '-').$letter,
                $server->notice_info
            );
            next MODE;
        }

        # these are returned by ->cmode_takes_parameter: NOT mode types
        #     1 = always takes param
        #     2 = takes param, but valid if there isn't,
        #         such as list modes like +b for viewing
        #
        my ($takes, $param);
        if ($takes = $server->cmode_takes_parameter($name, $state)) {
            $param = shift @m;
            if (!defined $param && $takes == 1) {
                L("Mode '$name' is missing a parameter; skipped");
                next MODE;
            }
        }

        # convert nicks or UIDs to user objects.
        if (length $param && $type == MODE_STATUS) {
            my $user = $over_protocol           ?
                $server->uid_to_user($param)    :
                $pool->lookup_user_nick($param);
            $param = $user if $user;
        }

        # add it to the list of changes.
        my $prefixed_name = ($state ? '' : '-').$name;
        push @changes, $prefixed_name, $param;

    }

    return $class->new(@changes);
}

# $modes->push_mode(owner => $user)
# $modes->push_mode(-no_ext => undef)
#
# push a single mode name and parameter
#
sub push_mode {
    my ($modes, $name, $param) = @_;
    push @$modes, $name, $param;
}

# $modes->push_stated_mode(0, owner => $user)
sub push_stated_mode {
    my ($modes, $state, $name, $param) = @_;
    $name = "-$name" if !$state;
    $modes->push_mode($name => $param);
    return $modes;
}

# push a mode ref
sub push_modes {
    my ($modes, $new_modes) = @_;
    push @$modes, @$new_modes;
    return $modes;
}

# same as ->push_modes except it auto-simplifies
sub merge_in {
    my ($modes, $new_modes) = @_;
    return $modes->push_modes($new_modes)->simplify;
}

# the number of modes
sub count {
    my $modes = shift;
    return @$modes / 2;
}

# remove redundancies
sub simplify {
    my $modes = shift;
    my $new_modes = difference(modes->new, $modes);
    @$modes = @$new_modes;
    return $modes;
}

# change the sign of each mode
sub invert {
    my $modes = shift;
    my @new;
    while (my ($name, $param) = splice @$modes, 0, 2) {
        my $pfx = \substr $name, 0, 1;
        $$pfx = $$pfx eq '-' ? '' : "-$$pfx";
        push @new, $name, $param;
    }
    @$modes = @new;
    return $modes;
}

# remove modes matching criteria
sub remove {
    my ($modes, @matchers) = @_;
    my $new = _matching_not_matching(0, $modes, @matchers);
    @$modes = @$new;
    return $modes;
}

# remove modes not matching criteria
sub filter {
    my ($modes, @matchers) = @_;
    my $new = _matching_not_matching(1, $modes, @matchers);
    @$modes = @$new;
    return $modes;
}

# true if the given mode name or type is present
sub has {
    my ($modes, $name) = @_;
    return $modes->filter($name)->count;
}

sub _matching_not_matching {
    my ($matching, $modes, @matchers) = @_;
    @matchers = map _get_matcher($_), @matchers;
    my $matches = modes->new;

    # add only modes matching this
    foreach ($modes->stated) {
        my ($state, $name, $param) = @$_;
        my $found = first { $_->($name) } @matchers;
        next if !!$matching != !!$found;
        $matches->push_stated_mode($state, $name, $param);
    }

    return $matches;
}

sub _get_matcher {
    my $type = shift;

    # inf means all modes
    if ($type eq 'inf') {
        return sub { 1 };
    }

    # -inf means all except status modes
    elsif ($type eq -inf) {
        return sub { $me->cmode_type(shift) != MODE_STATUS };
    }

    # code ref is a custom matcher.
    elsif (ref $type eq 'CODE') {
        return $type;
    }

    # other number means all modes of the specified type.
    elsif (looks_like_number($type)) {
        return sub { $me->cmode_type(shift) == $type };
    }

    # anything else is hopefully a string mode name.
    return sub { shift() eq $type };
}

# my $string  = $modes->to_string(...)
# my @strings = $modes->to_strings(...)
#
# converts named modes to one or more mode strings.
#
#   $server             desired server perspective
#   $over_protocol      whether to spit out UIDs or nicks
#   $organize           whether to alphabetize the output
#   $skip_checks        for internal use; whether to skip certain sanity checks
#
sub to_string   { _to_strings(0, @_) }
sub to_strings  { _to_strings(1, @_) }
sub _to_strings {
    my ($split, $modes, $server, $over_protocol, $organize, $skip_checks) = @_;
    my @changes;

    # add each mode to the resultant.
    MODE: foreach ($modes->stated) {
        my ($state, $name, $param) = @$_;

        # $skip_checks is enabled when the modes were generated internally.
        # this is to improve efficiency when we're already certain it's valid.
        unless ($skip_checks) {

            # find the mode type.
            my $type = $me->cmode_type($name);
            if (!defined $type || $type == MODE_UNKNOWN) {
                L("Mode '$name' is not known to this server; skipped");
                next MODE;
            }

            # if the mode requires a parameter but one was not provided,
            # we have no choice but to skip this.
            #
            # these are returned by ->cmode_takes_parameter: NOT mode types
            #     1 = always takes param
            #     2 = takes param, but valid if there isn't,
            #         such as list modes like +b for viewing
            #
            my $takes = $me->cmode_takes_parameter($name, $state) || 0;
            if (!defined $param && $takes == 1) {
                L("Mode '$name' is missing a parameter; skipped");
                next MODE;
            }

        }

        push @changes, [ $state, $name, $param ];
    }

    # if $organize is specified, put positive changes first and alphabetize.
    @changes = sort {
        my $sort;
        $sort = -1 if  $a->[0] && !$b->[0];
        $sort = 1  if !$a->[0] &&  $b->[0];
        $sort // $a->[1] cmp $b->[1]
    } @changes if $organize;

    # determine how much we can jam into one string.
    my $limit =
        !$split         ? 'inf'                                     : # no limit
         $split == 1    ? conf('channels',
            $over_protocol ? 'max_modes_per_server_line' : 'max_modes_per_line'
                        )                                           : # config
         $split;    # custom amount specified as $split

    # stringify.
    my @strings;
    my ($str, @params) = '';
    my $current_state = -1;
    my $letters = 0;
    CHANGE: foreach my $change (@changes) {
        my ($state, $name, $param) = @$change;

        # start a new string.
        if ($letters >= $limit) {
            $str = join ' ', $str, @params;
            push @strings, $str;
            ($str, $letters, $current_state, @params) = ('', 0, -1);
        }

        # the state has changed.
        if ($state != $current_state) {
            $str .= $state ? '+' : '-';
            $current_state = $state;
        }

        # add the letter.
        my $letter = $server->cmode_letter($name) or next CHANGE;
        $str .= $letter;
        $letters++;

        # push the parameter.
        push @params, _stringify_cmode_parameter(
            $server, $name, $param, $state, $over_protocol
        ) if defined $param;

    }
    if (length $str) {
        $str = join ' ', $str, @params;
        push @strings, $str;
    }

    return $split && wantarray ? @strings : $strings[0] || '';
}

sub _stringify_cmode_parameter {
    my ($server, $name, $param, $state, $over_protocol) = @_;

    # it's a string already
    return $param if !ref $param;
    
    # not blessed, so it ought to be a hashref
    if (!blessed $param) {
        
        # always fire the 1459 stringifier
        my @events = [ "cmode.stringify.$name.1459" => $param ];
        
        # if this is over server protocol, also fire the proto-specific one
        push @events, [ "cmode.stringify.$name.$$server{link_type}" => $param ]
            if $over_protocol && defined $server->{link_type};
            
        # if this is over client protocol, add 'client' one
        push @events, [ "cmode.stringify.$name.client" => $param ]
            if !$over_protocol;

        my $fire = $pool->fire_events_together(@events);
        my ($string, $proto) = @$fire{'string', 'proto'};
        
        # nothing returned?!
        if (!length $string) {
            L("Mode '$name' stringifier for '$proto' protocol failed!");
            return $param;
        }
        
        return $string;
    }

    # for users, use UID or nickname.
    if ($param->isa('user')) {
        return $server->user_to_uid($param) if $over_protocol;
        return $param->name;
    }

    # for servers, use an SID or name.
    if ($param->isa('server')) {
        return $server->server_to_sid($param) if $over_protocol;
        return $param->name;
    }

    # fallback to name if available.
    if ($param->can('name')) {
        return $param->name;
    }

    return $param;
}

# modes::difference($old_modes, $new_modes)
sub difference {
    my ($_old_modes, $_new_modes, $remove_none) = @_;

    # explicitly copy the modes.
    my @old_modes = @$_old_modes;
    my @new_modes = @$_new_modes;

    # determine the original values.
    my %o_modes;
    while (my ($name, $param) = splice @old_modes, 0, 2) {
        my $type = $me->cmode_type($name);

        # this type takes a parameter.
        if ($me->cmode_takes_parameter($name, 1)) {
            $o_modes{$name}{$param} = $param;
            next;
        }

        # no parameter.
         $o_modes{$name}++;

    }

    # determine the new values.
    my %n_modes;
    while (my ($name, $param) = splice @new_modes, 0, 2) {

        # this type takes a parameter.
        if ($me->cmode_takes_parameter($name, 1)) {

            # only add to %n_modes if it does not exist in %o_modes.
            $n_modes{$name}{$param} = $param
                unless delete $o_modes{$name}{$param};

            next;
        }

        # no parameter.
        $n_modes{$name}++
            unless delete $o_modes{$name};
    }

    # ok, at this point:
    # %n_modes contains modes that were missing from $old_modes
    # %o_modes contains modes that were missing from $new_modes

    # create a moderef of the new modes.
    my $changes = modes->new;
    foreach my $name (keys %n_modes) {

        # if it takes a parameter, push each instance.
        if ($me->cmode_takes_parameter($name, 1)) {
            $changes->push_mode($name => $_)
                for values %{ $n_modes{$name} };
            next;
        }

        # otherwise, push the mode and undef.
        $changes->push_mode($name => undef);
    }

    # if we're not removing any modes, we're done.
    return $changes if $remove_none;

    # ok now add negated modes for anything that was missing from $new_modes.
    foreach my $name (keys %o_modes) {

        # if it takes a parameter, push each instance.
        if ($me->cmode_takes_parameter($name, 1)) {
            $changes->push_stated_mode(0, $name => $_)
                for values %{ $o_modes{$name} };
            next;
        }

        # otherwise, push the mode and undef.
        $changes->push_stated_mode(0, $name => undef);
    }

    return $changes;
}

sub stated {
    my $modes = shift;
    my @modes = @$modes;
    my @stated;
    while (my ($name, $param) = splice @modes, 0, 2) {
        my $pfx   = \substr $name, 0, 1;
        my $state = $$pfx ne '-';
        $$pfx     = '' if !$state;
        push @stated, [ $state, $name, $param ];
    }
    return @stated;
}

$mod
