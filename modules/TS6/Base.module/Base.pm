# Copyright (c) 2014, mitchellcooper
#
# Created on Mitchells-Mac-mini.local
# Fri Aug  8 22:47:25 EDT 2014
# Base.pm
#
# @name:            'TS6::Base'
# @package:         'M::TS6::Base'
# @description:     'programming interface for TS6'
#
# @depends.modules: 'API::Methods'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::TS6::Base;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

sub init {
    $mod->register_module_method('register_outgoing_ts6_command') or return;
    
    # module events.
    $api->on('module.unload' => \&unload_module, with_eo => 1) or return;
    $api->on('module.init'   => \&module_init,
        name    => '%ts6_outgoing_commands',
        with_eo => 1
    ) or return;
    
    return 1;
}

sub register_outgoing_ts6_command {
    my ($mod, $event, %opts) = @_;

    # make sure all required options are present
    foreach my $what (qw|name code|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        L("outgoing command $opts{name} does not have '$what' option");
        return
    }

    # register to juno
    $opts{name} = uc $opts{name};
    $pool->register_outgoing_handler(
        $mod->name,
        $opts{name},
        $opts{code},
        'ts6'
    ) or return;

    L("TS6 outgoing command $opts{name} registered");
    $mod->list_store_add('outgoing_ts6_commands', $opts{name});
    return 1;
}

sub unload_module {
    my ($mod, $event) = @_;
    $pool->delete_outgoing_handler($_, 'ts6')
        foreach $mod->list_store_items('outgoing_ts6_commands');
    return 1;
}

# a module is being initialized.
sub module_init {
    my $mod = shift;
    my %commands = $mod->get_symbol('%ts6_outgoing_commands');
    $mod->register_outgoing_ts6_command(
        name => $_,
        code => $commands{$_}
    ) or return foreach keys %commands;
    return 1;
}

$mod

