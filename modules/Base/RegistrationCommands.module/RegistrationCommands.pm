# Copyright (c) 2014, mitchellcooper
#
# Created on Mitchells-Mac-mini.local
# Thu Jun 19 18:05:14 EDT 2014
# RegistrationCommands.pm
#
# @name:            'Base::RegistrationCommands'
# @package:         'M::Base::RegistrationCommands'
# @description:     'provides an interface for client registration commands'
# @version:         ircd->VERSION
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Base::RegistrationCommands;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

sub init {
    
    # register methods.
    $mod->register_module_method('register_registration_command') or return;

    return 1;
}

sub register_registration_command {
    my ($mod, $event, %opts) = @_;

    # make sure all required options are present.
    foreach my $what (qw|name code cb_name|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        L("registration command '$opts{name}' does not have '$what' option");
        return;
    }
    
    # attach the callback.
    my $command = uc delete $opts{name};
    $pool->on("connection.command_$command" => $opts{code},
        name => delete $opts{cb_name},
        %opts
    );
    
}

$mod

