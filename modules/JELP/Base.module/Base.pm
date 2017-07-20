# Copyright (c) 2010-16, Mitchell Cooper
#
# @name:            "JELP::Base"
# @package:         "M::JELP::Base"
#
# @depends.modules+ 'API::Methods'
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::JELP::Base;

use warnings;
use strict;
use 5.010;

use utils qw(col trim notice v set_v conf);
use Scalar::Util qw(blessed);

our ($api, $mod, $pool, $me);

# JELP versions
our $JELP_CURRENT  = '22.00';
our $JELP_MIN      = '22.00';

sub init {
    $me->{proto} = $JELP_CURRENT;
    
    # register methods.
    $mod->register_module_method('register_jelp_command'    ) or return;
    $mod->register_module_method('register_global_command'  ) or return;
    $mod->register_module_method('register_outgoing_command') or return;

    # module events.
    $api->on('module.unload' => \&on_unload, with_eo => 1);
    $api->on('module.init'   => \&module_init,
        name    => '%jelp_outgoing_commands',
        with_eo => 1
    );

    # connection events.
    $pool->on('connection.initiate_jelp_link' => \&initiate_jelp_link,
        name    => 'jelp.initiate',
        with_eo => 1
    );

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
        L("JELP command $opts{name} does not have '$what' option");
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
        _caller  => $mod->package,
    data => {
        parameters => $opts{parameters} // $opts{params},
        cb_code    => $opts{code}
    });

    # this callback forwards to other servers.
    $pool->on($e_name => \&_forward_handler,
        priority => 0,
        with_eo  => 1,
        _caller  => $mod->package,
        name     => "jelp.$command.forward",
        data     => { forward => $opts{forward} }
    ) if $opts{forward};

    $mod->list_store_add('JELP_commands', $command);
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
        my ($server, $msg, $user, @rest) = @_;
        $rest[$#rest] = ':'.$rest[$#rest] if @rest; # sentinel
        $user->handle_unsafe("$opts{name} @rest");
    };

    # pass it on to this base's ->register_jelp_command().
    return register_jelp_command($mod, $event,
        %opts,
        parameters => '-source(user) ...(opt)'
    );

}

sub register_outgoing_command {
    my ($mod, $event, %opts) = @_;

    # make sure all required options are present
    foreach my $what (qw|name code|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        L("outgoing JELP command $opts{name} does not have '$what' option");
        return;
    }

    # register to juno
    $opts{name} = lc $opts{name};
    $pool->register_outgoing_handler(
        $mod->name,
        $opts{name},
        $opts{code},
        'jelp'
    ) or return;

    D("JELP outgoing command $opts{name} registered");
    $mod->list_store_add('outgoing_commands', $opts{name});
    return 1;
}

#############################
### Initiating JELP links ###
#############################

sub initiate_jelp_link {
    my $conn = shift;
    $conn->{sent_creds} = 1;
    send_server_server($conn);
}

sub send_server_server {
    my $conn = shift;
    my $name = $conn->{name} // $conn->{want};
    if (!defined $name) {
        L('Trying to send credentials to an unknown server?');
        return;
    }
    $conn->send(sprintf 'SERVER %s %s %s %s %s :%s',
        $me->{sid},
        $me->{name},
        $JELP_CURRENT,
        v('VERSION'),
        time,
        ($me->{hidden} ? '(H) ' : '').$me->{desc}
    );
    $conn->{i_sent_server} = 1;
}

sub send_server_pass {
    my $conn = shift;
    my $name = $conn->{name} // $conn->{want};
    if (!defined $name) {
        L('Trying to send credentials to an unknown server?');
        return;
    }
    $conn->send('PASS '.conf([ 'connect', $name ], 'send_password'));
    $conn->{i_sent_pass} = 1;
}

##########################
### Handling JELP data ###
##########################

# jelp_message(%opts)
# jelp_message($msg)
sub jelp_message {
    my $msg;
    if (scalar @_ == 1 && blessed $_[0]) {
        $msg = shift;
    }
    else {
        $msg = message->new(@_);
    }

    # JELP param handlers and lookup methods.
    $msg->{objectify_function}  = \&_lookup_source;
    $msg->{stringify_function}  = sub { shift->id };
    $msg->{param_package}       = __PACKAGE__;

    return $msg;
}

sub _handle_command {
    my ($server, $event, $msg) = @_;
    $event->cancel('ERR_UNKNOWNCOMMAND');
    jelp_message($msg);

    # figure parameters.
    my ($ok, @params);
    if (my $params = $event->callback_data('parameters')) {
        # $msg->{_event} = $event;
        ($ok, @params) = $msg->parse_params($params);
        return if !$ok;
    }

    # call actual callback.
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
    my ($msg, $param, $opts) = @_;

    # make sure the source exists
    my $source = _lookup_source($msg->{source});
    return if !$source || !blessed $source;

    # make sure the type is right, if specified
    if ($opts->{server}) { $source->isa('server') or return }
    if ($opts->{user})   { $source->isa('user')   or return }

    # make sure the source is reached via the physical server
    my $from_server = $msg->{_physical_server};
    if ($source->location != $from_server) {
        notice(server_protocol_warning =>
            $from_server->notice_info,
            'sent '.$msg->command.' with source '.$source->notice_info.
            ', which is not reached via this uplink'
        );
        return;
    }

    return $source;
}

# -priv: checks if server privs are present
*_param_priv = \&server::protocol::_param_priv;

# server: match an SID.
sub _param_server {
    my ($msg, $param, $opts) = @_;
    return $pool->lookup_server($param);
}

# user: match a UID.
sub _param_user {
    my ($msg, $param, $opts) = @_;
    return $pool->lookup_user($param);
}

# channel: match a channel name.
sub _param_channel {
    my ($msg, $param, $opts) = @_;
    return $pool->lookup_channel((split ',', $param)[0])
}

# ts: match a timestamp.
sub _param_ts {
    my ($msg, $param, $opts) = @_;
    return if $param =~ m/\D/;
    return $param;
}

# lookup a JELP message source.
sub _lookup_source {
    my $id = shift;
    return $pool->lookup_server($id) || $pool->lookup_user($id);
}

#####################
### Module events ###
#####################

sub module_init {
    my ($mod, $event) = @_;

    # register outgoing commands
    my %commands = $mod->get_symbol('%jelp_outgoing_commands');
    $mod->register_outgoing_command(
        name => $_,
        code => $commands{$_}
    ) or return for keys %commands;

    # register incoming commands
    %commands = $mod->get_symbol('%jelp_incoming_commands');
    $mod->register_jelp_command(
        name => $_,
        %{ $commands{$_} }
    ) or return for keys %commands;

    return 1;
}

sub on_unload {
    my ($mod, $event) = @_;
    $pool->delete_outgoing_handler($_, 'jelp')
        foreach $mod->list_store_items('outgoing_commands');
    return 1;
}

$mod
