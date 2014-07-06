# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "ircd::utils"
# @package:         "utils"
# @description:     "provides convenience and utility functions"
# @version:         ircd->VERSION
# @no_bless:        1
# @preserve_sym:    1
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package utils;

use warnings;
use strict;
use 5.010;
use utf8;

use Scalar::Util 'blessed';

our ($api, $mod);

# fetch a configuration file.
sub conf { $ircd::conf->get(@_) }

# store something in the database.
sub db_store {
    my ($block, $key, $value) = @_;
    return $ircd::conf->store($block, $key, $value);
}

# log and exit.
sub fatal {
    my $line = shift;
    my $sub = (caller 1)[3];
    L(($sub ? "$sub(): " : q..).$line);
    exit(shift() ? 0 : 1);
}

# remove a prefixing colon.
sub col {
    my $string = shift;
    my $ref = \substr($string, 0, 1);
    $$ref = '' if $$ref eq ':';
    return $string;
}

# find an object by it's id (server, user) or channel name.
sub global_lookup {
    return unless pool->can('lookup_server');
    my $id = shift;
    my $server = $::pool->lookup_server($id);
    my $user   = $::pool->lookup_user($id);
    my $chan   = $::pool->lookup_channel($id);
    return $server || $user || $chan;
}

# remove leading and trailing whitespace.
sub trim {
    my $string = shift;
    $string =~ s/\s+$//;
    $string =~ s/^\s+//;
    return $string;
}

# check if a nickname is valid.
sub validnick {
    my $str   = shift;
    my $limit = conf('limit', 'nick');

    # too long, too short, or invalid characters.
    return if (
        length $str < 1         or
        length $str > $limit    or
        $str !~ m/^[A-Za-z_`\-^\|\\\{}\[\]][A-Za-z_0-9`\-^\|\\\{}\[\]]*$/
    );

    return 1;
}

# check if an ident is valid.
sub validident {
    # see: https://github.com/atheme/charybdis/blob/55abcbb20aeabcf2e878a9c65c9697210dd10079/src/match.c
    # the (?#) is a regex comment that fixes syntax highlighting screwups caused by ` :)
    return shift() =~ m/^(~?)([A-Za-z0-9]{1})([A-Za-z0-9\-\.\[\\\]\^_(?#)`\{\|\}~]*)$/;
}

# check if a channel name is valid.
sub validchan {
    my $name = shift;
    return if length $name > conf('limit', 'channelname');
    return unless substr($name, 0, 1) eq '#';
    return 1;
}

# match a list.
sub match {
    my ($what, @list) = @_;
    return $::pool->user_match($what, @list) if $::pool && blessed $what;
    return irc_match($what, @list);
}

# basic matcher.
sub irc_match {
    my ($what, @list) = (lc shift, @_);
    return scalar grep { $what =~ /^$_$/ } map {
        $_ = lc quotemeta;
        s/\\\*/[\x01-\xFF]{0,}/g;
        s/\\\?/[\x01-\xFF]{1,1}/g;
        $_
    } @list;
}

# format time for IRC.
sub irc_time {
    my $time = shift;
    return POSIX::strftime('%a %b %d %Y at %H:%M:%S %Z', localtime $time);
}

# chop a string to its limit as the config says.
sub cut_to_limit {
    my ($limit, $string) = (conf('limit', shift), shift);
    return $string unless defined $limit;
    my $overflow = length($string) - $limit;
    $string = substr $string, 0, -$overflow if length $string > $limit;
    return $string;
}

our %crypts = (
    sha1   => [ 'Digest::SHA', 'sha1_hex'   ],
    sha224 => [ 'Digest::SHA', 'sha224_hex' ],
    sha256 => [ 'Digest::SHA', 'sha256_hex' ],
    sha384 => [ 'Digest::SHA', 'sha384_hex' ],
    sha512 => [ 'Digest::SHA', 'sha512_hex' ],
    md5    => [ 'Digest::MD5', 'md5_hex'    ],
    none   => [ __PACKAGE__,   '_none'      ]
);

sub _none { shift }

# encrypt something.
sub crypt {
    my ($what, $crypt, $salt) = @_;
    $salt //= '';
    
    # no such crypt.
    if (!defined $crypts{$crypt}) {
        L("Crypt error: Unknown crypt $crypt!");
        return;
    }
    
    # load if it isn't loaded.
    my ($package, $function) = @{ $crypts{$crypt} };
    ircd::load_or_reload($package, 0);
    
    # call the function.
    if (my $code = $package->can($function)) {
        return $code->($salt.$what);
    }

    # couldn't find the function.
    L("Crypt error: $package cannot $function!");
    return;
    
}

# fetch variable.
sub v {
    my $h = \%::v;
    while (scalar @_ != 1) { $h = $h->{ +shift } }
    return $h->{ +shift };
}

# set variable.
sub set_v ($$) {
    my ($key, $value) = @_;
    $::v{$key} = $value;
}

# send a notice to opers.
sub notice {
    return unless pool->can('fire_oper_notice') && $::pool;
    my @caller = caller 1;

    # fire it.
    my ($amnt, $key, $str) = $::pool->fire_oper_notice(@_);
    return if !$key || !$str;
    
    # log it.
    my $obj = $api->package_to_module($caller[0]) or return;
    return unless ircd->can('_L');
    ircd::_L($obj, \@caller, "$key: $str");
    
    return $str;
}

sub import {
    my $this_package = shift;
    my $package = caller;
    no strict 'refs';
    *{$package.'::'.$_} = *{$this_package.'::'.$_} foreach @_;
}

# utils must have its own L() because it is loaded before anything else.
sub L { ircd::_L($mod, [caller 1], @_) if ircd->can('_L') }

$mod