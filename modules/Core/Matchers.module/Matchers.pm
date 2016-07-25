# Copyright (c) 2009-16, Mitchell Cooper
#
# @name:            "Core::Matchers"
# @package:         "M::Core::Matchers"
# @description:     "the core set of mask matchers"
#
# @depends.modules: "Base::Matchers"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Core::Matchers;

use warnings;
use strict;
use 5.010;

use utils qw(irc_match);

our ($api, $mod, $me);

sub init {
    $mod->register_matcher(
        name => 'standard',
        code => \&standard_matcher
    ) or return;

    $mod->register_matcher(
        name => 'oper',
        code => \&oper_matcher
    ) or return;

    return 1;
}

sub standard_matcher {
    my ($event, $user, @list) = @_;
    foreach my $mask ($user->full, $user->fullreal, $user->fullip) {
        return $event->{matched} = 1 if irc_match($mask, @list);
    }
    return;
}

sub oper_matcher {
    my ($event, $user, @list) = @_;
    return unless $user->is_mode('ircop');

    foreach my $item (@list) {

        # just check if opered.
        return $event->{matched} = 1 if $item eq '$o';

        # match a specific oper flag.
        next unless $item =~ m/^\$o:(.+)/;
        return $event->{matched} = 1 if $user->has_flag($1);

    }

    return;
}

$mod
