# Copyright (c) 2016, Mitchell Cooper
#
# @name:            "Channel::Invite"
# @package:         "M::Channel::Invite"
# @description:     "channel invitations"
#
# @depends.modules: ['Base::UserCommands', 'Base::ChannelModes', 'Base::UserNumerics']
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Channel::Invite;

use warnings;
use strict;
use 5.010;

use utils qw(irc_lc conf);

our ($api, $mod, $me, $pool);

# ARE WE GOING TO ALLOW AN INVITE?
#
# Does the channel exist?
#   - No. Is channels:invite_must_exist enabled?
#       - No. Invite is OK
#       - Yes. ERR_NOSUCHCHANNEL
#   - Yes. Is the inviter in the channel?
#       - No. ERR_NOTONCHANNEL
#       - Yes. Is the invitee in the channel already?
#           - Yes. ERR_USERONCHANNEL
#           - No. Is the inviter an op in the channel?
#               - Yes. Invite is OK
#               - No. Is free invite (+g) enabled?
#                   - Yes. Invite is OK
#                   - No. Is invite only (+i) enabled?
#                       - Yes. ERR_CHANOPRIVSNEEDED
#                       - No. Is channels:only_ops_invite enabled?
#                           - No. Invite is OK
#                           - Yes. ERR_CHANOPRIVSNEEDED
my $INVITE_OK = my $JOIN_OK = 1;

# INVITE user command
our %user_commands = (INVITE => {
    code   => \&ucmd_invite,
    desc   => 'invite a user to a channel',
    params => 'user *'
});

# numerics
our %user_numerics = (
    RPL_INVITING        => [ 341, '%s %s'                           ],
    RPL_INVITELIST      => [ 346, '%s %s'                           ],
    RPL_ENDOFINVITELIST => [ 347, '%s :End of channel invite list'  ],
    ERR_INVITEONLYCHAN  => [ 472, '%s :You must be invited'         ]
);

# channel mode blocks
our %channel_modes = (
    invite_only     => { type => 'normal' },
    free_invite     => { type => 'normal' },
    invite_except   => {
        type    => 'banlike',
        list    => 'invite_except',
        reply   => 'invite'
    }
);

sub init {

    # add INVEX to RPL_ISUPPORT.
    $me->on(supported => sub {
        my (undef, undef, $supported) = @_;
        $supported->{INVEX} = $me->cmode_letter('invite_except');
    }, 'invex.supported');

    # first, user must be in the channel if it exists.
    $pool->on('user.can_invite' => \&on_can_invite_source,
        name     => 'source.in.channel',
        priority => 30,
        with_eo  => 1
    );

    # second, target can't be in the channel already.
    $pool->on('user.can_invite' => \&on_can_invite_target,
        name     => 'target.in.channel',
        priority => 20,
        with_eo  => 1
    );

    # finally, user must have basic status if it's invite only.
    $pool->on('user.can_invite' => \&on_can_invite_status,
        name     => 'has.basic.status',
        priority => 10,
        with_eo  => 1
    );

    # ON JOIN,
    # check if the channel is invite only.
    $pool->on('user.can_join' => \&on_user_can_join,
        name     => 'has.invite',
        priority => 20,
        with_eo  => 1
    );

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
        $t_user->loc_get_invited_by($user, $channel || $ch_name);
    }

    # remote user.
    else {
        $t_user->{location}->fire_command(invite => $user, $t_user, $ch_name);
    }

    # tell the source the target's being invited.
    $user->numeric(RPL_AWAY => $t_user->{nick}, $t_user->{away})
        if length $t_user->{away};
    $user->numeric(RPL_INVITING => $t_user->{nick}, $ch_name);

    return 1;
}

# user must be in the channel if it exists.
sub on_can_invite_source {
    my ($user, $event, $t_user, $ch_name, $channel) = @_;

    # channel does not exist.
    if (!$channel) {

        # invite is OK if it does not have to exist.
        return $INVITE_OK
            if !conf('channels', 'invite_must_exist');

        # invite_must_exist says to end it here.
        $event->stop;
        $user->numeric(ERR_NOSUCHCHANNEL => $channel->name);
        return;
    }

    # user is there.
    return $INVITE_OK
        if $channel->has_user($user);

    # channel exists, and user is not there.
    $event->stop;
    $user->numeric(ERR_NOTONCHANNEL => $ch_name);
}

# target can't be in the channel already.
sub on_can_invite_target {
    my ($user, $event, $t_user, $ch_name, $channel) = @_;
    return $INVITE_OK if !$channel;

    # target is not in there.
    return $INVITE_OK
        unless $channel->has_user($t_user);

    # target is in there already.
    $event->stop;
    $user->numeric(ERR_USERONCHANNEL => $t_user->{nick}, $ch_name);
}

sub on_can_invite_status {
    my ($user, $event, $t_user, $ch_name, $channel) = @_;
    return $INVITE_OK if !$channel;

    # if the user is op: +i, +g, and only_ops_invite do not apply.
    return $INVITE_OK
        if $channel->user_has_basic_status($user);

    # if free_invite is set, anyone can invite.
    return $INVITE_OK
        if $channel->is_mode('free_invite');

    # if the channel is -i, anyone can invite,
    # unless the only_ops_invite option is enabled.
    if (!$channel->is_mode('invite_only')) {
        return $INVITE_OK
            unless conf('channels', 'only_ops_invite');
    }

    # permission denied.
    $event->stop;
    $user->numeric(ERR_CHANOPRIVSNEEDED => $ch_name);
}

# check if a user can join an invite-only channel
sub on_user_can_join {
    my ($user, $event, $channel) = @_;

    # channel is not invite-only.
    return $JOIN_OK
        unless $channel->is_mode('invite_only');

    # user has been invited.
    return $JOIN_OK
        if $channel->user_has_invite($user);

    # user matches the exception list.
    return $JOIN_OK
        if $channel->list_matches('invite_except', $user);

    # sorry, not invited, no exception.
    $event->{error_reply} =
        [ ERR_INVITEONLYCHAN => $channel->name ];
    $event->stop('not_invited');
}

$mod
