# Copyright (c) 2014, Mitchell Cooper
#
# @name:            "Base::UserModes"
# @version:         ircd->VERSION
# @package:         "M::Base::UserModes"
#
# @depends.modules: "API::Methods"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Base::UserModes;

use warnings;
use strict;
use 5.010;

our ($api, $mod);

sub init {
    
    # register methods.
    $mod->register_module_method('register_user_mode_block') or return;
    
    # module unload event.
    $api->on(unload_module => \&unload_module) or return;
    
    return 1;
}

sub register_user_mode_block {
    my ($mod, $event, %opts) = @_;

    # make sure all required options are present.
    foreach my $what (qw|name code|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        $mod->_log("user mode block '$opts{name}' does not have '$what' option");
        return
    }

    # register the mode block.
    $::pool->register_user_mode_block(
        $opts{name},
        $mod->name,
        $opts{code}
    );

    $mod->_log("user mode block '$opts{name}' registered");
    $mod->list_store_add('user_modes', $opts{name});
    return 1;
}

sub unload_module {
    my ($event, $mod) = @_;
    $::pool->delete_user_mode_block($_, $mod->name)
      foreach $mod->list_store_items('user_modes');
    
    return 1;
}

$mod