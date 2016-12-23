# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-Mac-mini.local
# Fri Aug  8 22:43:11 EDT 2014
# ModeSync.pm
#
# @name:            'Channel::ModeSync'
# @package:         'M::Channel::ModeSync'
# @description:     'improves channel mode synchronization'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Channel::ModeSync;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool, $me);

sub init {
    $mod->add_companion_submodule('JELP::Base', 'JELP');
    $mod->add_companion_submodule('Base::UserCommands', 'Desync');
    $pool->on(cmodes_changed => \&cmodes_changed, 'modesync');
    return 1;
}

sub cmodes_changed {
    my (undef, $fire, $added, $removed) = @_;

    # first, locally unset the modes which were removed
    for my $channel ($pool->channels) {
        my @all_modes;
        for my $name (@$removed) {

            # get all modes of this name
            my $modes = $channel->modes_with($name);
            next if !@$modes;

            # invert the state
            for (0..$#$modes) {
                next if $_ % 2;
                $modes->[$_] = '-'.$modes->[$_];
            }

            push @all_modes, @$modes;
        }

        # commit the changes
        $channel->do_modes_local(
            $me, \@all_modes,
            1,          # force
            undef,      # not over protocol
            1,          # organize
            1           # allow unloaded modes (see issue #63)
        );
    }

    # consider: now that we're done with this mode, we could tell the pool to
    # abandon it. currently the temp code stays until overwritten. I wouldn't
    # feel good about deleting it here because then it would still remain when
    # ModeSync isn't loaded. it's not that big of a deal regardless.

    # send out a MODEREQ targeting all channels and all servers affected by
    # the new mode letters.
    my $letters = '';
    foreach (@$added) {
        my ($name, $letter, $type) = @$_;
        $letters .= $letter;
    }

    $pool->fire_command_all(modereq => $me, undef, undef, $letters)
        if length $letters;
}

# handle_modereq()
#
# $source_serv  server object source
#
# $ch_maybe     channel object or undef if it is for all channels
#
# $target       server object target or undef if it is network-wide
#
# $modes        string of mode letters in the perspective of the source server
#               or undef if requesting all modes
#
sub handle_modereq {
    my ($msg, $source_serv, $ch_maybe, $target, $modes) = @_;

    # if the modes are missing, a channel must be present.
    # this indicates a network-wide sync of all modes on a channel.
    return if !$ch_maybe && !defined $modes;

    my @forward_args = (modereq => $source_serv, $ch_maybe, $target, $modes);

    # this is not for me; forward.
    if ($target && $target != $me) {
        return $msg->forward_to($target, @forward_args);
    }

    # Safe point - we will handle this mode request.
    my @channels = $ch_maybe ? $ch_maybe : $pool->channels;
    foreach my $channel (@channels) {

        # map mode letters in the perspective of $source_serv to names.
        my @mode_names = defined $modes ?
            map $source_serv->cmode_name($_), split //, $modes :
            'inf'; # inf indicates all modes

        # construct a mode string in the perspective of $me with these modes.
        my $mode_str = $channel->mode_string_with($me, @mode_names);
        next if !length $mode_str;

        $source_serv->{location}->fire_command(moderep =>
            $me, $channel,
            defined $modes ? $source_serv : undef, # reply to the server or *
            $mode_str
        );
    }

    # unless this was addressed specifically to me, forward.
    $msg->forward(@forward_args) if !defined $target;

    return 1;
}

# handle_moderep()
#
# $source_serv  server object source
#
# $ch_maybe     channel object (required)
#
# $target       server object target or undef if it is network-wide
#
# $mode_str     mode string in the perspective of $source_serv, including
#               any possible parameters
#
sub handle_moderep {
    my ($msg, $source_serv, $channel, $target, $mode_str) = @_;

    my @forward_args = (moderep => $source_serv, $channel, $target, $mode_str);

    # this is not for me; forward.
    if ($target && $target != $me) {
        return $msg->forward_to($target, @forward_args);
    }

    # Safe point - we will handle this mode reply.

    # store the complete mode string before any changes.
    # convert the incoming mode string to the perspective of $me.
    my $old_mode_str = $channel->mode_string_all($me);
    $mode_str = $source_serv->convert_cmode_string($me, $mode_str, 1);

    # determine the difference between the old mode string and the new one.
    # note that ->cmode_string_difference() ONLY supports positive +modes.
    my $difference = $me->cmode_string_difference(
        $old_mode_str,      # all former modes
        $mode_str,          # all new modes
        1                   # do NOT remove modes missing from $mode_str
    );

    # do the mode string in perspective of $me.
    $channel->do_mode_string_local($me, $source_serv, $difference, 1, 1)
        if $difference;

    # unless this was addressed specifically to me, forward.
    $msg->forward(@forward_args) if !defined $target;

    return 1;
}

$mod
