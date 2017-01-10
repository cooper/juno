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

use utils qw(broadcast);

our ($api, $mod, $pool, $me);
my $cloak_func;

sub init {

    # add mode block
    $mod->register_user_mode_block(
        name => 'cloak',
        code => \&umode_cloak
    ) or return;

    # for now, only charybdis-style is supported
    my $chary = $mod->load_submodule('Charybdis') or return;
    $cloak_func = $chary->can('cloak');

    return 1;
}

sub umode_cloak {
    my ($user, $state) = @_;
    return 1 if !$user->is_local;
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

    # OK, cloaking is enabled. but it may not necessarily be applied.
    $user->{cloak_enabled} = $new_host;

    # apply the cloak - but only if the real host is active.
    if ($user->{cloak} eq $user->{host}) {
        $user->get_mask_changed($user->{ident}, $new_host);

        # tell other servers if the user has been propagated
        broadcast(chghost => $me, $user, $new_host)
            if $user->{init_complete};
    }

    return 1;
}

sub disable_cloak {
    my $user = shift;
    return unless $user->{cloak_enabled};

    # only reset the real host if the cloak is still current
    if ($user->{cloak} eq $user->{cloak_enabled}) {

        # apply the real host
        $user->get_mask_changed(@$user{'ident', 'host'});

        # tell other servers if the user has been propagated
        broadcast(chghost => $me, $user, $user->{host})
            if $user->{init_complete};

    }

    delete $user->{cloak_enabled};
    return 1;
}

$mod
