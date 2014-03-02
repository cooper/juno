# Copyright (c) 2012-14, Mitchell Cooper
# provides channel access modes.
# this module MUST be loaded globally for proper results.
# TODO: add support for multiple modes in a single entry.
# TODO: show list of access if no parameters are given.
package API::Module::Access;

use warnings;
use strict;

use utils qw(conf v match);

our $mod = API::Module->new(
    name        => 'Access',
    version     => '1.0',
    description => 'implements channel access modes',
    requires    => ['Events', 'ChannelModes'],
    initialize  => \&init
);

sub init {

    # register access mode block.
    $mod->register_channel_mode_block(
        name => 'access',
        code => \&cmode_access
    ) or return;

    # register channel:user_joined event.
    $mod->register_ircd_event('channel.user_joined' => \&on_user_joined) or return;

    # register UP command.
    $mod->register_user_command(
        name        => 'up',
        description => 'grant yourself with your access privileges',
        parameters  => 'channel(inchan)',
        code        => \&cmd_up
    ) or return;

    return 1
}

sub cmd_up {
    my ($user, $data, $channel) = @_;
    
    # pretend join.
    on_user_joined(undef, $channel, $user);
    
}

# access mode handler.
sub cmode_access {
    my ($channel, $mode) = @_;

    # view access list.
    if (!defined $mode->{param} && $mode->{source}->isa('user') && $mode->{state}) {
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
    
    # ensure that this user is at least the $final_status unless force or server.
    # TODO: should we always allow over-protocol?
    if (!$mode->{force} && $mode->{source}->isa('user')) {
        my $level1 = $channel->user_get_highest_level($mode->{source});
        my $level2 = conf('prefixes', $final_status)->[2];
        # FIXME: major issues if improper configuration values are not array references.
        
        # the level being set is higher than the level of the setter.
        if ($level2 > $level1) {
            $mode->{send_no_privs} = 1;
            $mode->{do_not_set}    = 1;
            return;
        }
        
    }
    
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
    my ($channel, $event, $user) = @_;
    my (@matches, @letters);
    
    # look for matches.
    return unless exists $channel->{modes}{access};
    foreach my $mask ($channel->list_elements('access')) {
        my $realmask = $mask;
        $realmask = (split ':', $mask, 2)[1] if $mask =~ m/^(.+?):(.+)$/;
        
        # found a match.
        push @matches, $mask if match($user, $realmask);
        
    }
    
    # continue through matches.
    my %done;
    foreach my $match (@matches) {
        
        # there is match, so let's continue.
        my ($modename, $mask) = split ':', $match, 2;
        
        # find the mode letter.
        my $letter = v('SERVER')->cmode_letter($modename);
        
        # user already has this status.
        next if $done{$letter};
        next if $channel->user_is($user, $modename);
        
        push @letters, $letter;
        $done{$letter} = 1;
    }
    
    return 1 unless scalar @letters;
    
    # create list of letters.
    my $letters = join('', @letters);
    
    # create mode strings for user and server.
    my $uids  = ($user->{uid} .q( )) x length $letters;
    my $nicks = ($user->{nick}.q( )) x length $letters;
    my $sstr  = "+$letters $uids";
    my $ustr  = "+$letters $nicks";
    
    # interpret the server mode string.
    # ($channel, $server, $source, $modestr, $force, $over_protocol)
    my ($user_mode_string, $server_mode_string) =
     $channel->handle_mode_string(v('SERVER'), v('SERVER'), $sstr, 1, 1);
    
    # inform the users of this server.
    $channel->send_all(q(:).v('SERVER', 'name')." MODE $$channel{name} $user_mode_string");
    
    return 1;
}

$mod
