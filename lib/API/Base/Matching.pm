# Copyright (c) 2014, Mitchell Cooper
package API::Base::Matching;

use warnings;
use strict;
use 5.010;

use utils 'log2';

sub register_matcher {
    my ($mod, %opts) = @_;
    my $callb_name   = "$$mod{name}.$opts{name}";
    
    # register the event.
    $main::pool->register_event(
        user_match => $opts{code},
        %opts,
        name => $callb_name,
    ) or return;
    
    log2("$$mod{name} registered $opts{name} matcher");
    
    # store for later.
    push @{ $mod->{matchers} ||= [] }, $callb_name;
    
    return $callb_name;
}

sub _unload {
    my ($class, $mod) = @_;
    log2("unloading matchers registered by $$mod{name}");
    $main::pool->delete_event(user_match => $_) foreach @{ $mod->{matchers} };
    log2("done unloading matchers");
    return 1
}

1
