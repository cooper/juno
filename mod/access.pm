# Copyright (c) 2012, Mitchell Cooper
# provides channel access modes
package API::Module::access;

use warnings;
use strict;

our $mod = API::Module->new(
    name        => 'access',
    version     => '0.1',
    description => 'implements channel access modes',
    requires    => ['ChannelEvents', 'ChannelModes'],
    initialize  => \&init
);
 
sub init {

    $mod->register_channel_event(
        name => 'user_joined',
        code => sub {
            print "Got user join: @_\n";
        }
    );

    return 1
}


$mod
