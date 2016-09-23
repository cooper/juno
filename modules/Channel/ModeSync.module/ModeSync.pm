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
    $pool->on(cmodes_changed => \&cmodes_changed, 'modesync');
}

sub cmodes_changed {
    my (undef, $fire, $added, $removed) = @_;

    # first, locally unset the modes which were removed
    for my $channel ($pool->channels) {
        my @all_modes;
        for my $mode_type (@$removed) {

            # get all modes of this type
            my $modes = $channel->get_modes($mode_type);
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

}

$mod
