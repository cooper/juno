# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "Core::UserModes"
# @version:         ircd->VERSION
# @package:         "M::Core::UserModes"
# @description:     "the core set of user modes"
#
# @depends.modules: "Base::UserModes"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Core::UserModes;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $me);

my %umodes = (
    ircop     => \&umode_ircop,
    ssl       => \&umode_never,
    invisible => \&umode_normal,
    service   => \&umode_never
);

sub init {
    $mod->register_user_mode_block(
        name => $_,
        code => $umodes{$_}
    ) || return foreach keys %umodes;
    undef %umodes;
    return 1;
}

##############
# USER MODES #
##############

sub umode_ircop {
    my ($user, $state) = @_;
    return if $state; # /never/ allow setting ircop
    
    # but always allow them to unset it.
    L("removing all flags from $$user{nick}");
    $user->{flags} = [];
    delete $user->{oper};
    
    return 1;
}

# SSL can never be set or unset without force.
# network service can never be set or unset without force.
# etc.
sub umode_never {
    return;
}

sub umode_normal {
    return 1;
}

$mod
