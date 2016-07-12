# Copyright (c) 2009-16, Mitchell Cooper
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

use utils qw(notice);

our ($api, $mod, $me);

my %umodes = (

    # settable by any user
    invisible   => \&umode_normal,
    wallops     => \&umode_normal,
    deaf        => \&umode_normal,
    bot         => \&umode_normal,

    # requires the power of a greater being
    admin       => \&umode_never,
    ssl         => \&umode_never,
    service     => \&umode_never,
    registered  => \&umode_never,

    # special rules
    ircop       => \&umode_ircop

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

    # but always allow unsetting
    notice(user_deopered => $user->notice_info);
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
