# Copyright (c) 2014, Mitchell Cooper
#
# @name:            "Base::UserNumerics"
# @version:         ircd->VERSION
# @package:         "M::Base::UserNumerics"
#
# @depends.modules: "API::Methods"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Base::UserNumerics;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

sub init {
    
    # register methods.
    $mod->register_module_method('register_user_numeric') or return;
    
    # module unload event.
    $api->on('module.unload' => \&unload_module, with_eo => 1) or return;
    
    # module initialization.
    $api->on('module.init' => \&module_init,
        name    => '%user_numerics',
        with_eo => 1
    ) or return;
    
    return 1;
}

sub register_user_numeric {
    my ($mod, $event, %opts) = @_;

    # make sure all required options are present.
    foreach my $what (qw|name number format|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        L("User numeric $opts{name} does not have '$what' option");
        return;
    }

    # register the numeric.
    $pool->register_numeric(
        $mod->name,
        $opts{name},
        $opts{number},
        $opts{format} // $opts{code},
        $opts{allow_conn} || $opts{allow_connection}
    ) or return;

    L("$opts{name} $opts{number} registered");
    $mod->list_store_add('user_numerics', $opts{name});
    return 1;
}

sub unload_module {
    my ($mod, $event) = @_;
    $pool->delete_numeric($mod->name, $_) foreach $mod->list_store_items('user_numerics');
    return 1;
}

# a module is being initialized.
sub module_init {
    my $mod = shift;
    my %numerics = $mod->get_symbol('%user_numerics');
    $mod->register_user_numeric(
        name    => $_,
        number  => $numerics{$_}[0],
        format  => $numerics{$_}[1]
    ) || return foreach keys %numerics;
    return 1;
}


$mod