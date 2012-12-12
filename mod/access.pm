# Copyright (c) 2012, Mitchell Cooper
# provides channel access modes.
# this module MUST be loaded globally for proper results.
package API::Module::access;

use warnings;
use strict;

use utils 'conf', 'gv';

our $mod = API::Module->new(
    name        => 'access',
    version     => '0.2',
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
        return 1;
    }

    # for setting and unsetting -
    # split status:mask. status can be either a status name or a letter.
    my ($status, $mask) = split ':', $mode->{param}, 2;
    
    # if either is not present, this is invalid.
    if (!defined $status || !defined $mask) {
        $mode->{do_not_set} = 1;
        return;
    }

    # ensure that the status is valid.
    my $final_status;
    
    # first, let's see if this is a status name.
    if (defined $mode->{server}->cmode_letter($status)) {
        $final_status = $status;
    }

    # next, check if it is a status letter.
    else {
        $final_status = $mode->{server}->cmode_name($status);
    }
    
    # neither worked. give up.
    if (!defined $final_status) {
        $mode->{do_not_set} = 1;
        return;
    }
    
    # TODO: ensure that this user is at least the $final_status unless force or server.
    
    # set the parameter to the desired mode_name:mask format.
    $mode->{param} = $final_status.q(:).$mask;

    # setting.
    if ($mode->{state}) { 
    
        # this is valid; add it to the access list.
        $channel->add_to_list('access', $mode->{param},
            setby => $mode->{source}->name,
            time  => time
        );
        
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
    my $match;
    
    # check if there is a match, and return if there is not.
    if (
        !defined($match = $channel->list_matches('access', $user->full))  &&
        !defined($match = $channel->list_matches('access', $user->fullcloak))
    ) { return }
    
    # there is, so let's continue.
    my ($modename, $mask) = split ':', $match, 2;
    
    # find the mode letter.
    my $letter = gv('SERVER')->cmode_letter($modename);
    
    # create mode strings for user and server.
    my $sstr   = "+$letter $$user{uid}";
    my $ustr   = "+$letter $$user{nick}";
    
    # interpret the server mode string.
    # ($channel, $server, $source, $modestr, $force, $over_protocol)
    my ($user_mode_string, $server_mode_string) =
     $channel->handle_mode_string(gv('SERVER'), gv('SERVER'), $sstr, 1, 1);
    
    # inform the users of this server.
    channel::mine::send_all($channel, q(:).gv('SERVER', 'name')." MODE $$channel{name} $user_mode_string");
    
    return 1;
}

$mod
