# Copyright (c) 2010-14, Mitchell Cooper
#
# @name:            "JELP::Base"
# @package:         "M::JELP::Base"
#
# @depends.modules: ['API::Methods', 'ircd::message']
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::JELP::Base;

use warnings;
use strict;
use 5.010;

use utils qw(col trim notice);
use Scalar::Util qw(looks_like_number blessed);

our ($api, $mod, $pool);
my $PARAM_BAD = $message::PARAM_BAD;
my $props     = $Evented::Object::props;

sub init {
    
    # register methods.
    $mod->register_module_method('register_jelp_command'    ) or return;
    $mod->register_module_method('register_global_command'  ) or return;
    $mod->register_module_method('register_outgoing_command') or return;
    
    # module unload event.
    $api->on('module.unload' => \&unload_module, with_eo => 1) or return;
    
    return 1;
}

#########################################
### Registering JELP command handlers ###
#########################################

sub register_jelp_command {
    my ($mod, $event, %opts) = @_;

    # make sure all required options are present.
    foreach my $what (qw|name code|) {
        next if defined $opts{$what};
        $opts{name} ||= 'unknown';
        L("user command $opts{name} does not have '$what' option");
        return;
    }
    
    my $command = uc $opts{name};
    my $e_name  = "server.jelp_message_$command";
    
    # attach the event.
    $pool->on($e_name => \&_handle_command,
        priority => 0, # registration commands are 500 priority
        with_eo  => 1,
        %opts,
        name     => "jelp.$command",
        _caller  => $mod->{package},
    data => {
        parameters => $opts{parameters} // $opts{params},
        cb_code    => $opts{code}
    });
    
    # this callback forwards to other servers.
    $pool->on($e_name => \&_forward_handler,
        priority => 0,
        with_eo  => 1,
        _caller  => $mod->{package},
        name     => "jelp.$command.forward",
        data     => { forward => $opts{forward} }
    ) if $opts{forward};
    
    $mod->list_store_add('jelp_commands', $command);
}

sub register_global_command {
    my ($mod, $event, %opts) = @_;
    
    # make sure all required options are present
    foreach my $what (qw|name|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        L("global command $opts{name} does not have '$what' option");
        return;
    }
    
    # create a handler that calls ->handle_unsafe().
    $opts{code} = sub {
        my ($server, $msg, $user, $rest) = @_;
        $user->handle_unsafe("$opts{name} $rest");
    };
    
    # pass it on to this base's ->register_jelp_command().
    return register_jelp_command($mod, $event,
        %opts,
        parameters => '-source(user) :rest(opt)'
    );
    
}

sub register_outgoing_command {
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
        'jelp'
    ) or return;

    L("JELP outgoing command $opts{name} registered");
    $mod->list_store_add('outgoing_commands', $opts{name});
    return 1;
}

##########################
### Handling JELP data ###
##########################

sub _handle_command {
    my ($server, $event, $msg) = @_;
    $event->cancel('ERR_UNKNOWNCOMMAND');

    # JELP param handlers and lookup method.
    $msg->{source_lookup_method} = \&_lookup_source;
    $msg->{param_package} = __PACKAGE__;
    
    # figure parameters.
    my @params;
    if (my $params = $event->callback_data('parameters')) {
        # $msg->{_event} = $event;
        @params = $msg->parse_params($params);
        return if defined $params[0] && $params[0] eq $message::PARAM_BAD;
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
    my $source = _lookup_source($msg->{source}) or return $PARAM_BAD;
    return $PARAM_BAD unless blessed $source;
    if ($opts->{server}) { $source->isa('server') or return $PARAM_BAD }
    if ($opts->{user})   { $source->isa('user')   or return $PARAM_BAD }
    push @$params, $source;
}

# server: match an SID.
sub _param_server {
    my ($msg, $param, $params, $opts) = @_;
    my $server = $pool->lookup_server($param) or return $PARAM_BAD;
    push @$params, $server;
}

# user: match a UID.
sub _param_user {
    my ($msg, $param, $params, $opts) = @_;
    my $user = $pool->lookup_user($param) or return $PARAM_BAD;
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

# lookup a JELP message source.
sub _lookup_source {
    my $id = shift;
    return $pool->lookup_server($id) || $pool->lookup_user($id);
}

#####################
### Module events ###
#####################

sub unload_module {
    my ($mod, $event) = @_;
    $pool->delete_outgoing_handler($_, 'jelp')
        foreach $mod->list_store_items('outgoing_commands');
    return 1;
}

$mod
