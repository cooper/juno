# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-Mac-mini.local
# Fri Aug  8 22:47:25 EDT 2014
# Base.pm
#
# @name:            'TS6::Base'
# @package:         'M::TS6::Base'
# @description:     'programming interface for TS6'
#
# @depends.modules+ 'API::Methods', 'TS6::Utils'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::TS6::Base;

use warnings;
use strict;
use 5.010;

use Scalar::Util  qw(blessed looks_like_number);
use M::TS6::Utils qw(obj_from_ts6 ts6_id);
use utils qw(col trim notice v conf);

our ($api, $mod, $pool, $me);

# TS versions
our $TS_CURRENT  = 6;
our $TS_MIN      = 6;

sub init {
    
    # if casemapping is not RFC1459, do not alow this
    if (conf('server', 'casemapping') ne 'rfc1459') {
        L('TS6 requires casemapping rfc1459');
        return;
    }
    
    $mod->register_module_method('register_ts6_command'         ) or return;
    $mod->register_module_method('register_outgoing_ts6_command') or return;
    $mod->register_module_method('register_ts6_capability'      ) or return;

    # module events.
    $api->on('module.unload' => \&on_unload,  with_eo => 1);
    $api->on('module.init'   => \&module_init,
        name    => '%ts6_outgoing_commands',
        with_eo => 1
    );

    # ok so this hooks onto raw incoming TS6 data to handle numerics.
    $pool->on('server.ts6_message' =>
        \&_handle_numeric_maybe,
        name     => 'ts6.numerics',
        with_eo  => 1,
        priority => 100  # do before server.ts6_message_*
    );

    # connection events
    $pool->on('connection.initiate_ts6_link' => \&initiate_ts6_link,
        name    => 'ts6.link',
        with_eo => 1
    );

    return 1;
}

############################
### Initiating TS6 links ###
############################

sub initiate_ts6_link {
    my $conn = shift;
    return if $conn->{sent_creds}++;
    send_server_pass($conn);
    send_server_server($conn);
}

sub send_server_pass {
    my $conn = shift;
    my $name = $conn->{want} // $conn->{name};

    # send PASS first.
    $conn->send(sprintf
        'PASS %s TS %d :%s',
        conf([ 'connect', $name ], 'send_password'),
        $TS_CURRENT,
        ts6_id($me)
    );

    # send CAPAB. only advertise ones that are enabled on $me.
    my @caps = grep $me->has_cap($_), get_caps();
    $conn->send("CAPAB :@caps");
}

sub send_server_server {
    my $conn = shift;

    # send server
    $conn->send(sprintf
        'SERVER %s %d :%s',
        $me->{name},
        1, # hopcount - will this ever not be one?
        $me->{desc}
    );

    # ask for a PONG to emulate end of burst
    $conn->send("PING :$$me{name}");
}

########################
### TS6 capabilities ###
########################

our %capabilities;

sub register_ts6_capability {
    my ($mod, $event, %opts) = @_;

    # no name provided
    my $cap = $opts{name};
    if (!defined $cap) {
        L("TS6 capability has to have a name");
        return;
    }

    # already have it
    $cap = uc $cap;
    if (exists $capabilities{$cap}) {
        L("TS6 capability '$cap' is already registered");
        return;
    }

    # store it.
    $capabilities{$cap} = \%opts;
    $mod->list_store_add('TS6_capabilities', $cap);

    # enable it, unless told not to.
    $me->add_cap($cap)
        unless $opts{dont_enable};

    D("TS6 capability $cap registered");
    return 1;
}

# returns all caps, even ones not enabled
sub get_caps {
    return sort keys %capabilities;
}

# returns caps that have the required flag
sub get_required_caps {
    return sort grep $capabilities{$_}{required}, keys %capabilities;
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
        _caller  => $mod->package,
    data => {
        parameters => $opts{parameters} // $opts{params},
        cb_code    => $opts{code}
    });

#    # this callback forwards to other servers.
#    $pool->on($e_name => \&_forward_handler,
#        priority => 0,
#        with_eo  => 1,
#        _caller  => $mod->package,
#        name     => "ts6.$command.forward",
#        data     => { forward => $opts{forward} }
#    ) if $opts{forward};

    $mod->list_store_add('TS6_commands', $command);
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
    $opts{name} = lc $opts{name};
    $pool->register_outgoing_handler(
        $mod->name,
        $opts{name},
        $opts{code},
        'ts6'
    ) or return;

    D("TS6 outgoing command $opts{name} registered");
    $mod->list_store_add('outgoing_TS6_commands', $opts{name});
    return 1;
}

