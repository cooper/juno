# Copyright (c) 2012, Mitchell Cooper
package API::Base::UserModes;

use warnings;
use strict;

use utils 'log2';

sub register_user_mode_block {
    my ($mod, %opts) = @_;

    # make sure all required options are present
    foreach my $what (qw|name code|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        log2("user mode block $opts{name} does not have '$what' option.");
        return
    }

    # register the mode block
    user::modes::register_block(
        $opts{name},
        $mod->{name},
        $opts{code}
    );

    $mod->{user_modes} ||= [];
    push @{$mod->{user_modes}}, $opts{name};
    return 1
}

sub unload {
    my ($class, $mod) = @_;
    log2("unloading user modes registered by $$mod{name}");

    # delete 1 at a time
    foreach my $name (@{$mod->{user_modes}}) {
        user::modes::delete_block($name, $mod->{name});
    }

    log2("done unloading modes");
    return 1
}

1
