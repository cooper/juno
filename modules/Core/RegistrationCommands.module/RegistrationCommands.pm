# Copyright (c) 2014, mitchellcooper
#
# Created on Mitchells-Mac-mini.local
# Thu Jun 19 19:14:26 EDT 2014
# RegistrationCommands.pm
#
# @name:            'Core::RegistrationCommands'
# @package:         'M::Core::RegistrationCommands'
# @description:     'the core set of pre-registration commands'
#
# @depends.modules: ['Base::RegistrationCommands']
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Core::RegistrationCommands;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

sub init {
    $mod->register_registration_command(
        name => 'CAP',
        code => \&rcmd_cap
    ) or return;
    return 1;
}

# handle a CAP.
sub rcmd_cap {
    my ($connection, $event, @args) = @_;
    my $subcmd = lc shift @args;
    
    # handle the subcommand.
    if (my $code = __PACKAGE__->can("cap_$subcmd")) {
        return $code->($connection, $event, @args);
    }
    
    # ERR_INVALIDCAPCMD
    $connection->early_reply(410, "$subcmd :Invalid CAP subcommand");
    return;
    
}

sub cap_ls {
    my ($connection, $event, @args) = @_;
    
}

sub cap_list {
    my ($connection, $event, @args) = @_;
    
}

$mod

