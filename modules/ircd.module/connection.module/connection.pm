# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "ircd::connection"
# @package:         "connection"
# @description:     "represents a connection to the server"
# @version:         ircd->VERSION
# @no_bless:        1
# @preserve_sym:    1
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
use Net::IP qw(ip_get_embedded_ipv4);
use Scalar::Util qw(weaken blessed looks_like_number);
use utils qw(conf v notice);

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
                $name, $connection->server->id,
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
    print "stream : $stream\n";
    return unless $stream && $stream->{write_handle};

    # check the IP.
    my $ip = $stream->{write_handle}->peerhost;
    $ip = ip_get_embedded_ipv4($ip) || $ip;
    $ip = utils::safe_ip($ip);

    # create the connection object.
    bless my $connection = {
        stream        => $stream,
        ip            => $ip,
        host          => $ip,
        localport     => $stream->{write_handle}->sockport,
        peerport      => $stream->{write_handle}->peerport,
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
printf "GET(%s): %s\n", $connection->type ? $connection->type->name : 'unregistered', $data;
    # update ping information.
    $connection->{ping_in_air}   = 0;
    $connection->{last_response} = time;

    # connection is being closed.
    return if $connection->{goodbye};

    return unless length $data;
    my $msg  = message->new(data => $data, real_message => 1, source => $connection);
    my $cmd  = $msg->command;
    my @args = $msg->params;

    # connection events.
    my @events = (

    #   .---------------.
    #   | legacy events |
    #   '---------------'

        [ raw                   => $data, @args ],
        [ "command_${cmd}_raw"  => $data, @args ],
        [ "command_$cmd"        =>        @args ],

    #   .------------.
    #   | new events |
    #   '------------'

        [ message               => $msg ],
        [ "message_${cmd}"      => $msg ]

    );

    # user events.
    if (my $user = $connection->user) {
        push @events, $user->events_for_message($msg);
        $connection->{last_command} = time unless $cmd eq 'PING' || $cmd eq 'PONG';
    }

    # if it's a server, add the $PROTO_message events.
    elsif (my $server = $connection->server) {
        my $proto = $server->{link_type};
        push @events, [ $server, "${proto}_message"        => $msg ],
                      [ $server, "${proto}_message_${cmd}" => $msg ];
        $msg->{_physical_server} = $server;
    }

    # fire with safe option.
    my $fire = $connection->prepare(@events)->fire('safe');

    # 'safe' with exception.
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
    return if $connection->{ready};
    $connection->fire_event('ready');

    # must be a user.
    if (length $connection->{nick} && length $connection->{ident}) {

        # if the client limit has been reached, hang up.
        if (scalar $pool->local_users >= conf('limit', 'client')) {
            $connection->done('Not accepting clients');
            return;
        }

        # check if the ident is valid.
        if (!utils::validident($connection->{ident})) {
            $connection->early_reply(NOTICE => ':*** Your username is invalid.');
            $connection->done("Invalid username [$$connection{ident}]");
            return;
        }

        $connection->{server}   =
        $connection->{location} = $me;
        $connection->{cloak}  //= $connection->{host};

        # at this point, if a user by this nick exists...
        if ($pool->lookup_user_nick($connection->{nick})) {
            delete $connection->{nick};
            # fallback to the UID.
        }

        # create a new user.
        $connection->{type} = $pool->new_user(
            %$connection,
            $Evented::Object::props  => {},
            $Evented::Object::events => {}
        );

        weaken($connection->{type}{conn} = $connection);
        $connection->fire_event(user_ready => $connection->{type});

    }

    # must be a server.
    elsif (length $connection->{name}) {
        my $name = $connection->{name};

        # check if the server is linked already.
        if (my $err = utils::check_new_server($connection->{sid}, $connection->{name}, $me->{name})) {
            notice(connection_invalid => $connection->{ip}, 'Server exists');
            $connection->done($err);
            return;
        }

        $connection->{parent} = $me;
        $connection->{type}   = my $server = $pool->new_server(
            %$connection,
            $Evented::Object::props  => {},
            $Evented::Object::events => {}
        );

        weaken($connection->{type}{conn} = $connection);
        $connection->fire_event(server_ready => $connection->{type});

        $server->{conn} = $connection;
        weaken($connection->{type}{location} = $connection->{type});
        $pool->fire_command_all(new_server => $connection->{type});

    }

    # must be an intergalactic alien.
    else {
        warn 'intergalactic alien has been found';
        $connection->done('alien');
        return;
    }

    $connection->fire_event(ready_done => $connection->{type});
    $connection->{type}->new_connection if $connection->user;
    return $connection->{ready} = 1;
}

