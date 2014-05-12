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

use utils qw(log2);

our ($api, $mod, $me);

my %umodes = (
    ircop => \&umode_ircop
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
    log2("removing all flags from $$user{nick}");
    $user->{flags} = [];
    
    return 1;
}

$mod
