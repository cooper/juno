# Copyright (c) 2016, Mitchell Cooper
#
# @name:            'Channel::ModeSync::JELP'
# @package:         'M::Channel::ModeSync::JELP'
# @description:     'JELP mode synchronization'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Channel::ModeSync::JELP;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

our %jelp_incoming_commands = ();
our %jelp_outgoing_commands = ();

$mod
