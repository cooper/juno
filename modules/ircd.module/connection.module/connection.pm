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
use Scalar::Util 'weaken';
use utils qw(conf v notice);

our ($api, $mod, $me, $pool);

sub init {

    # basically, this forwards to server/user ->handle().
    # it is the lowest priority of the events fired together in ->handle() below.
    # by default, registration commands that work post-registration stop the event
    # before it would reach these handlers.
    # THIS IS ONLY USED FOR SERVERS AS OF 8 July 2014.
    $pool->on('connection.raw' => sub {
        my ($connection, $event, $data, @args) = @_;
        return unless $connection->{type};
        return unless $connection->{type}->isa('server');
        $connection->{type}->handle($data, \@args);
    }, name => 'high.level.handlers', priority => -100, with_eo => 1);

    # send unknown command. this is canceled by handlers.
    $pool->on('connection.message' => sub {
        my ($connection, $event, $msg) = @_;
        $connection->numeric(ERR_UNKNOWNCOMMAND => $msg->raw_cmd);
        return;
    }, name => 'ERR_UNKNOWNCOMMAND', priority => -200, with_eo => 1);
    
}

sub new {
    my ($class, $stream) = @_;
    return unless defined $stream;

    bless my $connection = {
        stream        => $stream,
        ip            => $stream->{write_handle}->peerhost,
        host          => $stream->{write_handle}->peerhost,
        localport     => $stream->{write_handle}->sockport,
        peerport      => $stream->{write_handle}->peerport,
        source        => $me->{sid},
        time          => time,
        last_response => time,
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
    push @events,
        [ $connection->{type}, message          => $msg ],
        [ $connection->{type}, "message_${cmd}" => $msg ]
    if $connection->{type} && $connection->{type}->isa('user');
    
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
    
    # must be a user.
    if (length $connection->{nick} && length $connection->{ident}) {

        # if the client limit has been reached, hang up.
        if (scalar $pool->local_users >= conf('limit', 'client')) {
            $connection->done('Not accepting clients');
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

    }

    # must be a server.
    elsif (length $connection->{name}) {
        my $name = $connection->{name};
        
        # check for valid password.
        my $password = utils::crypt(
            $connection->{pass},
            conf(['connect', $name], 'encryption')
        );
        if ($password ne conf(['connect', $name], 'receive_password')) {
            $connection->done('Invalid credentials');
            notice(connection_invalid => $connection->{ip}, 'Received invalid password');
            return;
        }

        # check if the server is linked already.
        if ($pool->lookup_server($connection->{sid}) || $pool->lookup_server_name($connection->{name})) {
            notice(connection_invalid => $connection->{ip}, 'Server exists');
            return;
        }

        $connection->{parent} = $me;
        $connection->{type}   = my $server = $pool->new_server(
            %$connection,
            $Evented::Object::props  => {},
            $Evented::Object::events => {}
        );
        
        $server->{conn} = $connection;
        weaken($connection->{type}{location} = $connection->{type});
        $pool->fire_command_all(sid => $connection->{type});

        # send server credentials
        if (!$connection->{sent_creds}) {
            $connection->send_server_credentials;
        }

        # I already sent mine, meaning it should have been accepted on both now.
        # go ahead and send the burst.
        else {
            $server->send_burst if !$server->{i_sent_burst};
        }

        # honestly at this point the connect timer needs to die.
        server::linkage::cancel_connection($connection->{name});

    }

    # must be an intergalactic alien.
    else {
        warn 'intergalactic alien has been found';
        $connection->done('alien');
        return;
    }

    weaken($connection->{type}{conn} = $connection);
    $connection->{type}->new_connection if $connection->{type}->isa('user');
    return $connection->{ready} = 1;
}

# send data to the socket
sub send {
    my ($connection, @msg) = @_;
    return unless $connection->{stream};
    return if $connection->{goodbye};
    $connection->{stream}->write("$_\r\n") foreach grep { defined } @msg;
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
        $connection->{type} && $connection->{type}->isa('server') ?
        $me->{sid} : $me->{name};
    $connection->sendfrom($source, @_);
}

sub sock { shift->{stream}{write_handle} }

sub send_server_credentials {
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
        $me->{desc}
    );     
    $connection->send('PASS '.conf(['connect', $name], 'send_password'));  
}

# send a command to a possibly unregistered connection.
sub early_reply {
    my ($conn, $cmd) = (shift, shift);
    $conn->sendme("$cmd ".(defined $conn->{nick} ? $conn->{nick} : '*')." @_");
}

# end a connection. this must be foolproof.
sub done {
    my ($connection, $reason, $silent) = @_;
    L("Closing connection from $$connection{ip}: $reason");


    # a user or server is associated with the connection.
    if ($connection->{type}) {

        # share this quit with the children.
        $pool->fire_command_all(quit => $connection, $reason);

        # tell user.pm or server.pm that the connection is closed.
        $connection->{type}->quit($reason);

    }

    # I'm not sure where $silent is even used these days.
    # this is safe because ->send() is safe now.
    $connection->send("ERROR :Closing Link: $$connection{host} ($reason)") unless $silent;

    # remove from connection the pool if it's still there.
    # if the connection has reserved a nick, release it.
    my $r = defined $connection->{nick} ? $pool->nick_in_use($connection->{nick}) : undef;
    $pool->release_nick($connection->{nick}) if $r && $r == $connection;
    $pool->delete_connection($connection, $reason) if $connection->{pool};

    # will close it WHEN the buffer is empty
    # (if the stream still exists).
    $connection->{stream}->close_when_empty if $connection->{stream};

    # destroy these references, just in case.
    delete $connection->{type}{conn};
    delete $connection->{type};

    # prevent confusion if more data is received.
    delete $connection->{ready};
    $connection->{goodbye} = 1;

    # delete all callbacks to dispose of any possible
    # looping references within them.
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

    # local user.
    my $nick = ($connection->{type} || $connection)->{nick} // '*';
    $connection->sendme("$num $nick $_") foreach @response;

    return 1;

}

####################
### CAPABILITIES ###
####################

# has a capability
sub has_cap {
    my ($connection, $flag) = (shift, lc shift);
    return unless $connection->{cap_flags};
    foreach my $f (@{ $connection->{cap_flags} }) {
        return 1 if $f eq $flag;
    }
    return;
}

# add a capability
sub add_cap {
    my ($connection, @flags) = (shift, map { lc } @_);
    foreach my $flag (@flags) {
        next if $connection->has_cap($flag);
        push @{ $connection->{cap_flags} ||= [] }, $flag;
    }
    return 1;
}

# remove a capability 
sub remove_cap {
    my ($connection, @flags) = (shift, map { lc } @_);
    return unless $connection->{cap_flags};
    my %all_flags = map { $_ => 1 } @{ $connection->{cap_flags} };
    delete $all_flags{$_} foreach @flags;
    @{ $connection->{cap_flags} } = keys %all_flags;
}

sub DESTROY {
    my $connection = shift;
    L("$connection destroyed");
}

$mod