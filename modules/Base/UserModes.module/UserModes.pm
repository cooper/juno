# Copyright (c) 2016, Mitchell Cooper
#
# @name:            "Base::UserModes"
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

our ($api, $mod, $pool);

sub init {

    # register methods.
    $mod->register_module_method('register_user_mode_block') or return;

    # module unload event.
    $api->on('module.unload' => \&unload_module, 'void.user.modes');

    return 1;
}

sub register_user_mode_block {
    my ($mod, $event, %opts) = @_;

    # make sure all required options are present.
    foreach my $what (qw|name code|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        L("user mode block '$opts{name}' does not have '$what' option");
        return
    }

    # register the mode block.
    $opts{name} = lc $opts{name};
    $pool->register_user_mode_block(
        $opts{name},
        $mod->name,
        $opts{code}
    );

    L("'$opts{name}' registered");
    $mod->list_store_add('user_modes', $opts{name});
    return 1;
}

sub unload_module {
    my ($mod, $event) = @_;
    $pool->delete_user_mode_block($_, $mod->name)
      foreach $mod->list_store_items('user_modes');

    return 1;
}

$mod
