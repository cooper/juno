# Copyright (c) 2014, Mitchell Cooper
#
# @name:            "Channel::Invite"
# @package:         "M::Channel::Invite"
# @description:     "channel invitations"
#
# @depends.modules: [qw(Base::UserCommands JELP::Base Core::ChannelModes Base::UserNumerics)]
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Channel::Invite;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $me, $pool);

# INVITE user command.
our %user_commands = (INVITE => {
    code   => \&ucmd_invite,
    desc   => 'invite a user to a channel',
    params => 'user any'
});

sub init {
    
    # INVITE server command.
    $mod->register_server_command(
        name       => 'invite',
        parameters => 'user user any',
        code       => \&scmd_invite
      # forward    => handled manually
    ) or return;
    
    # modes.
    my $ccm = $api->get_module('Core::ChannelModes') or return;
    $mod->register_channel_mode_block(
        name => 'invite_only',
        code => $ccm->can('cmode_normal')
    );
    $mod->register_channel_mode_block(
        name => 'invite_except',
        code => sub { $ccm->can('cmode_banlike')->('invite_except', 'invite', @_) }
    );
    
    # invite numerics.
    $mod->register_user_numeric(
        name    => shift @$_,
        number  => shift @$_,
        format  => shift @$_
    ) or return foreach (
        [ RPL_INVITING        => 341, '%s %s'                          ],
        [ RPL_INVITELIST      => 346, '%s %s'                          ],
        [ RPL_ENDOFINVITELIST => 347, '%s :End of channel invite list' ],
        [ ERR_INVITEONLYCHAN  => 472, '%s :You must be invited'        ]
    );
    
    # outgoing INVITE.
    $mod->register_outgoing_command(
        name => 'invite',
        code => \&ocmd_invite
    ) or return;
    
    # event callbacks.
    &add_invite_callbacks;

    return 1;
}

# user INVITE command.
#
# possible results:
#
# ERR_NEEDMOREPARAMS              ERR_NOSUCHNICK
# ERR_NOTONCHANNEL                ERR_USERONCHANNEL
# ERR_CHANOPRIVSNEEDED
# RPL_INVITING                    RPL_AWAY
#
sub ucmd_invite {
    my ($user, $event, $t_user, $ch_name) = @_;
    my $channel = $pool->lookup_channel($ch_name);
    
    # channel exists.
    if ($channel) {
        $ch_name = $channel->name;
    }
    
    # channel does not exist. check if the name is valid.
    elsif (!utils::validchan($ch_name)) {
        $user->numeric(ERR_NOSUCHCHANNEL => $ch_name);
        next;
    }
    
    # fire the event to check if the user can invite.
    # note: $channel might be undef.
    my $fire = $user->fire(can_invite => $t_user, $ch_name, $channel);
      
    # the fire was stopped. user can't invite.
    return if $fire->stopper;

    # local user.
    if ($t_user->is_local) {
        $t_user->get_invited_by($user, $channel || $ch_name);
    }
    
    # remote user.
    else {
        $t_user->{location}->fire_command(invite => $user, $t_user, $ch_name);
    }
    
    # tell the source the target's being invited.
    $user->numeric(RPL_AWAY => $t_user->{nick}, $t_user->{away})
        if exists $t_user->{away};    
    $user->numeric(RPL_INVITING => $t_user->{nick}, $ch_name);
    
    return 1;
}

# server INVITE command.
sub scmd_invite {
    # :uid INVITE target ch_name
    my ($server, $event, $user, $t_user, $ch_name) = @_;

    # local user.
    if ($t_user->is_local) {
        $t_user->get_invited_by($user, $ch_name);
        return 1;
    }
    
    # forward on to next hop.
    $t_user->{location}->fire_command(invite => $user, $t_user, $ch_name);
    
    return 1;
}

# outgoing INVITE command.
sub ocmd_invite {
    my ($to_server, $user, $t_user, $ch_name) = @_;
    ":$$user{uid} INVITE $$t_user{uid} $ch_name"
}

# checks during INVITE and JOIN commands.
sub add_invite_callbacks {
    
    # delete invitation on user join.
    $pool->on('channel.user_joined' => sub {
        my ($channel, $user) = (shift->object, shift);
        delete $user->{invite_pending}{ lc $channel->name };
    }, name => 'invite.clear');
    
    # ON INVITE,
    # first, user must be in the channel if it exists.
    $pool->on('user.can_invite' => sub {
        my ($event, $t_user, $ch_name, $channel) = @_;
        my $user = $event->object;
        return unless $channel;
        
        # user's not there.
        return 1 if $channel->has_user($user);
        
        $event->stop;
        $user->numeric(ERR_NOTONCHANNEL => $ch_name);
    }, name => 'source.in.channel', priority => 30);
    
    # second, target can't be in the channel already.
    $pool->on('user.can_invite' => sub {
        my ($event, $t_user, $ch_name, $channel) = @_;
        my $user = $event->object;
        return unless $channel;
        
        # target is in there.
        return 1 unless $channel->has_user($t_user);
        
        $event->stop;
        $user->numeric(ERR_USERONCHANNEL => $t_user->{nick}, $ch_name);
    }, name => 'target.in.channel', priority => 20);
    
    # finally, user must have basic status if it's invite only.
    $pool->on('user.can_invite' => sub {
        my ($event, $t_user, $ch_name, $channel) = @_;
        my $user = $event->object;
        return unless $channel;
        
        # channel's not invite only, or the user has basic status.
        return 1 unless $channel->is_mode('invite_only');
        return 1 if $channel->user_has_basic_status($user);
        
        $event->stop;
        $user->numeric(ERR_CHANOPRIVSNEEDED => $ch_name);        
    }, name => 'has.basic.status', priority => 10);
    
     
    # ON JOIN,
    # check if the channel is invite only.
    $pool->on('user.can_join' => sub {
        my ($event, $channel) = @_;
        my $user = $event->object;
        # TODO: invite exceptions.
        return unless $channel->is_mode('invite_only');
        return if $user->{invite_pending}{ lc $channel->name };
        
        # sorry, not invited.
        $user->numeric(ERR_INVITEONLYCHAN => $channel->name);
        $event->stop;
        
    }, name => 'has.invite', priority => 20);
    
}

$mod