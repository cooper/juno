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
# @depends.modules: ['API::Methods', 'TS6::Utils']
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::TS6::Base;

use warnings;
use strict;
use 5.010;

use Scalar::Util  qw(blessed looks_like_number);
use M::TS6::Utils qw(obj_from_ts6);
use utils qw(notice);

our ($api, $mod, $pool);
my $PARAM_BAD = $message::PARAM_BAD;
my $props     = $Evented::Object::props;

sub init {
    $mod->register_module_method('register_ts6_command'         ) or return;
    $mod->register_module_method('register_outgoing_ts6_command') or return;

    # module events.
    $api->on('module.unload' => \&unload_module, with_eo => 1) or return;
    $api->on('module.init'   => \&module_init,
        name    => '%ts6_outgoing_commands',
        with_eo => 1
    ) or return;

    return 1;
}

################################
### Registering TS6 commands ###
################################

sub register_ts6_command {
    my ($mod, $event, %opts) = @_;

    # make sure all required options are present.
    foreach my $what (qw|name code|) {
        next if defined $opts{$what};
        $opts{name} ||= 'unknown';
        L("TS6 command $opts{name} does not have '$what' option");
        return;
    }

    my $command = uc $opts{name};
    my $e_name  = "server.ts6_message_$command";

    # attach the event.
    $pool->on($e_name => \&_handle_command,
        priority => 0, # registration commands are 500 priority
        with_eo  => 1,
        %opts,
        name     => "ts6.$command",
        _caller  => $mod->{package},
    data => {
        parameters => $opts{parameters} // $opts{params},
        cb_code    => $opts{code}
    });

#    # this callback forwards to other servers.
#    $pool->on($e_name => \&_forward_handler,
#        priority => 0,
#        with_eo  => 1,
#        _caller  => $mod->{package},
#        name     => "ts6.$command.forward",
#        data     => { forward => $opts{forward} }
#    ) if $opts{forward};

    $mod->list_store_add('ts6_commands', $command);
}

sub register_outgoing_ts6_command {
    my ($mod, $event, %opts) = @_;

    # make sure all required options are present
    foreach my $what (qw|name code|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        L("outgoing TS6 command $opts{name} does not have '$what' option");
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

##################################
### Handling incoming TS6 data ###
##################################

sub _handle_command {
    my ($server, $event, $msg) = @_;
    $event->cancel('ERR_UNKNOWNCOMMAND');

    # TS6 param handlers and lookup method.
    $msg->{source_lookup_method} = \&obj_from_ts6;
    $msg->{param_package} = __PACKAGE__;

    # figure parameters.
    my @params;
    if (my $params = $event->callback_data('parameters')) {
        # $msg->{_event} = $event;
        @params = $msg->parse_params($params);
        if (defined $params[0] && $params[0] eq $message::PARAM_BAD) {
            notice(server_protocol_warning =>
                $server->name, $server->id,
                "provided invalid parameters for ts6 command ".$msg->command
            );
            return;
        }
    }

    # call actual callback.
    $event->{$props}{data}{allow_fantasy} = $event->callback_data('fantasy');
    $event->callback_data('cb_code')->($server, $msg, @params);

}

sub _forward_handler {
    my ($server, $event, $msg) = @_;
    my $forward = $event->callback_data('forward') or return;

    # forward to children.
    # $server is used here so that it will be ignored.
    #
    # by default, things are forwarded if I have sent MY burst.
    # forward = 2 means don't do it even if THAT server is bursting.
    #
    return if $forward == 2 && $server->{is_burst};

    $server->send_children($msg->data);
}

# -source: insert the message source.
# option server: ensure it's a server
# option user:   ensure it's a user
sub _param_source {
    my ($msg, undef, $params, $opts) = @_;
    my $source = obj_from_ts6($msg->source);
print "source: $source\n";
    # if the source isn't there, return PARAM_BAD unless it was optional.
    undef $source if !$source || !blessed $source;
    return $PARAM_BAD if !$source && !$opts->{opt};
print "past 1\n";
    # if the source is present and of the wrong type, bad param.
    if ($opts->{server}) {
        return $PARAM_BAD if $source && !$source->isa('server');
    }
print "past 2\n";
    if ($opts->{user}) {
        return $PARAM_BAD if $source && !$source->isa('user');
    }
print "past 3\n";
    # note that $source might be undef here, if it was optional.
    push @$params, $source;
}

# server: match an SID.
sub _param_server {
    my ($msg, $param, $params, $opts) = @_;
    my $server = obj_from_ts6($param);
    return $PARAM_BAD unless $server && $server->isa('server');
    push @$params, $server;
}

# user: match a UID.
sub _param_user {
    my ($msg, $param, $params, $opts) = @_;
    my $user = obj_from_ts6($param);
    return $PARAM_BAD unless $user && $user->isa('user');
    push @$params, $user;
}

# channel: match a channel name.
sub _param_channel {
    my ($msg, $param, $params, $opts) = @_;
    my $channel = $pool->lookup_channel((split ',', $param)[0]) or return $PARAM_BAD;
    push @$params, $channel;
}

# ts: match a timestamp.
sub _param_ts {
    my ($msg, $param, $params, $opts) = @_;
    looks_like_number($param) or return $PARAM_BAD;
    return $PARAM_BAD if $param < 0;
    push @$params, $param;
}

#####################
### Module events ###
#####################

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

    %commands = $mod->get_symbol('%ts6_incoming_commands');
    $mod->register_ts6_command(
        name => $_,
        %{ $commands{$_} }
    ) or return foreach keys %commands;

    return 1;
}

$mod
