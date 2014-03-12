# Copyright (c) 2012, Mitchell Cooper
package API::Base::ChannelModes;

use warnings;
use strict;

use utils 'log2';

our $VERSION = $ircd::VERSION;

sub register_channel_mode_block {
    my ($mod, %opts) = @_;

    # make sure all required options are present
    foreach my $what (qw|name code|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        log2("channel mode block $opts{name} does not have '$what' option.");
        return
    }

    # register the mode block
    $main::pool->register_channel_mode_block(
        $opts{name},
        $mod->{name},
        $opts{code}
    );

    $mod->{channel_modes} ||= [];
    push @{ $mod->{channel_modes} }, $opts{name};
    return 1
}

sub _unload {
    my ($class, $mod) = @_;
    log2("unloading channel modes registered by $$mod{name}");

    # delete 1 at a time
    foreach my $name (@{ $mod->{channel_modes} }) {
        $main::pool->delete_channel_mode_block($name, $mod->{name});
    }

    log2("done unloading modes");
    return 1
}

1
