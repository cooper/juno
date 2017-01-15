# Copyright (c) 2016, Mitchell Cooper
#
# @name:            "Base::UserCommands"
# @package:         "M::Base::UserCommands"
#
# @depends.modules+ "API::Methods"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Base::UserCommands;

use warnings;
use strict;
use 5.010;

use utils qw(col trim);
use Scalar::Util qw(looks_like_number);

our ($api, $mod, $pool);
my $props = $Evented::Object::props;

sub init {

    # register methods.
    $mod->register_module_method('register_user_command_new') or return;
    $mod->register_module_method('delete_user_command')       or return;

    # module events.
    $api->on('module.init' => \&module_init, '%user_commands');

    return 1;
}

###########
### NEW ###
###########

sub register_user_command_new {
    my ($mod, $event, %opts) = @_;
    $opts{description} //= $opts{desc};
    $opts{parameters}  //= $opts{params};

    # make sure all required options are present.
    foreach my $what (qw|name description code|) {
        next if defined $opts{$what};
        $opts{name} ||= 'unknown';
        L("user command $opts{name} does not have '$what' option");
        return;
    }

    # attach the event.
    my $command = uc $opts{name};
    $pool->on("user.message_$command" => \&_handle_command,
        priority    => 0, # registration commands are 500 priority
        with_eo     => 1,
        name        => $command,
        %opts,
        _caller     => $mod->{package},
    data => {
        parameters  => $opts{parameters},
        cb_code     => $opts{code}
    });

    $mod->list_store_add('user_commands', $command);
    return 1;
}

sub delete_user_command {
    my ($mod, $event, $command) = @_;
    $command = uc $command;
    # ->list_store_remove...
    $pool->delete_callback("user.message_$command", $command);
}

sub _handle_command {
    my ($user, $event, $msg) = @_;
    $event->cancel('ERR_UNKNOWNCOMMAND');
    $msg->{source} = $user;

    # figure parameters.
    my ($ok, @params);
    if (my $params = $event->callback_data('parameters')) {
        # $msg->{_event} = $event;
        ($ok, @params) = $msg->parse_params($params);
        if (!$ok) {
            my $cmd = $msg->command;
            L("Unsatisfied parameters for $cmd [$params] -> [@params]");
            return;
        }
    }

    # call actual callback.
    $event->callback_data('cb_code')->($user, $event, @params);

}

sub module_init {
    my $mod = shift;
    my %commands = $mod->get_symbol('%user_commands');
    $mod->register_user_command_new(
        name => $_,
        %{ $commands{$_} }
    ) or return foreach keys %commands;
    return 1;
}

$mod
