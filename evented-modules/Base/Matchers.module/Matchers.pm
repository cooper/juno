# Copyright (c) 2014, Mitchell Cooper
#
# @name:            "Base::Matchers"
# @version:         ircd->VERSION
# @package:         "M::Base::Matchers"
#
# @depends.modules: "API::Methods"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Base::Matchers;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

sub init {
    
    # register methods.
    $mod->register_module_method('register_matcher') or return;
    
    # module unload event.
    $api->on('module.unload' => \&unload_module, with_evented_obj => 1) or return;
    
    return 1;
}

sub register_matcher {
    my ($mod, $event, %opts) = @_;
    
    # register the event.
    $pool->register_event(
        user_match => $opts{code},
        %opts
    ) or return;
    
    $mod->_log("Matcher '$opts{name}' registered");
    $mod->list_store_add('matchers', $opts{name});    
    return $opts{name};
}

sub unload_module {
    my ($mod, $event) = @_;
    $pool->delete_event(user_match => $_) foreach $mod->list_store_items('matchers');
    return 1;
}

$mod