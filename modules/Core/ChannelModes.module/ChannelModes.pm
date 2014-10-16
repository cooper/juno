# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "Core::ChannelModes"
# @version:         ircd->VERSION
# @package:         "M::Core::ChannelModes"
# @description:     "the core set of channel modes"
#
# @depends.modules: ['Base::ChannelModes', 'Base::Capabilities']
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Core::ChannelModes;

use warnings;
use strict;
use 5.010;

use utils 'cols';

our ($api, $mod, $me, $pool);

my %cmodes = (
    no_ext        => \&cmode_normal,
    protect_topic => \&cmode_normal,
    moderated     => \&cmode_normal,
    ban           => sub { cmode_banlike('ban',    'ban',    @_) },
    except        => sub { cmode_banlike('except', 'except', @_) },
);

sub init {

    # register channel mode blocks
    $mod->register_channel_mode_block(
        name => $_,
        code => $cmodes{$_}
    ) || return foreach keys %cmodes;

    # register status channel modes
    register_statuses($_) or return foreach
        sort { $b <=> $a } keys %ircd::channel_mode_prefixes;
    
    # add multi-prefix capability.
    $mod->register_capability('multi-prefix');

    # add channel message restrictions.
    add_message_restrictions();
    
    undef %cmodes;
    return 1;
}

########################
# STATUS CHANNEL MODES #
########################

# status modes
sub register_statuses {
    my $level = shift;
    my $name  = $ircd::channel_mode_prefixes{$level}[2];
    $mod->register_channel_mode_block( name => $name, code => sub {
        my ($channel, $mode) = @_;
        my $source = $mode->{source};
        
        # find the target.
        my $t_user = $mode->{user_lookup}($mode->{param});

        # make sure the target user exists.
        if (!$t_user) {
            $source->numeric(ERR_NOSUCHNICK => $mode->{param})
                if $source->isa('user') && $source->is_local;
            return;
        }

        # and also make sure he is on the channel
        if (!$channel->has_user($t_user)) {
            $source->numeric(ERR_USERNOTINCHANNEL => $t_user->{nick}, $channel->name)
                if $source->isa('user') && $source->is_local;
            return;
        }

        if (!$mode->{force} && $source->is_local) {
            my $check1 = sub {

                # no basic status
                return unless $channel->user_has_basic_status($source);

                # he has a higher status..
                return 1 if $mode->{state};
                return if $channel->user_get_highest_level($source) <
                          $channel->user_get_highest_level($t_user);

                return 1;
            };
            
            my $check2 = sub {

                # the source's highest status is not enough.
                return if $channel->user_get_highest_level($source) < $level;

                return 1;
            };

            # the above test(s) failed
            if (!&$check1 || !&$check2) {
                $mode->{send_no_privs} = 1;
                return;
            }
            
        }

        # [USER RESPONSE, SERVER RESPONSE]
        $mode->{param} = [ $t_user->{nick}, $t_user->{uid} ];

        # add or remove from the list.
        my $do = $mode->{state} ? 'add_to_list' : 'remove_from_list';
        $channel->$do($name, $t_user);
        
        return 1;
        
    }) or return;

    return 1
}

#################
# CHANNEL MODES #
#################

sub cmode_normal {
    my ($channel, $mode) = @_;
    return $mode->{has_basic_status};
}

sub cmode_banlike {
    my ($list, $reply, $channel, $mode) = @_;

    # view list.
    if (!length $mode->{param} && $mode->{source}->isa('user')) {
        
        # send each list item.
        my $name = uc($list).q(LIST);
        $mode->{source}->numeric("RPL_$name" =>
            $channel->name,
            $_->[0],
            $_->[1]{setby},
            $_->[1]{time}
        ) foreach $channel->list_elements($list, 1);
        
        # end of list.
        $mode->{source}->numeric("RPL_ENDOF$name" => $channel->name);
        
        return;
    }

    # needs privs.
    if (!$mode->{has_basic_status}) {
        $mode->{send_no_privs} = 1;
        return;
    }
    
    # remove prefixing colon.
    $mode->{param} = cols($mode->{param});
    if (!length $mode->{param}) {
        $mode->{do_not_set} = 1;
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
    
    return 1;
}

sub add_message_restrictions {

    # not in channel and no external messages?
    $pool->on('user.can_message' => sub {
        my ($user, $event, $channel, $message, $type) = @_;
        
        # not internal only, or user is in channel.
        return unless $channel->is_mode('no_ext');
        return if $channel->has_user($user);
        
        # no external messages.
        $user->numeric(ERR_CANNOTSENDTOCHAN => $channel->name, 'No external messages');
        $event->stop('no_ext');
        
    }, name => 'no.external.messages', with_eo => 1, priority => 30);
    
    # moderation and no voice?
    $pool->on('user.can_message' => sub {
        my ($user, $event, $channel, $message, $type) = @_;
        
        # not moderated, or the user has proper status.
        return unless $channel->is_mode('moderated');
        return if $channel->user_get_highest_level($user) >= -2;
        
        # no external messages.
        $user->numeric(ERR_CANNOTSENDTOCHAN => $channel->name, 'Channel is moderated');
        $event->stop('moderated');
        
    }, name => 'moderated', with_eo => 1, priority => 20);

    # banned and no voice?
    $pool->on('user.can_message' => sub {
        my ($user, $event, $channel, $message, $type) = @_;

        # not moderated, or the user has proper status.
        return unless $channel->list_matches('ban', $user);
        return if $channel->user_get_highest_level($user) >= -2;
        return if $channel->list_matches('except', $user);

        $user->numeric(ERR_CANNOTSENDTOCHAN => $channel->name, 'You are banned');
        $event->stop('banned');

    }, name => 'stop.banned.users', with_eo => 1, priority => 10);
    
}

$mod
