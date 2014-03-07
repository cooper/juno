#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper

# this file contains channely stuff for local users
# and even some servery channely stuff.
package channel::mine;

use warnings;
use strict;

use utils qw[log2 conf v];

# omg hax
# it has the same name as the one in channel.pm.
# the only difference is that this one sends
# the mode changes around
sub localjoin {
    my ($channel, $user, $time, $force) = @_;
    if ($channel->has_user($user)) {
        return unless $force;
    }
    else {
        $channel->cjoin($user, $time);
    }

    # for each user in the channel
    foreach my $usr (@{ $channel->{users} }) {
        next unless $usr->is_local;
        $usr->sendfrom($user->full, "JOIN $$channel{name}")
    }

    $user->handle("TOPIC $$channel{name}") if $channel->{topic};
    names($channel, $user);
    
    # fire after join event.
    $channel->fire_event(user_joined => $user);

    return $channel->{time};
}

# send NAMES
# this is here instead of user::handlers because it is convenient to send on channel join
sub names {
    my ($channel, $user) = @_;
    my @str;
    my $curr = 0;
    foreach my $usr (@{ $channel->{users} }) {

        # if this user is invisible, do not show him unless the querier is in a common
        # channel or has the see_invisible flag.
        if ($usr->is_mode('invisible')) {
            next if !$channel->has_user($user) && !$user->has_flag('see_invisible')
        }

        $str[$curr] .= prefix($channel, $usr).$usr->{nick}.q( );
        $curr++ if length $str[$curr] > 500
    }
    $user->numeric('RPL_NAMEREPLY', '=', $channel->{name}, $_) foreach @str;
    $user->numeric('RPL_ENDOFNAMES', $channel->{name});
}

sub modes {
    my ($channel, $user) = @_;
    $user->numeric('RPL_CHANNELMODEIS', $channel->{name}, $channel->mode_string($user->{server}));
    $user->numeric('RPL_CREATIONTIME', $channel->{name}, $channel->{time});
}

sub send_all {
    my ($channel, $what, $ignore) = @_;
    foreach my $user (@{ $channel->{users} }) {
        next unless $user->is_local;
        next if defined $ignore && $ignore == $user;
        $user->send($what);
    }
    return 1
}

sub sendfrom_all {
    my ($channel, $who, $what, $ignore) = @_;
    return send_all($channel, ":$who $what", $ignore);
}

# send a notice to every user
sub notice_all {
    my ($channel, $what, $ignore) = @_;
    foreach my $user (@{ $channel->{users} }) {
        next unless $user->is_local;
        next if defined $ignore && $ignore == $user;
        $user->send(":".v('SERVER', 'name')." NOTICE $$channel{name} :*** $what");
    }
    return 1
}

# take the lower time of a channel and unset higher time stuff
sub take_lower_time {
    my ($channel, $time) = @_;
    return $channel->{time} if $time >= $channel->{time}; # never take a time that isn't lower

    log2("locally resetting $$channel{name} time to $time");
    my $amount = $channel->{time} - $time;
    $channel->set_time($time);

    # unset topic.
    if ($channel->{topic}) {
        send_all($channel, ':'.v('SERVER', 'name')." TOPIC $$channel{name} :");
        delete $channel->{topic};
    }

    # unset all channel modes.
    # hackery: use the server mode string to reset all modes.
    # note: we can't use do_mode_string() because it would send to other servers.
    my ($u_str, $s_str) = $channel->mode_string_all(v('SERVER'));
    substr($u_str, 0, 1) = substr($s_str, 0, 1) = '-';
    sendfrom_all($channel, v('SERVER', 'name'), "MODE $$channel{name} $u_str");
    $channel->handle_mode_string(v('SERVER'), v('SERVER'), $s_str, 1, 1);
    
    notice_all($channel, "New channel time: ".scalar(localtime $time)." (set back \2$amount\2 seconds)");
    return $channel->{time};
}

# I hate this subroutine.
# returns the highest prefix a user has
sub prefix {
    my ($channel, $user) = @_;
    my $level = $channel->user_get_highest_level($user);
    if (defined $level && $ircd::channel_mode_prefixes{$level}) {
        return $ircd::channel_mode_prefixes{$level}[1]
    }
    return q..
}

# same as do_mode_string() except it never sends to other servers.
sub do_mode_string_local { _do_mode_string(1, @_) }

# handle a mode string, tell our local users, and tell other servers.
sub  do_mode_string { _do_mode_string(undef, @_) }
sub _do_mode_string {
    my ($local_only, $channel, $perspective, $source, $modestr, $force, $protocol) = @_;

    # handle the mode.
    my ($user_result, $server_result) = $channel->handle_mode_string(
        $perspective, $source, $modestr, $force, $protocol
    );
    return unless $user_result;

    # tell the channel's users.
    my $local_ustr =
        $perspective == v('SERVER') ? $user_result :
        $perspective->convert_cmode_string(v('SERVER'), $user_result);
    $channel->sendfrom_all($source->full, "MODE $$channel{name} $local_ustr");
    
    # stop here if it's not a local user or this server.
    return unless $source->is_local;
    
    # the source is our user or this server, so tell other servers.
    # ($source, $channel, $time, $perspective, $server_modestr)
    $main::pool->fire_command_all(cmode =>
        $source, $channel, $channel->{time},
        $perspective->{sid}, $server_result
    ) unless $local_only;
    
}

1
