# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "Core"
# @version:         ircd->VERSION
# @package:         "M::Core"
# @description:     "the core components of the ircd"
#
# @depends.modules: [qw(Core::UserModes Core::UserCommands Core::UserNumerics Core::ChannelModes Core::OperNotices Core::Matchers)]
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Core;

use warnings;
use strict;
use 5.010;

our $mod;