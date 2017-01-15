# Copyright (c) 2009-16, Mitchell Cooper
#
# @name:            "ircd::connection"
# @package:         "connection"
# @description:     "represents a connection to the server"
# @version:         ircd->VERSION
#
# @no_bless
# @preserve_sym
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package connection;

use warnings;
use strict;
use 5.010;
use parent 'Evented::Object';

use Socket::GetAddrInfo;
use Scalar::Util qw(weaken blessed looks_like_number);
use utils qw(conf v notice broadcast);

our ($api, $mod, $me, $pool);

sub init {

    # send unknown command. this is canceled by handlers.
    $pool->on('connection.message' => sub {
        my ($connection, $event, $msg) = @_;

        # ignore things that aren't a big deal.
        return if $msg->command eq 'NOTICE' && ($msg->param(0) || '') eq '*';
        return if $msg->command eq 'PONG' || $msg->command eq 'PING';
        return if looks_like_number($msg->command); # numeric

        # server command unknown.
        if ($connection->server) {
            my ($command, $name) = ($msg->command, $connection->server->name);
            my $proto = $connection->server->{link_type};
            notice(server_protocol_warning =>
                $connection->server->notice_info,
                "sent $command which is unknown by $proto; ignored"
            );
            return;
        }

        $connection->numeric(ERR_UNKNOWNCOMMAND => $msg->raw_cmd);
        return;
    }, name => 'ERR_UNKNOWNCOMMAND', priority => -200, with_eo => 1);

}

sub new {
    my ($class, $stream) = @_;
    return unless $stream && $stream->{write_handle};

    # check the IP.
    my $ip = $stream->{write_handle}->peerhost;
    $ip = utils::safe_ip(utils::embedded_ipv4($ip) || $ip);

    # create the connection object.
    bless my $connection = {
        stream        => $stream,
        ip            => $ip,
        host          => $ip,
        family        => $stream->write_handle->sockdomain,
        localport     => $stream->write_handle->sockport,
        peerport      => $stream->write_handle->peerport,
        ssl           => $stream->isa('IO::Async::SSLStream'),
        source        => $me->{sid},
        time          => time,
        last_response => time,
        last_command  => time,
        wait          => {}
    }, $class;

    # two initial waits:
    # in clients - one for NICK   (id1), one for USER (id2).
    # in servers - one for SERVER (id1), one for PASS (id2).
    $connection->reg_wait('id1');
    $connection->reg_wait('id2');

    return $connection;
}

sub handle {
    my ($connection, $data) = @_;

    # update ping information.
    $connection->{ping_in_air}   = 0;
    $connection->{last_response} = time;
    delete $connection->{warned_ping};

    # connection is being closed or empty line.
    return if $connection->{goodbye} || !length $data;

my $name = $connection->type ? $connection->type->name : '(unregistered)';
print "R[$name] $data\n";

    # create a message.
    my $msg = message->new(
        data            => $data,
        source          => $connection,
        real_message    => 1
    );
    my $cmd = $msg->command;

    # connection events.
    my @events = (
        [ message               => $msg ],
        [ "message_${cmd}"      => $msg ]
    );

    # user events.
    if (my $user = $connection->user) {
        push @events, $user->_events_for_message($msg);
        $connection->{last_command} = time
            unless $cmd eq 'PING' || $cmd eq 'PONG';
    }

    # server $PROTO_message events.
    elsif (my $server = $connection->server) {
        my $proto = $server->{link_type};
        push @events, [ $server, "${proto}_message"        => $msg ],
                      [ $server, "${proto}_message_${cmd}" => $msg ];
        $msg->{_physical_server} = $server;
    }

    # fire with safe option.
    my $fire = $connection->prepare(@events)->fire('safe');

    # an exception occurred.
    if (my $e = $fire->exception) {
        my $stopper = $fire->stopper;
        notice(exception => "Error in $cmd from $stopper: $e");
        return;
    }

    return 1;
}

# increase the wait count.
sub reg_wait {
    my ($connection, $name) = @_;
    $connection->{wait} or return;
    $connection->{wait}{$name} = 1;
}

# decrease the wait count.
sub reg_continue {
    my ($connection, $name) = @_;
    $connection->{wait} or return;
    delete $connection->{wait}{$name};
    $connection->ready unless scalar keys %{ $connection->{wait} };
}

