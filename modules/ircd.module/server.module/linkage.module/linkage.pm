# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "ircd::server::linkage"
# @package:         "server::linkage"
# @description:     "manages server connections"
# @no_bless:        1
# @preserve_sym:    1
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package server::linkage;

use warnings;
use strict;

use utils qw(conf log2 v notice);

our ($api, $mod);

# connect to a server in the configuration
sub connect_server {
    my $server_name = shift;

    # make sure we at least have some configuration information about the server.
    unless ($ircd::conf->has_block(['connect', $server_name])) {
        log2("attempted to connect to nonexistent server: $server_name");
        return;
    }
    
    # then, ensure that the server is not connected already.
    if ($::pool->lookup_server_name($server_name)) {
        log2("attempted to connect an already connected server: $server_name");
        return;
    }

    my %serv = $ircd::conf->hash_of_block(['connect', $server_name]);
    notice(server_connect => $server_name, $serv{address}, $serv{port});

    # create the socket
    my $socket = IO::Socket::IP->new(
        PeerAddr => $serv{address},
        PeerPort => $serv{port},
        Proto    => 'tcp',
        Timeout  => 5
    );

    if (!$socket) {
        log2("could not connect to server $server_name: ".($! ? $! : $@));
        return;
    }

    log2("connection established to server $server_name");
    
    # create a stream.
    my $stream = IO::Async::Stream->new(
        read_handle  => $socket,
        write_handle => $socket
    );

    # create connection object.
    my $conn = $::pool->new_connection(stream => $stream);

    # configure the stream events.
    $stream->configure(
        read_all       => 0,
        read_len       => POSIX::BUFSIZ,
        on_read        => \&ircd::handle_data,
        on_read_eof    => sub { _end($conn, $stream, $server_name, 'Connection closed')   },
        on_write_eof   => sub { _end($conn, $stream, $server_name, 'Connection closed')   },
        on_read_error  => sub { _end($conn, $stream, $server_name, 'Read error: ' .$_[1]) },
        on_write_error => sub { _end($conn, $stream, $server_name, 'Write error: '.$_[1]) }
    );

    # add to loop.
    $::loop->add($stream);

    # send server credentials.
    $conn->send(sprintf 'SERVER %s %s %s %s :%s',
        v('SERVER', 'sid'),
        v('SERVER', 'name'),
        v('PROTO'),
        v('VERSION'),
        v('SERVER', 'desc')
    );
    $conn->send("PASS $serv{send_password}");

    $conn->{sent_creds} = 1;
    $conn->{want}       = $server_name;
    
    return $conn;
}

sub _end {
    my ($conn, $stream, $server_name, $reason) = @_;
    $conn->done($reason);
    $stream->close_now;
    
    # if we have an autoconnect_timer for this server, start a connection timer.
    my $timeout = conf(['connect', $server_name], 'auto_timeout');
    if ($timeout) {
        log2("going to attempt to connect to server $server_name in $timeout seconds.");
        
        # start the timer.
        my $timer = IO::Async::Timer::Periodic->new( 
            delay     => $timeout,
            on_expire => sub { connect_server($server_name) }
        );
        
        $::loop->add($timer);
        $timer->start;
        
    }
    
    # if we don't, that's all - we're done.
    
}

$mod