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
use utils qw(col);

our ($api, $mod, $pool);

sub init {
    $mod->register_registration_command(
        name       => 'CAP',
        code       => \&rcmd_cap,
        parameters => 1
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

# CAP LIST: display the server's available caps.
sub cap_ls {
    my ($connection, $event, @args) = @_;
    my @flags = $pool->capabilities;
    $connection->early_reply(CAP => "LS :@flags");
}

# CAP LIST: display the client's active caps.
sub cap_list {
    my ($connection, $event, @args) = @_;
    my @flags = @{ $connection->{cap_flags} || [] };
    $connection->early_reply(CAP => "LIST :@flags");
}

# CAP REQ: client requests a capability.
sub cap_req {
    my ($connection, $event, @args) = @_;
    
    # first REQ - postpone registration.
    if (!$connection->{received_req}) {
        $connection->{received_req} = 1;
        $connection->reg_wait;
    }
    
    # handle each capability.
    my (@add, @remove, $nak);
    foreach my $item (@args) {
        $item = col($item);
        my ($m, $flag) = ($item =~ m/^([-]?)(.+)$/);
                
        # requesting to remove it.
        if ($m eq '-') {
            push @remove, $flag;
        }
        
        # no such flag.
        if (!$pool->has_cap($flag)) {
            $nak = 1;
            last;
        }
        
        # it was removed.
        next if $m eq '-';
        
        # adding.
        push @add, $flag;
        
    }
    
    # sending NAK; don't change anything.
    my $cmd = 'ACK';
    if ($nak) {
        $cmd = 'NAK';
        @add = @remove = ();
    }
    
    $connection->add_cap(@add);
    $connection->remove_cap(@remove);
    $connection->early_reply(CAP => "$cmd :@args");
}

# CAP CLEAR: remove all active capabilities from a client.
sub cap_clear {
    my ($connection, $event, @args) = @_;
    my @flags = @{ $connection->{cap_flags} || [] };
    $connection->remove_cap(@flags);
    @flags = map { "-$_" } @flags;
    $connection->early_reply(CAP => "ACK :@flags");
}

# CAP END: capability negotiation complete.
sub cap_end {
    my ($connection, $event) = @_;
    return if $connection->{type};
    $connection->reg_continue if delete $connection->{received_req};
}

$mod

