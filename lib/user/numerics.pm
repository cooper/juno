#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
# TODO: there should be a way for code refs to be registered like this
# then we should be able to put this stuff in the UserNumerics core module.
package user::numerics;

use warnings;
use strict;

use utils qw/conf log2/;


sub rpl_isupport {
    my $user = shift;

    my %things = (
        PREFIX      => &prefix,
        CHANTYPES   => '#',                         # TODO
        CHANMODES   => &chanmodes,
        MODES       => 0,                           # TODO
        CHANLIMIT   => '#:0',                       # TODO
        NICKLEN     => conf('limit', 'nick'),
        MAXLIST     => 'beIZ:0',                    # TODO
        NETWORK     => conf('network', 'name'),
        EXCEPTS     => 'e',                         # TODO
        INVEX       => 'I',                         # TODO
        CASEMAPPING => 'rfc1459',
        TOPICLEN    => conf('limit', 'topic'),
        KICKLEN     => conf('limit', 'kickmsg'),
        CHANNELLEN  => conf('limit', 'channelname'),
        RFC2812     => 'YES',
        FNC         => 'YES',
        AWAYLEN     => conf('limit', 'away'),
        MAXTARGETS  => 1                            # TODO
      # ELIST                                       # TODO
    );

    my @lines = '';
    my $curr = 0;

    while (my ($param, $val) = each %things) {
        if (length $lines[$curr] > 135) {
            $curr++;
            $lines[$curr] = ''
        }
        $lines[$curr] .= ($val eq 'YES' ? $param : $param.q(=).$val).q( )
    }

    $user->numeric('RPL_ISUPPORT', $_) foreach @lines
}

# CHANMODES in RPL_ISUPPORT
sub chanmodes {
    #   normal (0)
    #   parameter (1)
    #   parameter_set (2)
    #   list (3)
    #   status (4)
    my (%m, @a);
    @a[3, 1, 2, 0] = (q.., q.., q.., q..);
    foreach my $name ($ircd::conf->keys_of_block(['modes', 'channel'])) {
        my ($type, $letter) = @{conf(['modes', 'channel'], $name)};
        $m{$type} = [] unless $m{$type};
        push @{$m{$type}}, $letter
    }

    # alphabetize
    foreach my $type (keys %m) {
        my @alphabetized = sort { $a cmp $b } @{$m{$type}};
        $a[$type] = join '', @alphabetized
    }

    return "$a[3],$a[1],$a[2],$a[0]"
}

# PREFIX in RPL_ISUPPORT
sub prefix {
    my ($modestr, $prefixes) = (q.., q..);
    foreach my $level (sort { $b <=> $a } keys %channel::modes::prefixes) {
        $modestr  .= $channel::modes::prefixes{$level}[0];
        $prefixes .= $channel::modes::prefixes{$level}[1];
    }
    return "($modestr)$prefixes"
}

1

