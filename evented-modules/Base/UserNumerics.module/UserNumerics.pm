# Copyright (c) 2014, Mitchell Cooper
#
# @name:            "Base::UserNumerics"
# @version:         ircd->VERSION
# @package:         "M::Base::UserNumerics"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Base::UserNumerics;

use warnings;
use strict;
use 5.010;

my ($api, $mod);

sub init {
    
    # register methods.
    $mod->register_module_method('register_user_numeric') or return;
    
    # module unload event.
    $api->on(unload_module => \&unload_module) or return;
    
    return 1;
}

sub register_user_numeric {
    my ($mod, %opts) = @_;

    # make sure all required options are present.
    foreach my $what (qw|name number format|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        $mod->_log("user numeric $opts{name} does not have '$what' option");
        return;
    }

    # register the numeric.
    $::pool->register_numeric(
        $mod->name,
        $opts{name},
        $opts{number},
        $opts{format} // $opts{code}
    ) or return;

    $mod->_log("user numeric $opts{name} $opts{number} registered by ".$mod->name);
    $mod->list_store_add('user_numerics', $opts{name});
    return 1;
}

sub unload_module {
    my ($event, $mod) = @_;
    $::pool->delete_numeric($_) foreach $mod->list_store_items('user_numerics');
    return 1;
}

$mod