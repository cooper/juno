# Copyright (c) 2014, Mitchell Cooper
#
# @name:            "Base::OperNotices"
# @version:         ircd->VERSION
# @package:         "M::Base::OperNotices"
#
# @depends.modules: "API::Methods"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Base::OperNotices;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

sub init {
    
    # register methods.
    $mod->register_module_method('register_oper_notice') or return;
    
    # module unload event.
    $api->on('module.unload' => \&unload_module, with_evented_obj => 1) or return;
    
    return 1;
}

sub register_oper_notice {
    my ($mod, $event, %opts) = @_;
    
    # make sure all required options are present.
    foreach my $what (qw|name format|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        $mod->_log("Oper notice '$opts{name}' does not have '$what' option");
        return;
    }
    
    # register the notice.
    $pool->register_notice(
        $mod->name,
        $opts{name},
        $opts{format} // $opts{code}
    ) or return;
    
    $mod->_log("Oper notice '$opts{name}' registered");
    
    $mod->list_store_add('oper_notices', $opts{name});
    return 1;
}

sub unload_module {
    my ($mod, $event) = @_;
    $pool->delete_notice($mod->name, $_) foreach $mod->list_store_items('oper_notices');
    return 1;
}

$mod