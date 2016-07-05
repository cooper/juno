# Copyright (c) 2016, Mitchell Cooper
#
# JELP.pm
#
# @name:            'SASL::JELP'
# @package:         'M::SASL::JELP'
# @description:     'JELP SASL implementation'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
# depends on JELP::Base, but don't put that here.
# companion submodule loading takes care of it.
#
package M::SASL::JELP;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool, $me);

$mod