##################################
### Handling incoming TS6 data ###
##################################

sub ts6_message {
    my $msg;
    if (scalar @_ == 1 && blessed $_[0]) {
        $msg = shift;
    }
    else {
        $msg = message->new(@_);
    }

    # TS6 param handlers and lookup methods.
    $msg->{objectify_function}  = \&obj_from_ts6;
    $msg->{stringify_function}  = \&ts6_id;
    $msg->{param_package}       = __PACKAGE__;

    return $msg;
}

sub _handle_command {
    my ($server, $event, $msg) = @_;

    # figure parameters.
    my ($ok, @params);
    if (my $params = $event->callback_data('parameters')) {
        # $msg->{_event} = $event;
        ($ok, @params) = $msg->parse_params($params);
        if (!$ok) {
            notice(server_protocol_warning =>
                $server->notice_info,
                "provided invalid parameters for TS6 command ".$msg->command
            );
            return;
        }
    }

    # call actual callback.
    $event->callback_data('cb_code')->($server, $msg, @params);

}

# this is called before the above.
sub _handle_numeric_maybe {
    my ($server, $event, $msg) = @_;
    $event->cancel('ERR_UNKNOWNCOMMAND');
    ts6_message($msg);

    # check for numeric
    return 1 if $msg->command !~ m/^\d+$/;
    my $code = M::TS6::Incoming->can('handle_numeric') or return;
    $code->($server, $msg);

    return 1;
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

    # check if the source exists
    my $source = obj_from_ts6($msg->{source}) or return;

    # check the type, if specified
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
    my $server = obj_from_ts6($param);
    return if !$server || !$server->isa('server');
    return $server;
}

# hunted: like charybdis hunt_server()
# can be a UID, SID, server mask
sub _param_hunted {
    my ($msg, $param, $opts) = @_;

    # first, find either a user or a server from SID/UID
    my $target = obj_from_ts6($param);
    $target = $target->{server} if $target && !$target->isa('server');

    # find server from mask
    # (this will return $me if $me matches)
    $target ||= $pool->lookup_server_mask($param);

    # no matches
    return if !$target || !$target->isa('server');

    return $target;
}

# user: match a UID.
sub _param_user {
    my ($msg, $param, $opts) = @_;
    my $user = obj_from_ts6($param);
    return if !$user || !$user->isa('user');
    return $user;
}

# channel: match a channel name.
sub _param_channel {
    my ($msg, $param, $opts) = @_;
    return $pool->lookup_channel((split ',', $param)[0]);
}

# ts: match a timestamp.
sub _param_ts {
    my ($msg, $param, $opts) = @_;
    return if $param =~ m/\D/;
    return $param;
}

#####################
### Module events ###
#####################

sub on_unload {
    my ($mod, $event) = @_;

    # delete outgoing commands
    $pool->delete_outgoing_handler($_, 'ts6')
        foreach $mod->list_store_items('outgoing_TS6_commands');

    # delete capabilities
    foreach my $cap ($mod->list_store_items('TS6_capabilities')) {
        delete $capabilities{$cap};
        $me->remove_cap($cap); # may or may not be enabled
    }

    return 1;
}

# a module is being initialized.
sub module_init {
    my $mod = shift;

    # add capabilities
    my %capabs = $mod->get_symbol('%ts6_capabilities');
    $mod->register_ts6_capability(
        name => $_,
        %{ $capabs{$_} }
    ) or return foreach keys %capabs;

    # add outgoing commands
    my %commands = $mod->get_symbol('%ts6_outgoing_commands');
    $mod->register_outgoing_ts6_command(
        name => $_,
        code => $commands{$_}
    ) or return foreach keys %commands;

    # add incoming commands
    %commands = $mod->get_symbol('%ts6_incoming_commands');
    $mod->register_ts6_command(
        name => $_,
        %{ $commands{$_} }
    ) or return foreach keys %commands;

    return 1;
}

$mod
