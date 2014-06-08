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
    # no longer used - this is simply a callback that will be automatically deleted.
    # $api->on('module.unload' => \&unload_module, with_evented_obj => 1) or return;
    
    return 1;
}

sub register_matcher {
    my ($mod, $event, %opts) = @_;
    
    # register the event.
    $opts{name} = lc $opts{name};
    $pool->register_event(
        user_match => $opts{code},
        %opts
    ) or return;
    
    L("Matcher '$opts{name}' registered");
    $mod->list_store_add('matchers', $opts{name});    
    return $opts{name};
}

$mod