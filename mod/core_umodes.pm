# Copyright (c) 2012, Mitchell Cooper
package ext::core_umodes;
 
use warnings;
use strict;
 
use utils 'log2';

my %umodes = (
    ircop => \&umode_ircop
);

our $mod = API::Module->new(
    name        => 'core_umodes',
    version     => '0.1',
    description => 'the core set of user commands',
    requires    => ['user_modes'],
    initialize  => \&init
);
 
sub init {

    # register user mode blocks
    $mod->register_user_mode_block(
        name => $_,
        code => $umodes{$_}
    ) || return foreach keys %umodes;

    undef %umodes;

    return 1
}

##############
# USER MODES #
##############

sub umode_ircop {
    my ($user, $state) = @_;
    return if $state; # /never/ allow setting ircop

    # but always allow them to unset it
    log2("removing all flags from $$user{nick}");
    $user->{flags} = [];
    return 1
}

$mod
