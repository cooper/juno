# Copyright (c) 2014, Mitchell Cooper
#
# @name:            "Base::UserCommands"
# @version:         ircd->VERSION
# @package:         "M::Base::UserCommands"
#
# @depends.modules: "API::Methods"
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

sub init {
    
    # register methods.
    $mod->register_module_method('register_user_command_new') or return;
    
    # module events.
    $api->on('module.init' => \&module_init,
        name    => '%user_commands',
        with_eo => 1
    ) or return;
        
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
        priority => 0, # registration commands are 500 priority
        with_eo  => 1,
        name     => $command,
        %opts,
        _caller  => $mod->{package},
    data => {
        parameters => $opts{parameters},
        cb_code    => $opts{code}
    });
    
}

sub _handle_command {
    my ($user, $event, $msg) = @_;
    $msg->{source} = $user;
    
    # figure parameters.
    my @params;
    if (my $params = $event->callback_data('parameters')) {
        # $msg->{_event} = $event;
        @params = $msg->parse_params($params);
        return if defined $params[0] && $params[0] eq $message::PARAM_BAD;
    }
    
    # call actual callback.
    $event->cancel('ERR_UNKNOWNCOMMAND');
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