# Copyright (c) 2012-14, Mitchell Cooper
#
# @name:            "Base::ChannelModes"
# @version:         ircd->VERSION
# @package:         "M::Base::ChannelModes"
#
# @depends.modules: "API::Methods"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Base::ChannelModes;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

sub init {
    
    # register methods.
    $mod->register_module_method('register_channel_mode_block') or return;
    
    # module unload event.
    $api->on('module.unload' => \&unload_module, with_evented_obj => 1) or return;
    
    return 1;
}

sub register_channel_mode_block {
    my ($mod, $event, %opts) = @_;
    
    # make sure all required options are present.
    foreach my $what (qw|name code|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        L("Channel mode block $opts{name} does not have '$what' option");
        return;
    }
    
    # register the mode block.
    $opts{name} = lc $opts{name};
    $pool->register_channel_mode_block(
        $opts{name},
        $mod->name,
        $opts{code}
    );
    
    L("'$opts{name}' registered");
    $mod->list_store_add('channel_modes', $opts{name});
}

sub unload_module {
    my ($mod, $event) = @_;
    # delete all mode blocks.
    $pool->delete_channel_mode_block($_, $mod->name)
      foreach $mod->list_store_items('channel_modes');
    
    return 1;
}

$mod