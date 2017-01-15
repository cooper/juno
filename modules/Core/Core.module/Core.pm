# Copyright (c) 2009-16, Mitchell Cooper
#
# @name:            "Core"
# @package:         "M::Core"
# @description:     "the core components of the ircd"
#
# @depends.modules+ qw(Core::UserModes Core::UserCommands Core::UserNumerics)
# @depends.modules+ qw(Core::ChannelModes Core::OperNotices Core::Matchers)
# @depends.modules+ qw(Core::RegistrationCommands)
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Core;

use warnings;
use strict;
use 5.010;

our $mod;
