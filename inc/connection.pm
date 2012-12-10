#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
package connection;

use warnings;
use strict;
use feature 'switch';

use Socket::GetAddrInfo;

use utils qw[log2 col conn conf match gv set];

our ($ID, %connection) = 'a';

sub new {
    my ($class, $stream) = @_;
    return unless defined $stream;

    bless my $connection = {
        stream        => $stream,
        ip            => $stream->{write_handle}->peerhost,
        source        => gv('SERVER', 'sid'),
        time          => time,
        last_ping     => time,
        last_response => time
    }, $class;

    # resolve hostname
    #if (conf qw/enabled resolve/) {
    #    $connection->send(':'.gv('SERVER', 'name').' NOTICE * :*** Looking up your hostname...');
    #    res::resolve_address($connection)
    #}
    #else {
        $connection->{host} = $connection->{ip};
        $connection->send(':'.gv('SERVER', 'name').' NOTICE * :*** hostname resolving is not enabled on this server');
    #}

    # update total connection count
    my $count = gv('connection_count');
    set('connection_count', $count + 1);

    # update maximum connection count
    if ((scalar keys %connection) + 1 > gv('max_connection_count')) {
        set('max_connection_count', (scalar keys %connection) + 1);
    }

    log2("Processing connection from $$connection{ip}");
    return $connection{$stream} = $connection
}

sub handle {
    my ($connection, $data) = @_;

    $connection->{ping_in_air}   = 0;
    $connection->{last_response} = time;

    # strip unwanted characters
    $data =~ s/(\n|\r|\0)//g;

    # connection is being closed
    return if $connection->{goodbye};

    # if this peer is registered, forward the data to server or user
    return $connection->{type}->handle($data) if $connection->{ready};

    my @args = split /\s+/, $data;
    return unless defined $args[0];

    given (uc shift @args) {

        when ('NICK') {

            # not enough parameters
            return $connection->wrong_par('NICK') if not defined $args[0];

            my $nick = col(shift @args);

            # nick exists
            if (user::lookup_by_nick($nick)) {
                $connection->send(':'.gv('SERVER', 'name')." 433 * $nick :Nickname is already in use.");
                return
            }

            # invalid chars
            if (!utils::validnick($nick)) {
                $connection->send(':'.gv('SERVER', 'name')." 432 * $nick :Erroneous nickname");
                return
            }

            # set the nick
            $connection->{nick} = $nick;

            # the user is ready if their USER info has been sent
            $connection->ready if exists $connection->{ident} && exists $connection->{host}

        }

        when ('USER') {

            # set ident and real name
            if (defined $args[3]) {
                $connection->{ident} = $args[0];
                $connection->{real}  = col((split /\s+/, $data, 5)[4])
            }

            # not enough parameters
            else {
                return $connection->wrong_par('USER')
            }

            # the user is ready if their NICK has been sent
            $connection->ready if exists $connection->{nick} && exists $connection->{host}

        }

        when ('SERVER') {

            # parameter check
            return $connection->wrong_par('SERVER') if not defined $args[4];


            $connection->{$_}   = shift @args foreach qw[sid name proto ircd];
            $connection->{desc} = col(join ' ', @args);

            # if this was by our request (as in an autoconnect or /connect or something)
            # don't accept any server except the one we asked for.
            if (exists $connection->{want} && lc $connection->{want} ne lc $connection->{name}) {
                $connection->done('unexpected server');
                return
            }

            # find a matching server

            if (defined ( my $addr = conn($connection->{name}, 'address') )) {

                # check for matching IPs

                if (!match($connection->{ip}, $addr)) {
                    $connection->done('Invalid credentials');
                    return
                }

            }

            # no such server

            else {
                $connection->done('Invalid credentials');
                return
            }

            # if a password has been sent, it's ready
            $connection->ready if exists $connection->{pass} && exists $connection->{host}

        }

        when ('PASS') {

            # parameter check
            return $connection->wrong_par('PASS') if not defined $args[0];

            $connection->{pass} = shift @args;

            # if a server has been sent, it's ready
            $connection->ready if exists $connection->{name} && exists $connection->{host}

        }

        when ('QUIT') {
            my $reason = 'leaving';

            # get the reason if they specified one
            if (defined $args[1]) {
                $reason = col((split /\s+/,  $data, 2)[1])
            }

            $connection->done("~ $reason");
        }

    }
}

