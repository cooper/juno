# Copyright (c) 2014, matthew
#
# Created on mattbook
# Wed Jul 2 01:25:56 EDT 2014
# Key.pm
#
# @name:            'Channel::Key'
# @package:         'M::Channel::Key'
# @description:     'adds channel key mode'
#
# @depends.modules: ['Base::ChannelModes', 'Base::UserNumerics']
#
# @author.name:     'Matthew Barksdale'
# @author.website:  'https://github.com/mattwb65'
#
package M::Channel::Key;

use warnings;
use strict;
use 5.010;

use utils qw(cut_to_limit cols);

our ($api, $mod, $pool);

# user numerics
our %user_numerics = (
    ERR_BADCHANNELKEY => [ 481, '%s :Invalid channel key'       ],
    ERR_KEYSET        => [ 467, '%s :Channel key already set'   ]
);

# channel mode block
our %channel_modes = (
    key => { code => \&cmode_key }
);

sub init {

    # Hook on the can_join event to prevent joining a channel without valid key
    $pool->on('user.can_join' => \&on_user_can_join, 'has.key');

    return 1;
}

sub cmode_key {
    my ($channel, $mode) = @_;
    $mode->{has_basic_status} or return;

    # if we're unsetting...
    if (!$mode->{setting}) {
        return unless $channel->is_mode('key');

        # if we unset without a parameter (the key),
        # we need to push the current key to params
        push @{ $mode->{params} }, $channel->mode_parameter('key')
            if !defined $mode->{param};

        $channel->unset_mode('key');
    }

    # setting.
    else {

        # sanity checking
        $mode->{param} = fix_key($mode->{param});

        # no length; don't set.
        if (!length $mode->{param}) {
            return;
        }

        $channel->set_mode('key', $mode->{param});
    }

    return 1;
}

# charybdis/blob/8fed90ba8a221642ae1f0fd450e8e580a79061fb/ircd/chmode.cc#L556
sub fix_key {
    my $in = shift;
    my $out = '';
    for (split //, $in) {
        next if /[\r\n\s:,]/;
        next if ord() < 13;
        $out .= $_;
    }
    return cut_to_limit('key', $out);
}

sub on_user_can_join {
    my ($user, $event, $channel, $key) = @_;
    return unless $channel->is_mode('key');
    return if defined $key && $channel->mode_parameter('key') eq $key;
    $event->{error_reply} = [ ERR_BADCHANNELKEY => $channel->name ];
    $event->stop;
}

$mod
