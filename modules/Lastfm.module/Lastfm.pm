# Copyright (c) 2014, mitchellcooper
#
# Created on Mitchells-Mac-mini.local
# Thu Jun 26 18:26:51 EDT 2014
# Lastfm.pm
#
# @name:            'Lastfm'
# @package:         'M::Lastfm'
# @description:     'last.fm now playing'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Lastfm;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool, $es);

sub init {
    $es = $mod->spawn_submodule('Daemon') or return;
}

sub ucmd_lastfm {
    my ($user, $event, $username) = @_;
    
    $es->do(fetch_np => $username, sub {
        # fire_then will be defined in Evented::Socket
        # sub Evented::Object::Collection::fire_then maybe
    });
    
    
    # I am unsure if this is a good idea. it's not really what I had in mind
    # originally, but it does not need to be more complex without reason.
    
}

$mod

