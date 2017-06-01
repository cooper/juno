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
use Socket qw(AF_INET6);

our ($api, $mod, $me, $pool);

# Sets these keys on the connection:
#
#   ident               the ident. it MAY be prefixed with a tilde. this will
#                       become $user->{ident} after registration.
#
#   ident_checked       true if we have attempted to look up an ident at all.
#                       it will be true even if the ident verification failed.
#
#   ident_verified      true if we received an ident response and accepted it.
#
#   ident_tilde         true if we are prefixing the ident with a tilde.
#                       we have to remember so that later USER commands will not
#                       overwrite the tilde which was added on ident abort.
#
#   ident_skip          true if we will/did skip ident checking.
#
#   ident_stream        (temporary) an IO::Async::Stream to an ident server.
#
#   ident_success       (temporary) before registration completes, the pending
#                       ident received from the server is stored here.
#
sub init {

    # on new connection, check ident
    $pool->on('connection.new' => \&connection_new,
        name    => 'check.ident',
        after   => 'resolve.hostname',
        with_eo => 1
    );

    # USER and SERVER registration commands
    $pool->on('connection.reg_user' => \&connection_user,
        with_eo => 1
    );
    $pool->on('connection.looks_like_server' => \&connection_server,
        with_eo => 1
    );

    return 1;
}

# on new connection, perform ident lookup
sub connection_new {
    my ($conn, $event) = @_;
    return if $conn->{goodbye} || $conn->{ident_skip};
    return unless $conn->{stream}->write_handle;

    # postpone registration.
    $conn->early_reply(NOTICE => ':*** Checking ident...');
    $conn->reg_wait('ident');

    # create a future that attempts to connect.
    my $family_int     = $conn->stream->write_handle->sockdomain;
    my $family_name    = $family_int == AF_INET6 ? 'inet6' : 'inet';
    my $connect_future = $::loop->connect(
        addr => {
            family   => $family_name,
            socktype => 'stream',
            port     => 113,
            ip       => $conn->{ip}
        }
    );

    # create a future to time out after 3 seconds.
    my $timeout_future = $::loop->timeout_future(after => 3);

    # create a third future that will wait for whichever comes first.
    my $future = Future->wait_any($connect_future, $timeout_future);
    $conn->adopt_future(ident_connect => $future);

    # on ready, either start sending data or cancel.
    $future->on_ready(sub {

        # connect was cancelled or failed.
        my $e = $connect_future->failure;
        if (defined $e || $connect_future->is_cancelled) {
            $e //= 'Timed out'; chomp $e;
            ident_cancel($conn, $e);
            return;
        }

        # it seems to have succeeded...
        my $socket = $connect_future->get;
        ident_write($conn, $socket);

    });
}

# USER received.
sub connection_user {
    my ($conn, $event, $ident, $real) = @_;

    # if the requested ident has ~, cancel ident check.
    if (substr($ident, 0, 1) eq '~') {

        # already did a lookup or it was skipped already. ignore the request.
        return if $conn->{ident_checked};

        $conn->sendfrom($me->full, 'NOTICE * :*** Skipped ident lookup');
        $conn->{ident_skip} = 1;
        ident_cancel($conn, 'Skipped by user');
    }

    # otherwise, add a tilde when necessary.
    elsif ($conn->{ident_tilde}) {
        $conn->{ident} = "~$ident";
    }
}

# SERVER received. don't waste time processing this.
sub connection_server {
    my $conn = shift;
    ident_cancel($conn, 'SERVER command received');
}

# initiate the request.
sub ident_write {
    my ($conn, $socket) = @_;

    # data and error handling.
    my $err_cb = sub { ident_cancel($conn, @_) };
    my $stream = $conn->{ident_stream} = IO::Async::Stream->new(
        handle         => $socket,
        on_read_error  => $err_cb,
        on_write_error => $err_cb,
        on_read_eof    => $err_cb,
        on_write_eof   => $err_cb,
        on_read        => sub { } # who cares
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
    my $future         = Future->wait_any($line_future, $timeout_future);
    $conn->adopt_future(ident_read => $future);

    # on ready, set the ident or cancel.
    $future->on_ready(sub {

        # we read a line successfully.
        if ($line_future->is_done) {
            ident_read($conn, $line_future->get);
            return;
        }

        # it failed somehow.
        ident_cancel(
            $conn,
            $line_future->failure // 'Timed out'
        );

    });

    # send the request.
    return unless $conn->{stream}->write_handle;
    my $server_port = $conn->sock->peerport;
    my $client_port = $conn->sock->sockport; # i.e. 6667
    $stream->write("$server_port, $client_port\r\n");
}

# read incoming data.
sub ident_read {
    my ($conn, $line) = @_;
    chomp $line;

    # parts of the response are separated by colons.
    my @items = map { trim($_) } split /:/, $line;

    # if the response is not USERID, forget it.
    if (!$items[1] || !$items[3] || $items[1] ne 'USERID') {
        ident_cancel($conn, 'Response was not USERID');
        return;
    }

    # is the ident valid?
    if (!utils::validident($items[3])) {
        ident_cancel($conn, 'Bad ident');
        return;
    }

    # success.
    $conn->{ident_success} = $items[3];
    ident_done($conn);

}

# ident lookup failed.
sub ident_cancel {
    my ($conn, $err) = @_;
    return if $conn->{ident_checked};
    ident_done(@_);
    $err //= 'unknown error';
    L("Request for $$conn{ip} terminated: $err");
}

# whether succeeded or failed, we're done.
sub ident_done {
    my ($conn) = @_;
    return if $conn->{ident_checked};

    # close the stream.
    my $stream = delete $conn->{ident_stream};
    $stream->close_when_empty if $stream;

    # immediately cancel both futures.
    $conn->abandon_future('ident_connect');
    $conn->abandon_future('ident_read');

    # add tilde if not successful.
    if (!defined $conn->{ident_success}) {
        $conn->{ident_tilde}++;
        $conn->{ident} = '~'.$conn->{ident}
            if length $conn->{ident}
            && substr($conn->{ident}, 0, 1) ne '~';
        $conn->early_reply(NOTICE => ':*** No ident response')
            unless $conn->{ident_skip};
    }

    # it was successful. set the ident.
    else {
        $conn->{ident_verified}++;
        $conn->{ident} = delete $conn->{ident_success};
        $conn->early_reply(NOTICE => ':*** Found your ident')
            unless $conn->{ident_skip};
        $conn->fire('found_ident');
    }

    $conn->{ident_checked} = 1;
    $conn->reg_continue('ident');
}

$mod
