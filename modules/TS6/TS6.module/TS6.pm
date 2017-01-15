# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-Mac-mini.local
# Fri Aug  8 22:43:03 EDT 2014
# TS6.pm
#
# @name:            'TS6'
# @package:         'M::TS6'
# @description:     'TS version 6 linking protocol'
#
# @depends.modules+ qw(TS6::Utils TS6::Base TS6::Incoming)
# @depends.modules+ qw(TS6::Outgoing TS6::Registration)
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::TS6;

use warnings;
use strict;
use 5.010;

our $mod;
