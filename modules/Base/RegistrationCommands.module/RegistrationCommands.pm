# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-Mac-mini.local
# Thu Jun 19 18:05:14 EDT 2014
# RegistrationCommands.pm
#
# @name:            'Base::RegistrationCommands'
# @package:         'M::Base::RegistrationCommands'
# @description:     'provides an interface for client registration commands'
#
# @depends.modules+ 'API::Methods'
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

    # register method.
    $mod->register_module_method('register_registration_command') or return;

    # module events.
    $api->on('module.init' => \&module_init, '%registration_commands');

    return 1;
}

sub register_registration_command {
    my ($mod, $event, %opts) = @_;

    # fallback to the name of the command for the callback name.
    $opts{cb_name} //= ($opts{proto} ? "$opts{proto}." : '').$opts{name};

    # make sure all required options are present.
    foreach my $what (qw|name code|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        L("registration command '$opts{name}' does not have '$what' option");
        return;
    }

    # parameter check callback.
    my $command    = uc delete $opts{name};
    my $event_name = "connection.message_$command";
    my $params     = $opts{parameters} || $opts{params};
    $pool->on($event_name => sub {
            my ($conn, $event, $msg) = @_;

            # not the right protocol.
            return 1 if $opts{proto} && !$conn->possibly_protocol($opts{proto});

            # there are enough.
            return 1 if $msg->params >= $params;

            # not enough.
            $conn->numeric(ERR_NEEDMOREPARAMS => $command);
            $event->stop;

        },
        name     => 'parameter.check.'.$opts{cb_name},
        priority => 1000,
        with_eo  => 1,
        _caller  => $mod->package
    ) or return if $params;

    # wrapper.
    my $code = sub {
        my ($conn, $event, $msg) = @_;

        # prevent execution after registration.
        return if $conn->{type} && !$opts{after_reg};

        # only allow a specific protocol.
        return if $opts{proto} && !$conn->possibly_protocol($opts{proto});

        # arguments.
        my @args = $msg->params;
        unshift @args, $msg       if $opts{with_msg};
        unshift @args, $msg->data if $opts{with_data};

        $opts{code}($conn, $event, @args);
        $event->cancel('ERR_UNKNOWNCOMMAND');
        $event->stop unless $opts{continue_handlers}; # prevent later user/server handlers.
    };

    # attach the callback.
    my $result = $pool->on($event_name => $code,
        name     => $opts{cb_name},
        with_eo  => 1,
        priority => 500,
        %opts,
        _caller  => $mod->package
    );

    D("$command ($opts{cb_name}) registered");
    $mod->list_store_add('registration_commands', $command);
    return $result;
}

# a module is being initialized.
sub module_init {
    my $mod = shift;
    my %commands = $mod->get_symbol('%registration_commands');
    $mod->register_registration_command(
        name => $_,
        %{ $commands{$_} }
    ) or return foreach keys %commands;
    return 1;
}

$mod
