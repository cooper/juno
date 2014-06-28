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
    $mod->register_module_method('register_registration_command') or return;
    return 1;
}

sub register_registration_command {
    my ($mod, $event, %opts) = @_;
    
    # fallback to the name of the command for the callback name.
    $opts{cb_name} //= $opts{name};

    # make sure all required options are present.
    foreach my $what (qw|name code|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        L("registration command '$opts{name}' does not have '$what' option");
        return;
    }
    
    # parameter check callback.
    my $command = uc delete $opts{name};
    my $params  = $opts{parameters};
    $pool->on("connection.command_$command" => sub {
            my ($event, @args) = @_;
            say "enough for $command(@args) ", scalar(@args), " needs $params";
            
            # there are enough.
            return 1 if @args >= $params;
            
            # not enough.
            my $conn = $event->object;
            $conn->numeric(ERR_NEEDMOREPARAMS => $command);
            $event->stop;
            
        },
        name     => 'parameter.check',
        priority => 1000,
        _caller  => $mod->package
    ) or return if $params;
    
    # wrapper that prevents execution after registration.
    my $code = sub {
        my ($conn, $event) = @_;
        return if $conn->{type} && !$opts{after_reg};
        $opts{code}(@_);
        $event->stop unless $opts{continue_handlers}; # prevent later user/server handlers.
    };
    
    # attach the callback.
    my $event_name = 'connection.command_'.$command.($opts{with_data} ? '_raw' : '');
    my $result = $pool->on($event_name => $code,
        name => $opts{cb_name},
        with_evented_obj => 1,
        %opts,
        _caller => $mod->package
    ) or return;
    
    L("$command ($opts{cb_name}) registered");
    return $result;
}

$mod

