# Copyright (c) 2012-14, Mitchell Cooper
#
# @name:            "Ident"
# @package:         "M::Ident"
# @description:     "resolve idents"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Ident;

use warnings;
use strict;
use 5.010;

use utils qw(trim);

our ($api, $mod, $me, $pool);

sub init {
    $pool->on('connection.new' => \&connection_new, with_evented_obj => 1) or return;
    return 1;
}

sub connection_new {
    my ($connection, $event) = @_;
    return if $connection->{goodbye};
    
    # postpone registration.
    $connection->sendfrom($me->full, 'NOTICE * :*** Checking ident...');
    $connection->reg_wait;
    
    # create a future that attempts to connect.
    my $family_int     = $connection->{stream}->write_handle->sockdomain;
    my $family_name    = $family_int == 2 ? 'inet' : 'inet6';
    my $connect_future = $::loop->connect(
        addr => {
            family   => $family_name,
            socktype => 'stream',
            port     => 143,
            ip       => $connection->{ip}
        }
    );
    
    # create a future to time out after 3 seconds.
    my $timeout_future = $::loop->timeout_future(after => 3);
    
    # create a third future that will wait for whichever comes first.
    my $future = $connection->{ident_future} = Future->wait_any($connect_future, $timeout_future);
    
    $future->on_ready(sub {
        delete $connection->{ident_future};
        
        # connect was cancelled or failed.
        my $e = $connect_future->failure;
        if (defined $e || $connect_future->is_cancelled) {
            $e //= 'Timed out'; chomp $e;
            ident_cancel($connection, undef, $e);
            return;
        }
        
        # it seems to have succeeded...
        my $socket = $connect_future->get;
        ident_request($connection, $socket);
        
    });
}

# initiate the request.
sub ident_request {
    my ($connection, $socket) = @_;
    
    # data and error handling.
    my $err_cb = sub { ident_cancel($connection, @_) };
    my $stream = $connection->{ident_stream} = IO::Async::Stream->new(
        handle         => $socket,
        on_read_error  => $err_cb,
        on_write_error => $err_cb,
        on_read_eof    => $err_cb,
        on_write_eof   => $err_cb,
        on_read        => sub {}
    );
    $::loop->add($stream);
    
    # create 3 futures:
    #
    # - waits for a \n.
    # - waits 10 seconds before timing out.
    # - waits for whichever of those occurs furst.
    #
    my $line_future    = $stream->read_until("\n");
    my $timeout_future = $::loop->timeout_future(after => 10);
    $connection->{ident_future} =
     Future->wait_any($line_future, $timeout_future)->on_ready(sub {
        
        # we read a line successfully.
        if ($line_future->is_done) {
            ident_read($connection, $stream, $line_future->get);
            return;
        }
        
        # it failed somehow.
        ident_cancel($connection, $stream, $line_future->failure // 'Timed out');
        
    });

    # send the request.
    my $server_port = $connection->{stream}->write_handle->peerport;
    my $client_port = $connection->{stream}->write_handle->sockport; # i.e. 6667
    $stream->write("$server_port, $client_port\r\n");
    
}

# read incoming data.
sub ident_read {
    my ($connection, $stream, $line) = @_;
    chomp $line;
    
    # parts of the response are separated by colons.
    my @items = map { trim($_) } split /:/, $line;
    
    # if the response is not USERID, forget it.
    if (!$items[1] || !$items[3] || $items[1] ne 'USERID') {
        ident_cancel($connection, $stream, 'Response was not USERID');
        return;
    }
    
    # success.
    $connection->{ident_success} = $items[3];
    ident_done($connection, $stream);
    
}

# ident lookup failed.
sub ident_cancel {
    my ($connection, $stream, $err) = @_;
    ident_done(@_);
    $err //= 'unknown error';
    L("Request for $$connection{ip} terminated: $err");
}

# whether succeeded or failed, we're done.
sub ident_done {
    my ($connection, $stream) = @_;
    $stream->close_when_empty if $stream;
    delete $connection->{ident_future};
    delete $connection->{ident_stream};

    # add tilde if not successful.
    if (!defined $connection->{ident_success}) {
        $connection->{tilde} = 1;
        $connection->{ident} = '~'.$connection->{ident} if defined $connection->{ident};
        $connection->sendfrom($me->full, 'NOTICE * :*** No ident response');
    }
    
    # it was successful. set the ident.
    else {
        $connection->{ident} = $connection->{ident_success};
        $connection->sendfrom($me->full, 'NOTICE * :*** Found your ident');
    }
    
    $connection->reg_continue;
}

$mod