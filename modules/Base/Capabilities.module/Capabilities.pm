# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-Mac-mini.local
# Thu Jun 19 18:05:23 EDT 2014
# Capabilities.pm
#
# @name:            'Base::Capabilities'
# @package:         'M::Base::Capabilities'
# @description:     'provides an interface for client capabilities'
# @version:         ircd->VERSION
#
# @depends.modules: 'API::Methods'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Base::Capabilities;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

sub init {
    $mod->register_module_method('register_capability') or return;
    $api->on('module.unload' => \&unload_module, with_eo => 1) or return;
    return 1;
}

sub register_capability {
    my ($mod, $event, $cap, %opts) = @_;
    $cap = lc $cap;
    $pool->register_cap($mod->name, $cap, %opts) or return;
    $mod->list_store_add('capabilities', $cap);
    L("Registered '$cap'");
    return 1;
}

sub unload_module {
    my ($mod, $event) = @_;
    $pool->delete_cap($mod->name, $_) foreach $mod->list_store_items('capabilities');
    return 1;
}

$mod