# post-registration

sub wrong_par {
    my ($connection, $cmd) = @_;
    $connection->send(':'.gv('SERVER', 'name').' 461 '
      .($connection->{nick} ? $connection->{nick} : '*').
      " $cmd :Not enough parameters");
    return
}

sub ready {
    my $connection = shift;

    # must be a user
    if (exists $connection->{nick}) {

        # if the client limit has been reached, hang up
        if (scalar(grep { $_->{type} && $_->{type}->isa('user') } values %connection) >= conf('limit', 'client')) {
            $connection->done('not accepting clients');
            return
        }

        $connection->{uid}      = gv('SERVER', 'sid').++$ID;
        $connection->{server}   = gv('SERVER');
        $connection->{location} = gv('SERVER');
        $connection->{cloak}    = $connection->{host};
        $connection->{modes}    = '';
        $connection->{type}     = user->new($connection);        
    }

    # must be a server
    elsif (exists $connection->{name}) {

        # check for valid password.
        my $password = utils::crypt($connection->{pass}, conn($connection->{name}, 'encryption'));

        if ($password ne conn($connection->{name}, 'receive_password')) {
            $connection->done('Invalid credentials');
            return
        }

        $connection->{parent} = gv('SERVER');
        $connection->{type}   = server->new($connection);
        server::mine::fire_command_all(sid => $connection->{type});

        # send server credentials
        if (!$connection->{sent_creds}) {
            $connection->send(sprintf 'SERVER %s %s %s %s :%s', gv('SERVER', 'sid'), gv('SERVER', 'name'), gv('PROTO'), gv('VERSION'), gv('SERVER', 'desc'));
            $connection->send('PASS '.conn($connection->{name}, 'send_password'))
        }

        $connection->send('READY');

    }

    
    else {
        # must be an intergalactic alien
        warn 'intergalactic alien has been found';
    }
    
    # memory leak (fixed)
    $connection->{type}->{conn} = $connection;
    user::mine::new_connection($connection->{type}) if $connection->{type}->isa('user');
    return $connection->{ready} = 1

}

sub somewhat_ready {
    my $connection = shift;
    if (exists $connection->{nick} && exists $connection->{ident}) {
        return 1
    }
    if (exists $connection->{name} && exists $connection->{pass}) {
        return 1
    }
    return
}

# send data to the socket
sub send {
    return shift->{stream}->write(shift()."\r\n");
}

# find by a user or server object
sub lookup {
    my $obj = shift;
    foreach my $conn (values %connection) {
        # found a match
        return $conn if $conn->{type} == $obj
    }

    # no matches
    return
}

# find by a stream
sub lookup_by_stream {
    my $stream = shift;
    return $connection{$stream};
}

# end a connection

sub done {

    my ($connection, $reason, $silent) = @_;

    log2("Closing connection from $$connection{ip}: $reason");

    if ($connection->{type}) {
        # share this quit with the children
        server::mine::fire_command_all(quit => $connection, $reason);

        # tell user.pm or server.pm that the connection is closed
        $connection->{type}->quit($reason)
    }
    $connection->send("ERROR :Closing Link: $$connection{host} ($reason)") unless $silent;

    # remove from connection list
    delete $connection{$connection->{stream}}; # XXX select

    $connection->{stream}->close_when_empty; # will close it WHEN the buffer is empty

    # fixes memory leak:
    # referencing to ourself, etc.
    # perl doesn't know to destroy unless we do this
    delete $connection->{type}->{conn};
    delete $connection->{type};

    # prevent confusion if more data is received
    delete $connection->{ready};
    $connection->{goodbye} = 1;

    return 1

}

sub DESTROY {
    my $connection = shift;
    log2("$connection destroyed");
}

# get the IO object
sub obj {
    shift->{stream}->{write_handle} # XXX select
}

1