# send data to the socket
sub send {
    my ($connection, @msg) = @_;
    return unless $connection->{stream};
    return unless $connection->{stream}->write_handle;
    return if $connection->{goodbye};
    @msg = grep { defined } @msg;
    $connection->{stream}->write("$_\r\n") foreach @msg;
printf "GET(%s): %s\n", $connection->type ? $connection->type->name : 'unregistered', $_ foreach @msg;
}

# send data with a source
sub sendfrom {
    my ($connection, $source) = (shift, shift);
    $connection->send(map { ":$source $_" } @_);
}

# send data from ME
sub sendme {
    my $connection = shift;
    my $source =
        $connection->server ? $me->{sid} : $me->{name};
    $connection->sendfrom($source, @_);
}

sub sock { shift->{stream}{write_handle} }

# send a command to a possibly unregistered connection.
sub early_reply {
    my ($conn, $cmd) = (shift, shift);
    $conn->sendme("$cmd ".(defined $conn->{nick} ? $conn->{nick} : '*')." @_");
}

# end a connection. this must be foolproof.
sub done {
    my ($connection, $reason) = @_;
    L("Closing connection from $$connection{ip}: $reason");

    # a user or server is associated with the connection.
    if ($connection->{type}) {

        # share this quit with the children.
        $pool->fire_command_all(quit => $connection, $reason)
            unless $connection->{killed};

        # tell user.pm or server.pm that the connection is closed.
        $connection->{type}->quit($reason);

    }

    # this is safe because ->send() is safe now.
    $connection->send("ERROR :Closing Link: $$connection{host} ($reason)");

    # remove from connection the pool if it's still there.
    # if the connection has reserved a nick, release it.
    my $r = defined $connection->{nick} ? $pool->nick_in_use($connection->{nick}) : undef;
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
    $connection->fire_event(done => $reason);
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

##########################
### Server credentials ###
##########################

sub send_server_server {
    my $connection = shift;
    my $name = $connection->{name} // $connection->{want};
    if (!defined $name) {
        L('Trying to send credentials to an unknown server?');
        return;
    }
    $connection->send(sprintf 'SERVER %s %s %s %s :%s',
        $me->{sid},
        $me->{name},
        v('PROTO'),
        v('VERSION'),
        ($me->{hidden} ? '(H) ' : '').$me->{desc}
    );
    $connection->{i_sent_server} = 1;
}

sub send_server_pass {
    my $connection = shift;
    my $name = $connection->{name} // $connection->{want};
    if (!defined $name) {
        L('Trying to send credentials to an unknown server?');
        return;
    }
    $connection->send('PASS '.conf(['connect', $name], 'send_password'));
    $connection->{i_sent_pass} = 1;
}

####################
### CAPABILITIES ###
####################

# has a capability.
sub has_cap {
    my ($connection, $flag) = (shift, lc shift);
    return unless $connection->{cap_flags};
    foreach my $f (@{ $connection->{cap_flags} }) {
        return 1 if $f eq $flag;
    }
    return;
}

# add a capability.
sub add_cap {
    my ($connection, @flags) = (shift, map { lc } @_);
    foreach my $flag (@flags) {
        next if $connection->has_cap($flag);
        push @{ $connection->{cap_flags} ||= [] }, $flag;
    }
    return 1;
}

# remove a capability.
sub remove_cap {
    my ($connection, @flags) = (shift, map { lc } @_);
    return unless $connection->{cap_flags};
    my %all_flags = map { $_ => 1 } @{ $connection->{cap_flags} };
    delete $all_flags{$_} foreach @flags;
    @{ $connection->{cap_flags} } = keys %all_flags;
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