sub ready {
    my $connection = shift;
    return if $connection->{ready} || $connection->{done};
    $connection->fire('ready');

    # must be a user.
    if (length $connection->{nick} && length $connection->{ident}) {

        # if the client limit has been reached, hang up.
        if (scalar $pool->real_local_users >= conf('limit', 'client')) {
            $connection->done('Not accepting clients');
            return;
        }

        # check if the ident is valid.
        if (!utils::validident($connection->{ident})) {
            $connection->early_reply(NOTICE =>
                ':*** Your username is invalid.');
            $connection->done("Invalid username [$$connection{ident}]");
            return;
        }

        # at this point, if a user by this nick exists, fall back to UID.
        delete $connection->{nick}
            if $pool->lookup_user_nick($connection->{nick});

        # create a new user.
        my $user = $connection->{type} = $pool->new_user(
            %$connection,
            $Evented::Object::props  => {},
            $Evented::Object::events => {}
        );

        weaken($user->{conn} = $connection);
        $connection->fire(user_ready => $user);

        # we notify other servers of the new user in $user->_new_connection
    }

    # must be a server.
    elsif (length $connection->{name}) {
        my $name = $connection->{name};

        # check if the server is linked already.
        if (my $err = server::protocol::check_new_server(
        $connection->{sid}, $connection->{name}, $me->{name})) {
            notice(connection_invalid => $connection->{ip}, 'Server exists');
            $connection->done($err);
            return;
        }

        # create a new server.
        my $server = $connection->{type} = $pool->new_server(
            %$connection,
            $Evented::Object::props  => {},
            $Evented::Object::events => {}
        );

        weaken($server->{conn} = $connection);
        $connection->fire(server_ready => $server);

        # tell other servers.
        broadcast(new_server => $server);
        $server->fire('initially_propagated');
        $server->{initially_propagated}++;
    }

    # must be an intergalactic alien.
    else {
        warn 'Connection ->ready called prematurely';
        $connection->done('Alien');
        return;
    }

    $connection->fire(ready_done => $connection->{type});
    $connection->{type}->_new_connection if $connection->user;
    return $connection->{ready} = 1;
}

# send data to the socket
sub send {
    my ($connection, @msg) = @_;

    # check that there is a writable stream.
    return unless $connection->{stream};
    return unless $connection->{stream}->write_handle;
    return if $connection->{goodbye};
    @msg = grep defined, @msg;
my $name = $connection->type ? $connection->type->name : '(unregistered)';
print "S[$name] $_\n" for @msg;
    $connection->{stream}->write("$_\r\n") foreach @msg;
}

# send data with a source
sub sendfrom {
    my ($connection, $source) = (shift, shift);
    $connection->send(map { ":$source $_" } @_);
}

# send data from ME. JELP SID if server, server name otherwise.
sub sendme {
    my $connection = shift;
    my $source =
        $connection->server ? $me->{sid} : $me->{name};
    $connection->sendfrom($source, @_);
}

sub stream { shift->{stream} }
sub sock   { shift->{stream}{write_handle} }
sub ip     { shift->{ip} }

# send a command to a possibly unregistered connection.
sub early_reply {
    my ($conn, $cmd) = (shift, shift);
    $conn->sendme("$cmd ".(defined $conn->{nick} ? $conn->{nick} : '*')." @_");
}

# end a connection. this must be foolproof.
sub done {
    my ($connection, $reason) = @_;
    return if $connection->{done}++;
    L("Closing connection from $$connection{ip}: $reason");

    # a user or server is associated with the connection.
    if ($connection->{type} && !$connection->{type}{did_quit}) {

        # share this quit with the children.
        broadcast(quit => $connection, $reason)
            if $connection->{type}{initially_propagated} &&
            !$connection->{killed};

        # tell user.pm or server.pm that the connection is closed.
        $connection->{type}->quit($reason);
        $connection->{type}{did_quit}++;

    }

    # this is safe because ->send() is safe now.
    $connection->send("ERROR :Closing Link: $$connection{host} ($reason)");

    # remove from connection the pool if it's still there.
    # if the connection has reserved a nick, release it.
    my $r = defined $connection->{nick} ?
        $pool->nick_in_use($connection->{nick}) : undef;
    $pool->release_nick($connection->{nick}) if $r && $r == $connection;
    $pool->delete_connection($connection, $reason) if $connection->{pool};

    # will close it WHEN the buffer is empty
    # (if the stream still exists).
    $connection->{stream}->close_when_empty
        if $connection->{stream} && $connection->{stream}->write_handle;

    # destroy these references, just in case.
    delete $connection->{type}{conn};
    delete $connection->{$_} foreach qw(type location server stream);

    # prevent confusion if buffer spits out more data.
    delete $connection->{ready};
    $connection->{goodbye} = 1;

    # fire done event, then
    # delete all callbacks to dispose of any possible
    # looping references within them.
    $connection->fire(done => $reason);
    $connection->clear_futures;
    $connection->delete_all_events;

    return 1;
}

