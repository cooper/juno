# Copyright (c) 2012-14, Mitchell Cooper
package API::Base::Events;

use warnings;
use strict;
use feature 'switch';

use utils qw(log2 col);

our $VERSION = $ircd::VERSION;

# code: the callback.
# priority: the optional priority. (descending order)
# returns the callback name.
sub register_ircd_event {
    my ($mod, $event_name, $code, %opts) = @_;
    
    # check for name, code.
    
    $mod->{ircd_events} ||= [];
    my $callb_name = "$event_name.API.$$mod{name}";
    
    # register the event.
    $main::pool->register_event(
        $event_name      => $code,
        name             => $callb_name,
        with_evented_obj => 1,
        %opts # last so it can override
    ) or return;
    
    log2("$$mod{name} registered callback for ircd event $event_name: $callb_name");
    
    # store for later.
    push @{ $mod->{ircd_events} }, [$event_name, $callb_name];
    
    return $callb_name;
}

sub _unload {
    my ($class, $mod) = @_;
    log2("unloading ircd events registered by $$mod{name}");
    $main::pool->delete_event(@$_) foreach @{ $mod->{ircd_events} };
    log2("done unloading ircd events");
    return 1
}

1
