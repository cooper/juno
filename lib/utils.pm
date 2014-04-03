#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
package utils;

use warnings;
use strict;
use 5.010;
use utf8;

use Scalar::Util qw(blessed looks_like_number);

# array contains
sub contains (+$) {
    my ($array, $item) = @_;
    my $num = looks_like_number($item);
    foreach (@$array) {
        return 1 if $_ eq $item;
        return 1 if $num && looks_like_number($_) && $num == $_;
    }
    return;
}

# fetch a configuration file

sub conf {
    my ($sec, $key) = @_;
    return $::conf->get($sec, $key);
}

sub lconf { # for named blocks
    my ($block, $sec, $key) = @_;
    return $::conf->get([$block, $sec], $key);
}

# store something in the database.
sub db_store {
    my ($block, $key, $value) = @_;
    return $::conf->store($block, $key, $value);
}

# TODO: pending removal.
sub conn {
    my ($sec, $key) = @_;
    return $::conf->get(['connect', $sec], $key);
}

# log errors/warnings

sub log2 {
    return if !$::NOFORK  && defined $::PID;
    my $line = shift;
    my $sub = (caller 1)[3];
    say(time.q( ).($sub && $sub ne '(eval)' ? "$sub():" : q([).(caller)[0].q(])).q( ).$line)
}

# log and exit

sub fatal {
    my $line = shift;
    my $sub = (caller 1)[3];
    log2(($sub ? "$sub(): " : q..).$line);
    exit(shift() ? 0 : 1)
}

# remove a prefixing colon

sub col {
    my $string = shift;
    $string =~ s/^://;
    return $string
}

# find an object by it's id (server, user) or channel name
sub global_lookup {
    my $id = shift;
    my $server = $::pool->lookup_server($id);
    my $user   = $::pool->lookup_user($id);
    my $chan   = $::pool->lookup_channel($id);
    return $server // $user // $chan;
}

# remove leading and trailing whitespace

sub trim {
    my $string = shift;
    $string =~ s/\s+$//;
    $string =~ s/^\s+//;
    return $string
}

# check if a nickname is valid
sub validnick {
    my $str   = shift;
    my $limit = conf('limit', 'nick');

    # valid characters
    return if (
        length $str < 1         or
        length $str > $limit    or
        $str !~ m/^[A-Za-z_`\-^\|\\\{}\[\]][A-Za-z_0-9`\-^\|\\\{}\[\]]*$/
    );

    # success
    return 1

}

# check if a channel name is valid
sub validchan {
    my $name = shift;
    return if length $name > conf('limit', 'channelname');
    return unless $name =~ m/^#/;
    return 1
}

# match a list
sub match {
    my ($what, @list) = @_;
    return $::pool->user_match($what, @list) if blessed $what;
    return _match($what, @list);
}

# basic matcher.
sub _match {
    my ($mask, @list) = (lc shift, @_);
    return unless $mask =~ m/^(.+)\!(.+)\@(.+)$/;
    return scalar grep { $mask =~ /^$_$/ } map {
        $_ = lc quotemeta;
        s/\\\*/[\x01-\xFF]{0,}/g;
        s/\\\?/[\x01-\xFF]{1,1}/g;
        $_
    } @list;
}

sub lceq {
    lc shift eq lc shift
}

# chop a string to its limit as the config says
sub cut_to_limit {
    my ($limit, $string) = (conf('limit', shift), shift);
    return $string unless defined $limit;
    my $overflow = length($string) - $limit;
    $string = substr $string, 0, -$overflow if length $string > $limit;
    return $string
}

# encrypt something
sub crypt {
    my ($what, $crypt) = @_;

    # no do { given { 
    # compatibility XXX
    my $func = 'die';
    given ($crypt) {
        when ('sha1')   { $func = 'Digest::SHA::sha1_hex'   }
        when ('sha224') { $func = 'Digest::SHA::sha224_hex' }
        when ('sha256') { $func = 'Digest::SHA::sha256_hex' }
        when ('sha384') { $func = 'Digest::SHA::sha384_hex' }
        when ('sha512') { $func = 'Digest::SHA::sha512_hex' }
        when ('md5')    { $func = 'Digest::MD5::md5_hex'    }
    }

    $what    =~ s/'/\\'/g;
    my $eval =  "$func('$what')";

    # use eval to prevent crash if failed to load the module
    $what = eval $eval;

    if (not defined $what) {
        log2("couldn't crypt to $crypt. you probably forgot to load it. $@");
        return $what;
    }

    return $what;
}

# variables

sub v {
    my $h = \%::v;
    while (scalar @_ != 1) { $h = $h->{ +shift } }
    return $h->{ +shift };
}

sub set_v ($$) {
    $::v{ +shift } = shift
}

# send a notice to opers.
sub oper_notice {
    my ($key, @args) = @_;
    
}

# for configuration values

sub on  () { 1 }
sub off () { 0 }

sub import {
    my $package = caller;
    no strict 'refs';
    *{$package.'::'.$_} = *{__PACKAGE__.'::'.$_} foreach @_[1..$#_]
}

1
