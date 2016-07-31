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
    my ($connection, $event) = @_;
    return if $connection->{goodbye} || $connection->{ident_skip};
    return unless $connection->{stream}->write_handle;

    # postpone registration.
    $connection->early_reply(NOTICE => ':*** Checking ident...');
    $connection->reg_wait('ident');

    # create a future that attempts to connect.
    my $family_int     = $connection->stream->write_handle->sockdomain;
    my $family_name    = $family_int == AF_INET6 ? 'inet6' : 'inet';
    my $connect_future = $::loop->connect(
        addr => {
            family   => $family_name,
            socktype => 'stream',
            port     => 113,
            ip       => $connection->{ip}
        }
    );

    # create a future to time out after 3 seconds.
    my $timeout_future = $::loop->timeout_future(after => 3);

    # create a third future that will wait for whichever comes first.
    my $future = Future->wait_any($connect_future, $timeout_future);
    $connection->adopt_future(ident_connect => $future);

    # on ready, either start sending data or cancel.
    $future->on_ready(sub {

        # connect was cancelled or failed.
        my $e = $connect_future->failure;
        if (defined $e || $connect_future->is_cancelled) {
            $e //= 'Timed out'; chomp $e;
            ident_cancel($connection, $e);
            return;
        }

        # it seems to have succeeded...
        my $socket = $connect_future->get;
        ident_write($connection, $socket);

    });
}

# USER received.
sub connection_user {
    my ($connection, $event, $ident, $real) = @_;

    # if the requested ident has ~, cancel ident check.
    if (substr($ident, 0, 1) eq '~') {

        # already did a lookup or it was skipped already. ignore the request.
        return if $connection->{ident_checked};

        $connection->sendfrom($me->full, 'NOTICE * :*** Skipped ident lookup');
        $connection->{ident_skip} = 1;
        ident_cancel($connection, 'Skipped by user');
    }

    # otherwise, add a tilde when necessary.
    elsif ($connection->{ident_tilde}) {
        $connection->{ident} = "~$ident";
    }
}

# SERVER received. don't waste time processing this.
sub connection_server {
    my $connection = shift;
    ident_cancel($connection, 'SERVER command received');
}

# initiate the request.
sub ident_write {
    my ($connection, $socket) = @_;

    # data and error handling.
    my $err_cb = sub { ident_cancel($connection, @_) };
    my $stream = $connection->{ident_stream} = IO::Async::Stream->new(
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
    $connection->adopt_future(ident_read => $future);

    # on ready, set the ident or cancel.
    $future->on_ready(sub {

        # we read a line successfully.
        if ($line_future->is_done) {
            ident_read($connection, $line_future->get);
            return;
        }

        # it failed somehow.
        ident_cancel(
            $connection,
            $line_future->failure // 'Timed out'
        );

    });

    # send the request.
    return unless $connection->{stream}->write_handle;
    my $server_port = $connection->sock->peerport;
    my $client_port = $connection->sock->sockport; # i.e. 6667
    $stream->write("$server_port, $client_port\r\n");
}

# read incoming data.
sub ident_read {
    my ($connection, $line) = @_;
    chomp $line;

    # parts of the response are separated by colons.
    my @items = map { trim($_) } split /:/, $line;

    # if the response is not USERID, forget it.
    if (!$items[1] || !$items[3] || $items[1] ne 'USERID') {
        ident_cancel($connection, 'Response was not USERID');
        return;
    }

    # is the ident valid?
    if (!utils::validident($items[3])) {
        ident_cancel($connection, 'Bad ident');
        return;
    }

    # success.
    $connection->{ident_success} = $items[3];
    ident_done($connection);

}

# ident lookup failed.
sub ident_cancel {
    my ($connection, $err) = @_;
    return if $connection->{ident_checked};
    ident_done(@_);
    $err //= 'unknown error';
    L("Request for $$connection{ip} terminated: $err");
}

# whether succeeded or failed, we're done.
sub ident_done {
    my ($connection) = @_;
    return if $connection->{ident_checked};

    # close the stream.
    my $stream = delete $connection->{ident_stream};
    $stream->close_when_empty if $stream;

    # immediately cancel both futures.
    $connection->abandon_future('ident_connect');
    $connection->abandon_future('ident_read');

    # add tilde if not successful.
    if (!defined $connection->{ident_success}) {
        $connection->{ident_tilde}++;
        $connection->{ident} = '~'.$connection->{ident}
            if length $connection->{ident}
            && substr($connection->{ident}, 0, 1) ne '~';
        $connection->early_reply(NOTICE => ':*** No ident response')
            unless $connection->{ident_skip};
    }

    # it was successful. set the ident.
    else {
        $connection->{ident_verified}++;
        $connection->{ident} = delete $connection->{ident_success};
        $connection->early_reply(NOTICE => ':*** Found your ident')
            unless $connection->{ident_skip};
        $connection->fire('found_ident');
    }

    $connection->{ident_checked} = 1;
    $connection->reg_continue('ident');
}

$mod
