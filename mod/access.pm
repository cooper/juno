# Copyright (c) 2012, Mitchell Cooper
# provides channel access modes.
# this module MUST be loaded globally for proper results.
package API::Module::access;

use warnings;
use strict;

our $mod = API::Module->new(
    name        => 'access',
    version     => '0.1',
    description => 'implements channel access modes',
    requires    => ['ChannelEvents', 'ChannelModes'],
    initialize  => \&init
);

sub init {

    # register access mode block.
    $mod->register_channel_mode_block(
        name => 'access',
        code => \&cmode_access
    ) or return;

    # register channel:user_joined event.
    $mod->register_channel_event(
        name => 'user_joined',
        code => \&on_user_joined,
        with_channel => 1
    ) or return;

    return 1
}

# access mode handler.
sub cmode_access {
    my ($channel, $mode) = @_;

    # view access list.
    if (!defined $mode->{param} && $mode->{source}->isa('user')) {
        # TODO
        $mode->{do_not_set} = 1;
        return 1
    }

    # setting.
    if ($mode->{state}) {
        $channel->add_to_list('access', $mode->{param},
            setby => $mode->{source}->name,
            time  => time
        )
    }

    # unsetting.
    else {
        $channel->remove_from_list('access', $mode->{param});
    }

    push @{$mode->{params}}, $mode->{param};
    return 1
}

# user joined channel event handler.
sub on_user_joined {
    my ($event, $channel, $user) = @_;
    
    # check if there is a match.
    if (
        $channel->list_matches('access', $user->full) ||
        $channel->list_matches('access', $user->fullcloak)
    ) {
        print "USER MATCHES: $$user{nick}\n";
    }
    
}

$mod
