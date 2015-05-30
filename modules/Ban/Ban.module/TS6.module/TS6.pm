# Copyright (c) 2015, mitchell cooper
#
# Created on Mitchells-MacBook-Pro.local
# Sat May 30 12:26:25 EST 2015
# TS6.pm
#
# @name:            'Ban::TS6'
# @package:         'M::Ban::TS6'
# @description:     'TS6 ban propagation'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
# depends on TS6::Base, but don't put that here.
# companion submodule loading takes care of it.
#
package M::Ban::TS6;

use warnings;
use strict;
use 5.010;

M::Ban->import(qw(
    enforce_ban         activate_ban        enforce_ban
    get_all_bans        ban_by_id
    add_or_update_ban   delete_ban_by_id
));

our ($api, $mod, $pool, $conf, $me);

###########
### TS6 ###
###########

sub init {
    return if !$api->module_loaded('TS6::Base');
    return 1;
}

$mod