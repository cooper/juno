# Copyright (c) 2012, Mitchell Cooper
# provides channel access modes.
# this module MUST be loaded globally for proper results.
package API::Module::access;

use warnings;
use strict;

use utils 'conf';

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
print "1\n";
    # view access list.
    if (!defined $mode->{param} && $mode->{source}->isa('user')) {
        # TODO
        $mode->{do_not_set} = 1;
        return 1;
    }
print "2\n";
    # for setting and unsetting -
    # split status:mask. status can be either a status name or a letter.
    my ($status, $mask) = split ':', $mode->{param}, 2;
print "  3 \n"; 
    # if either is not present, this is invalid.
    if (!defined $status || !defined $mask) {
        $mode->{do_not_set} = 1;
        return;
    }
print "4\n";
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
print "  6  \n";
    # neither worked. give up.
    if (!defined $final_status) {
        $mode->{do_not_set} = 1;
        return;
    }
print "  7  \n";
    # TODO: ensure that this user is at least the $final_status unless force or server.
    
    # set the parameter to the desired mode_name:mask format.
    $mode->{param} = $final_status.q(:).$mask;
print "8\n";
    # setting.
    if ($mode->{state}) { 
print "   9 \n";
        # this is valid; add it to the access list.
        $channel->add_to_list('access', $mode->{param},
            setby => $mode->{source}->name,
            time  => time
        );
print "   10     \n";
    }

    # unsetting.
    else {
        $channel->remove_from_list('access', $mode->{param});
    }
print "11\n";
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
    print "setting $modename to $$user{nick}\n";
    
}

$mod