# send a numeric.
sub numeric {
    my ($connection, $const, @response) = (shift, shift);

    # does not exist.
    if (!$pool->numeric($const)) {
        L("attempted to send nonexistent numeric $const");
        return;
    }

    my ($num, $val, $allowed) = @{ $pool->numeric($const) };

    # CODE reference for numeric response.
    if (ref $val eq 'CODE') {
        $allowed or L("$const only allowed for users") and return;
        @response = $val->($connection, @_);
    }

    # formatted string.
    else {
        @response = sprintf $val, @_;
    }

    # ignore registered servers.
    return if $connection->server;

    # send.
    my $nick = ($connection->user || $connection)->{nick} // '*';
    $connection->sendme("$num $nick $_") foreach @response;

    return 1;

}

# what protocols might this be, according to the port?
sub possible_protocols {
    my ($connection, @protos) = shift;
    my $port = $connection->{localport};
    return $connection->{link_type} if defined $connection->{link_type};
    #
    # maybe a protocol has been specified.
    # this means that JELP will not be permitted,
    # unless of course $proto eq 'jelp'
    #
    # if no protocol is specified, fall back
    # to JELP always for compatibility.
    #
    return ('client', $ircd::listen_protocol{$port} || 'jelp');
}

# could this connection be protocol?
sub possibly_protocol {
    my ($connection, $proto) = @_;
    return grep { $_ eq $proto } $connection->possible_protocols;
}

####################
### CAPABILITIES ###
####################

# has a capability.
sub has_cap {
    my ($obj, $flag) = (shift, lc shift);
    return unless $obj->{cap_flags};
    foreach my $f (@{ $obj->{cap_flags} }) {
        return 1 if $f eq $flag;
    }
    return;
}

# add a capability.
sub add_cap {
    my ($obj, @flags) = (shift, map { lc } @_);
    foreach my $flag (@flags) {
        next if $obj->has_cap($flag);
        push @{ $obj->{cap_flags} ||= [] }, $flag;
    }
    return 1;
}

# remove a capability.
sub remove_cap {
    my ($obj, @flags) = (shift, map { lc } @_);
    return unless $obj->{cap_flags};
    my %all_flags = map { $_ => 1 } @{ $obj->{cap_flags} };
    delete @all_flags{@flags};
    @{ $obj->{cap_flags} } = keys %all_flags;
}

###############
### FUTURES ###
###############

# add a future which represents a pending operation related to the connection.
# it will automatically be removed when it completes or fails.
sub adopt_future {
    my ($connection, $name, $f) = @_;
    $connection->{futures}{$name} = $f;
    weaken(my $weak_conn = $connection);
    $f->on_ready(sub { $weak_conn->abandon_future($name) });
}

# remove a future. this is only necessary if you want to cancel a future which
# has not finished. however, calling it with an expired one produces no error.
sub abandon_future {
    my ($connection, $name) = @_;
    my $f = delete $connection->{futures}{$name} or return;
    $f->cancel; # it may already be canceled, but that's ok
}

# clear all futures associated with a connection.
sub clear_futures {
    my $connection = shift;
    my $count = 0;
    $connection->{futures} or return $count;
    foreach my $name (keys %{ $connection->{futures} }) {
        $connection->abandon_future($name);
        $count++;
    }
    return $count;
}

#############
### TYPES ###
#############

sub type { shift->{type} }

sub user {
    my $type = shift->{type};
    blessed $type && $type->isa('user') or return;
    return $type;
}

sub server {
    my $type = shift->{type};
    blessed $type && $type->isa('server') or return;
    return $type;
}

# sub DESTROY {
#     my $connection = shift;
#     L("$connection destroyed");
# }

$mod
