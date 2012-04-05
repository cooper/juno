#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
package utils;

use warnings;
use strict;
use feature qw[switch say];

our (%conf, %GV);

# parse a configuration file

sub parse_config {

    my ($file, $fh) = shift;
    open my $config, '<', $file or die "$!\n";
    my ($i, $block, $name, $key, $val) = 0;
    while (my $line = <$config>) {

        $i++;
        $line = trim($line);
        next unless $line;
        next if $line =~ m/^#/;

        # a block with a name
        if ($line =~ m/^\[(.*?):(.*)\]$/) {
            $block = trim($1);
            $name  = trim($2);
        }

        # a nameless block
        elsif ($line =~ m/^\[(.*)\]$/) {
            $block = 'sec';
            $name  = trim($1);
        }

        # a key and value
        elsif ($line =~ m/^(\s*)(\w*):(.*)$/ && defined $block) {
            $key = trim($2);
            $val = eval trim($3);
            die "Invalid value in $file line $i: $@" if $@;
            $conf{$block}{$name}{$key} = $val;
        }

        else {
            die "Invalid line $i of $file\n"
        }

    }

    open my $motd, conf('file', 'motd');
    if (!eof $motd) {
        while (my $line = <$motd>) {
            chomp $line;
            push @{$GV{MOTD}}, $line
        }
    }
    else {
        $GV{MOTD} = undef
    }

    return 1

}

# fetch a configuration file

sub conf {
    my ($sec, $key) = @_;
    return $conf{sec}{$sec}{$key} if exists $conf{sec}{$sec}{$key};
    return
}

sub lconf { # for named blocks
    my ($block, $sec, $key) = @_;
    return $conf{$block}{$sec}{$key} if exists $conf{$block}{$sec}{$key};
    return
}

sub conn {
    my ($sec, $key) = @_;
    return $conf{connect}{$sec}{$key} if exists $conf{connect}{$sec}{$key};
    return
}

# log errors/warnings

sub log2 {
    return if !$main::NOFORK  && defined $main::PID;
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
    my $server = server::lookup_by_id($id);
    my $user   = user::lookup_by_id($id);
    my $chan   = channel::lookup_by_name($id);
    return $server ? $server : ( $user ? $user : ( $chan ? $chan : undef ) )
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
    return if (length $str < 1 ||
      length $str > $limit ||
      ($str =~ m/^\d/) ||
      $str =~ m/[^A-Za-z-0-9-\[\]\\\`\^\|\{\}\_]/);

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

# match a host to a list
sub match {
    my ($mask, @list) = @_;
    $mask = lc $mask;
    my @aregexps;

    # convert IRC expression to Perl expression.
    @list = map {
        $_ = "\Q$_\E";  # escape all non-alphanumeric characters.
        s/\\\?/\./g;    # replace "\?" with "."
        s/\\\*/\.\*/g;  # replace "\*" with ".*"
        s/\\\@/\@/g;    # replace "\@" with "@"
        s/\\\!/\!/g;    # replace "\!" with "!"
        lc
    } @list;

    # success
    return 1 if grep { $mask =~ m/^$_$/ } @list;

    # no matches
    return

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

    return $what
}

# GV

sub gv {
    # can't use do{given{
    # compatibility with 5.12 XXX
    given (scalar @_) {
        when (1) { return $GV{+shift}                 }
        when (2) { return $GV{+shift}{+shift}         }
        when (3) { return $GV{+shift}{+shift}{+shift} }
    }
    return
}

sub set ($$) {
    my $set = shift;
    if (uc $set eq $set) {
        log2("can't set $set");
        return;
    }
    $GV{$set} = shift
}

# for configuration values

sub on  () { 1 }
sub off () { 0 }

sub import {
    my $package = caller;
    no strict 'refs';
    *{$package.'::'.$_} = *{__PACKAGE__.'::'.$_} foreach @_[1..$#_]
}

sub ircd_LOAD {
    # savor GV and conf
    ircd::reloadable(sub {
        $main::TMP_CONF = \%conf;
        $main::TMP_GV   = \%GV;
    }, sub {
        %conf = %{$main::TMP_CONF};
        %GV   = %{$main::TMP_GV};
        undef $main::TMP_CONF;
        undef $main::TMP_GV
    })
}

1
