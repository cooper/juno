# Copyright (c) 2009-16, Mitchell Cooper
#
# @name:            "ircd::modes"
# @package:         "modes"
# @description:     "represents a sequence of IRC mode changes"
# @version:         ircd->VERSION
# @no_bless:        1
# @preserve_sym:    1
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package modes;

use warnings;
use strict;
use 5.010;
use utf8;

use Scalar::Util qw(blessed);
use utils qw(conf notice);

our ($mod, $me, $pool);

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
        if (length $param && $type == 4) {
            my $user = $over_protocol ?
                $server->uid_to_user($param): $pool->lookup_user_nick($param);
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
}

# push a mode ref
sub push_modes {
    my ($modes, $new_modes) = @_;
    push @$modes, @$new_modes;
    # TODO: simplify?
}

# the number of modes
sub count {
    my $modes = shift;
    return @$modes / 2;
}

# remove redundancies
sub simplify {
    ...
    # TODO
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
    my @modes = @$modes; # explicitly make a copy
    MODE: while (my ($name, $param) = splice @modes, 0, 2) {

        # extract the state.
        my $state = 1;
        my $first = \substr($name, 0, 1);
        if ($$first eq '-' || $$first eq '+') {
            $state  = $$first eq '+';
            $$first = '';
        }

        # $skip_checks is enabled when the modes were generated internally.
        # this is to improve efficiency when we're already certain it's valid.
        unless ($skip_checks) {

            # find the mode type.
            my $type = $me->cmode_type($name);
            if (!defined $type || $type == -1) {
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
            $server, $param, $state, $over_protocol
        ) if defined $param;

    }
    if (length $str) {
        $str = join ' ', $str, @params;
        push @strings, $str;
    }

    return $split && wantarray ? @strings : $strings[0] || '';
}

sub _stringify_cmode_parameter {
    my ($server, $param, $state, $over_protocol) = @_;

    # already a string.
    return $param if !blessed $param;

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

$mod
