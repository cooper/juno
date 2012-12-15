# Copyright (c) 2012, Mitchell Cooper
package API::Base::UserCommands;

use warnings;
use strict;

use utils 'log2';

sub register_user_command {
    my ($mod, %opts) = @_;

    # make sure all required options are present
    foreach my $what (qw|name description code|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        log2("user command $opts{name} does not have '$what' option.");
        return
    }

    $mod->{user_commands} ||= [];

    # register to juno
    user::mine::register_handler(
        $mod->{name},
        $opts{name},
        $opts{parameters} || 0,
        $opts{code},
        $opts{description}
    ) or return;

    push @{$mod->{user_commands}}, $opts{name};
    return 1
}

sub unload {
    my ($class, $mod) = @_;
    log2("unloading user commands registered by $$mod{name}");
    user::mine::delete_handler($_) foreach @{$mod->{user_commands}};
    log2("done unloading commands");
    return 1
}

1
