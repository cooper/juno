# Copyright (c) 2012, Mitchell Cooper
package API::Base::ChannelEvents;

use warnings;
use strict;
use feature 'switch';

use utils qw(log2 col register_event delete_event);

# register_channel_event(%opts)
# name: name of event, excluding the channel prefix.
# code: the callback.
# with_channel: optional call with channel as second argument.
# priority: the optional priority. (descending order)
# returns the callback name.
sub register_channel_event {
    my ($mod, %opts) = @_;
    
    # check for name, code.
    
    $mod->{channel_events} ||= [];
    
    # event name and callback name.
    my $event_name = "channel:$opts{name}";
    my $callb_name = "$event_name.API.$$mod{name}";
    
    # register the event.
    register_event($event_name => sub {
        my ($event, $channel) = (shift, shift);
        
        # make sure the module still exists.
        return unless scalar grep { $_ == $mod } @{$main::API->{loaded}};
        
        # create argument list, taking with_channel into account.
        my @arglist = ($event, @_);
        @arglist    = ($event, $channel, @_) if $opts{with_channel};
        
        # call it.
        $opts{code}(@arglist);
        
    }, name => $callb_name);
    
    # store for later.
    push @{$mod->{channel_events}}, [$event_name, $callb_name];
    
    return $callb_name;
}

sub unload {
    my ($class, $mod) = @_;
    log2("unloading channel events registered by $$mod{name}");
    delete_event(@$_) foreach @{$mod->{channel_events}};
    log2("done unloading channel events");
    return 1
}

1
