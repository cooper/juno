# Copyright (c) 2012, Mitchell Cooper
package ext::core_cmodes;
 
use warnings;
use strict;

my %cmodes = (
    no_ext        => \&cmode_normal,
    protect_topic => \&cmode_normal,
    moderated     => \&cmode_normal,
    ban           => \&cmode_ban
);

our $mod = API::Module->new(
    name        => 'core_cmodes',
    version     => '0.2',
    description => 'the core set of channel modes',
    requires    => ['ChannelModes'],
    initialize  => \&init
);
 
sub init {

    # register channel mode blocks
    $mod->register_channel_mode_block(
        name => $_,
        code => $cmodes{$_}
    ) || return foreach keys %cmodes;

    # register status channel modes
    register_statuses() or return;

    undef %cmodes;

    return 1
}


########################
# STATUS CHANNEL MODES #
########################

# status modes
sub register_statuses {
 foreach my $level (sort { $b <=> $a } keys %channel::modes::prefixes) {

    my $modename = $channel::modes::prefixes{$level}[2];
    $mod->register_channel_mode_block( name => $modename, code => sub {

        my ($channel, $mode) = @_;
        my $source = $mode->{source};
        my $target = $mode->{proto} ? user::lookup_by_id($mode->{param}) : user::lookup_by_nick($mode->{param});

        # make sure the target user exists
        if (!$target) {
            if (!$mode->{force} && $source->isa('user') && $source->is_local) {
                $source->numeric('ERR_NOSUCHNICK', $mode->{param});
            }
            return
        }

        # and also make sure he is on the channel
        if (!$channel->has_user($target)) {
            if (!$mode->{force} && $source->isa('user') && $source->is_local) {
                $source->numeric('ERR_USERNOTINCHANNEL', $target->{nick}, $channel->{name});
            }
            return
        }

        if (!$mode->{force} && $source->is_local) {
            my $check = sub {

                # no basic status
                return unless $channel->user_has_basic_status($source);

                # he has a higher status..
                return if $channel->user_get_highest_level($source) <
                          $channel->user_get_highest_level($target);

                return 1
            };

            # the above test(s) failed
            if (!$check->()) {
                $mode->{send_no_privs} = 1;
                return
            }
        }

        # add/remove status
        $channel->{status}->{$target} ||= [];
        my $statuses = $channel->{status}->{$target};

        if ($mode->{state}) {
            push @$statuses, $level
        }
        else {
            @$statuses = grep { $_ != $level } @$statuses
        }

        $channel->{status}->{$target} = $statuses;

        # [USER RESPONSE, SERVER RESPONSE]
        push @{$mode->{params}}, [$target->{nick}, $target->{uid}];
        my $do = $mode->{state} ? 'add_to_list' : 'remove_from_list';
        $channel->$do($modename, $target);
        return 1
    }) or return;
 }

    return 1
}

#################
# CHANNEL MODES #
#################

sub cmode_normal {
    my ($channel, $mode) = @_;
    if (!$mode->{force} && $mode->{source}->is_local) {
        $mode->{send_no_privs} = 1;
        return
    }
    return 1
}

sub cmode_ban {
    my ($channel, $mode) = @_;

    # view list
    if (!defined $mode->{param} && $mode->{source}->isa('user')) {
        foreach my $ban ($channel->list_elements('ban')) {
            $mode->{source}->numeric(
                RPL_BANLIST =>
                $channel->{name}, $ban->[0], $ban->[1]->{setby}, $ban->[1]->{time}
            )
        }
        $mode->{source}->numeric(RPL_ENDOFBANLIST => $channel->{name});
        $mode->{do_not_set} = 1;
        return 1
    }

    # needs privs.
    if (!$mode->{force} && $mode->{source}->is_local) {
        $mode->{send_no_privs} = 1;
        return
    }

    # setting
    if ($mode->{state}) {
        $channel->add_to_list('ban', $mode->{param},
            setby => $mode->{source}->name,
            time  => time
        )
    }

    # unsetting
    else {
        $channel->remove_from_list('ban', $mode->{param});
    }

    push @{$mode->{params}}, $mode->{param};
    return 1
}

$mod
