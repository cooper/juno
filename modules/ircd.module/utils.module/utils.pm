# Copyright (c) 2009-16, Mitchell Cooper
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

# remove all prefixing colons.
sub cols {
    my $string = shift;
    $string =~ s/^:*//;
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

# return list without string duplicates.
sub simplify {
    my %h = map { $_ => 1 } @_;
    keys %h;
}

# convert array or hash ref to list or empty list if not ref.
sub ref_to_list {
    my $ref = shift;
    return defined $ref ? ($ref) : () if !ref $ref;
    if (ref $ref eq 'ARRAY') { return @$ref }
    if (ref $ref eq 'HASH')  { return %$ref }
    return ();
}

sub safe_arrayref {
    my $ref = shift;
    return [] if !ref $ref || ref $ref ne 'ARRAY';
    return $ref;
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

sub irc_lc {
    my ($name, $map) = @_;
    $map ||= conf('server', 'casemapping');

    # rfc1459
    # A-Z   -> a-z
    # []    -> {}
    # \     -> |
    # ~     -> ^
    if ($map eq 'rfc1459') {
        $name =~ tr/A-Z[]\\~/a-z{}|^/;
    }

    # "strict" rfc1459
    # A-Z   -> a-z
    # []    -> {}
    # \     -> |
    elsif ($map eq 'strict-rfc1459') {
        $name =~ tr/A-Z[]\\/a-z{}|/;
    }

    # unicode lc rules
    if ($map eq 'utf8') {
        use utf8;
        $name = lc $name;
    }

    # default is ASCII
    else {
        $name =~ tr/A-Z/a-z/;
    }

    return $name;
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

# convert mask to pretty
sub pretty_mask_parts {
    my $str = shift;
    return unless defined $str;
    $str =~ s/\*{2,}/*/g;
    my (@mask, $r);

    # no nickname provided, but ident and hostname were
    if ($str !~ /!/ and $str =~ /@/) {
        $r       = $str;
        $mask[0] = '*';
    }

    # nickname and possibly ident provided
    else {
        ($mask[0], $r) = split /!/, $str, 2;
    }

    # anything left over is ident and hostname
    if (defined $r) {
        $r =~ s/!//g;
        @mask[1..2] = split /@/, $r, 2;
    }

    # if there's a dot in the nickname and
    # no hostname or ident, assume it's a hostname
    if ($mask[0] =~ m/\./ && !length $mask[1] && !length $mask[2]) {
        @mask = (undef, undef, $mask[0]);
    }

    # replace empty spots with *
    $mask[2] =~ s/@//g if defined $mask[2];
    for (0..2) { $mask[$_] = '*' unless defined $mask[$_] }

    return @mask;
}

sub pretty_mask {
    my @mask = pretty_mask(@_);
    return "$mask[0]!$mask[1]\@$mask[2]";
}

# format time for IRC.
sub irc_time {
    my $time = shift;
    return POSIX::strftime('%a %b %d %Y at %H:%M:%S %Z', localtime $time);
}

# IRC-safe IP address.
sub safe_ip {
    my $ip = shift;
    return $ip unless substr($ip, 0, 1) eq ':';
    return "0$ip";
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

# alphabet notation to integer.
sub a2n {
    my $n = 0;
    $n = $n * 26 + $_ for map { ord($_) & 0x1F } split //, shift;
    return $n;
}

# integer to alphabet notation.
sub n2a {
    my $n = shift;
    my @a;
    while ($n > 0) {
        my $rem = ($n - 1) % 26;
        unshift @a, $rem || 0;
        $n = $n / 26;
        $n = int($n) == $n ? $n - 1 : int($n);
    }
    return join '', map chr(ord('a') + $_), @a;
}

# arrayref of keys and values -> hash.
sub keys_values {
    my ($keys, $values) = @_;
    return unless ref $keys eq 'ARRAY' && ref $values eq 'ARRAY';
    my %hash;
    while (@$keys || @$values) {
        my ($key, $value) = (shift @$keys, shift @$values);
        $hash{$key} = $value;
    }
    return (%hash);
}

my %multi = (
    'y' => 31536000,    # year
    'M' => 2592000,     # month (30 days)
    'd' => 86400,       # day
    'h' => 3600,        # hour
    'm' => 60,          # minute
    's' => 1            # second
);

# string -> seconds
sub string_to_seconds {
    my $str = shift;
    my ($current, $total) = ('', 0);
    for my $char (split //, $str) {

        # multiplier.
        if ($multi{$char}) {
            return undef unless length $current; # no number

            $total += $current * $multi{$char};
            $current = '';
            next;
        }

        return undef if $char =~ m/\D/;
        $current .= $char;
    }

    # number with no multiplier is seconds.
    return $total || (length $current ? $current : 0);

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
    my @caller = ref $_[0] eq 'ARRAY' ? @{+shift} : caller 1;

    # if the first arg is not a user object, inject undef.
    if ($_[0] && (!blessed $_[0] || !$_[0]->isa('user'))) {
        unshift @_, undef;
    }

    # fire it.
    my ($amnt, $key, $str) = $::pool->fire_oper_notice(@_);
    return if !$key || !$str;

    # log it.
    return if !$api || !ircd->can('_L');
    my $obj = $api->package_to_module($caller[0]) || $ircd::mod or return;
    ircd::_L($obj, \@caller, "$key: $str");

    return $str;
}

# send a notice that propagates.
sub gnotice {
    return unless pool->can('fire_command_all') && $::pool;

    # first arg might be a user.
    my ($to_user, $flag);
    my $first = $_[0];
    if ($first && blessed $first && $first->isa('user')) {
        $to_user = shift;
    }
    $flag = shift;

    my $message = notice([caller 1], $to_user, $flag, @_);
    $::pool->fire_command_all(snotice => $flag, $message, $to_user);
    return $message;
}

# convert a string list of channels to channel objects.
# e.g. "#a,#b,#c"
# nonexistent channels are ignored
sub channel_str_to_list {
    my $ch_name_list = shift;
    my @names = split /,/, $ch_name_list;
    if (my $limit = shift) {
        @names = @names[0 .. $limit - 1];
    }
    return grep defined, map $::pool->lookup_channel($_), @names;
}

# if the provided address is IPv4 already, returns it.
# if it's IPv6, checks for an embeded IPv6 address and
# returns either that or the unaltered IPv6 address.
sub embedded_ipv4 {
    my $ipvq = shift;
    my $ipv4 = (split /:/, $ipvq)[-1] or return $ipvq;
    return $ipv4 if valid_ipv4($ipv4);
    return $ipvq;
}

# check if IP address string looks like ipv6.
# fancy, right?
sub looks_like_ipv6 {
    my $ip = shift;
    return $ip =~ m/:/;
}

# check if an IP address string is valid IPv4.
sub valid_ipv4 {
    my $ip = shift;

    # only digits and dots allowed
    return unless $ip =~ m/^[\d\.]+$/;

    # quads
    my $n = () = $ip =~ /\./g;
    return if $n != 3;

    # must not have empty sections, start or end with dot
    return if $ip =~ m/(^\.)|\.\.|(\.$)/;

    # check each quad
    foreach (split /\./, $ip) {
        return if $_ < 0;
        return if $_ > 256;
    }

    return 1;
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
