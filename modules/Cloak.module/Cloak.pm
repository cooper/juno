# Copyright (c) 2016, Mitchell Cooper
#
#
# @name:            'Cloak'
# @package:         'M::Cloak'
# @description:     'hostname cloaking'
#
# @depends.modules: ['Base::UserModes']
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Cloak;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool, $me);

my $cloak_func = \&cloak;

sub init {
    $mod->register_user_mode_block(
        name => 'cloak',
        code => \&umode_cloak
    ) or return;
    return 1;
}

sub umode_cloak {
    my ($user, $state) = @_;
    return enable_cloak($user) if $state;
    return disable_cloak($user);
}

sub enable_cloak {
    my $user = shift;
    return if length $user->{cloak_enabled};

    # crypt
    my $new_host = $cloak_func->($user->{host}, $user);

    # just an extra check to make sure something's changed
    if (!length $new_host || $new_host eq $user->{cloak}) {
        return;
    }

    # apply the cloak
    $user->get_mask_changed($user->{ident}, $new_host);
    $user->{cloak_enabled} = $new_host;

    # tell other servers if the user has been propagated
    $pool->fire_command_all(chghost => $me, $user, $new_host)
        if $user->{init_complete};

    return 1;
}

sub disable_cloak {
    my $user = shift;
    return unless $user->{cloak_enabled};

    # only reset the real host if the cloak is still current
    if ($user->{cloak} eq $user->{cloak_enabled}) {

        # apply the real host
        $user->get_mask_changed(@$user{'ident', 'host'});
        delete $user->{cloak_enabled};

        # tell other servers if the user has been propagated
        $pool->fire_command_all(chghost => $me, $user, $user->{host})
            if $user->{init_complete};

    }

    return 1;
}

sub cloak {
    my ($host, $user) = @_;
    return crypt($host, 'secure!');
}

$mod
