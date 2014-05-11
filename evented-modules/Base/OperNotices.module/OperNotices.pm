# Copyright (c) 2014, Mitchell Cooper
#
# @name:            "Base::OperNotices"
# @version:         ircd->VERSION
# @package:         "M::Base::OperNotices"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Base::OperNotices;

use warnings;
use strict;
use 5.010;

our ($api, $mod);

sub init {
    
    # register methods.
    $mod->register_module_method('register_oper_notice') or return;
    
    # module unload event.
    $api->on(unload_module => \&unload_module) or return;
    
    return 1;
}

sub register_oper_notice {
    my ($mod, $event, %opts) = @_;
    
    # make sure all required options are present.
    foreach my $what (qw|name format|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        log2("oper notice '$opts{name}' does not have '$what' option.");
        return;
    }
    
    # register the notice.
    $::pool->register_notice(
        $mod->name,
        $opts{name},
        $opts{format} // $opts{code}
    ) or return;
    
    $mod->_log("oper notice '$opts{name}' registered by ".$mod->name);
    $mod->list_store_add('oper_notices', $opts{name});
    return 1;
}

sub unload_module {
    my ($event, $mod) = @_;
    $::pool->delete_notice($mod->name, $_) foreach $mod->list_store_items('oper_notices');
    return 1;
}

$mod