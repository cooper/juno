# Copyright (c) 2014, matthew
#
# Created on mattbook
# Wed Oct 15 15:48:55 EDT 2014
# OperOnly.pm
#
# @name:            'Channel::OperOnly'
# @package:         'M::Channel::OperOnly'
# @description:     'adds oper only mode'
#
# @depends.modules: ['Base::ChannelModes', 'Base::UserNumerics']
#
# @author.name:     'Matthew Barksdale'
# @author.website:  'https://github.com/mattwb65'
#
package M::Channel::OperOnly;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

# numerics
our %user_numerics = (
    ERR_OPERONLY => [ 520, '%s :Channel is IRC Operator only' ]
);

# channel mode block
our %channel_modes = (
    oper_only => { code => \&cmode_oper_only }
);

sub init {

    # Hook on the can_join event to prevent joining a channel that is oper only
    $pool->on('user.can_join' => \&on_user_can_join,
        with_eo => 1,
        name    => 'is.oper.only'
    );

    return 1;
}

# can +O be set?
sub cmode_oper_only {
    my ($channel, $mode) = @_;
    $mode->{has_basic_status} or return;

    # servers can always set +O
    return 1 if !$mode->{source}->isa('user');

    # a user only can if he's an IRC cop
    return $mode->{source}->is_mode('ircop');

}

# can a user join the channel?
sub on_user_can_join {
    my ($user, $event, $channel) = @_;

    # we're not concerned with a -O channel
    return unless $channel->is_mode('oper_only');

    # user must be an IRC cop
    return if $user->is_mode('ircop');

    $event->{error_reply} =
        [ ERR_OPERONLY => $channel->name ];
    $event->stop('channel_oper_only');
}



$mod
