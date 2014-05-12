# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "Core::ChannelModes"
# @version:         ircd->VERSION
# @package:         "M::Core::ChannelModes"
# @description:     "the core set of channel modes"
#
# @depends.modules: "Base::ChannelModes"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Core::ChannelModes;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $me);

my %cmodes = (
    no_ext        => \&cmode_normal,
    protect_topic => \&cmode_normal,
    moderated     => \&cmode_normal,
    ban           => sub { cmode_banlike('ban',    @_) },
    except        => sub { cmode_banlike('except', @_) },
    invite_except => sub { cmode_banlike('invite', @_) }
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
    return 1;
}

########################
# STATUS CHANNEL MODES #
########################

# status modes
sub register_statuses {
 foreach my $level (sort { $b <=> $a } keys %ircd::channel_mode_prefixes) {

    my $modename = $ircd::channel_mode_prefixes{$level}[2];
    $mod->register_channel_mode_block( name => $modename, code => sub {

        my ($channel, $mode) = @_;
        my $source = $mode->{source};
        my $target = $mode->{proto} ?
            $::pool->lookup_user($mode->{param}) :
            $::pool->lookup_user_nick($mode->{param});

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
            my $check1 = sub {

                # no basic status
                return unless $channel->user_has_basic_status($source);

                # he has a higher status..
                return 1 if $mode->{state};
                return if $channel->user_get_highest_level($source) <
                          $channel->user_get_highest_level($target);

                return 1;
            };
            
            my $check2 = sub {

                # the source's highest status is not enough.
                return if $channel->user_get_highest_level($source) < $level;

                return 1;
            };

            # the above test(s) failed
            if (!$check1->() || !$check2->()) {
                $mode->{send_no_privs} = 1;
                return
            }
        }

        # [USER RESPONSE, SERVER RESPONSE]
        push @{ $mode->{params} }, [$target->{nick}, $target->{uid}];
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
    if (!$mode->{force} && $mode->{source}->is_local &&
     !$channel->user_has_basic_status($mode->{source})) {
        $mode->{send_no_privs} = 1;
        return;
    }
    return 1;
}

sub cmode_banlike {
    my ($list, $channel, $mode) = @_;

    # view list.
    if (!defined $mode->{param} && $mode->{source}->isa('user')) {
        
        # send each list item.
        my $name = uc($list).q(LIST);
        $mode->{source}->numeric("RPL_$name" =>
            $channel->{name},
            $_->[0],
            $_->[1]{setby},
            $_->[1]{time}
        ) foreach $channel->list_elements($list, 1);
        
        # end of list.
        $mode->{source}->numeric("RPL_ENDOF$name" => $channel->{name});
        
        $mode->{do_not_set} = 1;
        return 1;
    }

    # needs privs.
    if (!$mode->{force} && $mode->{source}->isa('user')
     && !$channel->user_has_basic_status($mode->{source})) {
        $mode->{send_no_privs} = 1;
        return;
    }

    # setting.
    if ($mode->{state}) {
        $channel->add_to_list($list, $mode->{param},
            setby => $mode->{source}->name,
            time  => time
        );
    }

    # unsetting.
    else {
        $channel->remove_from_list($list, $mode->{param});
    }

    # add the parameter.
    push @{ $mode->{params} }, $mode->{param};
    
    return 1;
}

$mod
