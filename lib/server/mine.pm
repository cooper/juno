#!/usr/bin/perl
# Copyright (c) 2010-14, Mitchell Cooper
package server::mine;

use warnings;
use strict;

use utils qw(log2 col v conf);

# handle local user data
sub handle {print "@_\n";
    my $server = shift;
    return if !$server->{conn} || $server->{conn}{goodbye};
    
    foreach my $line (split "\n", shift) {

        # if logging is enabled, log.
        if (conf('log', 'server_debug')) {
            log2($server->{name}.q(: ).$line);
        }

        my @s = split /\s+/, $line;

        # response to PINGs
        if (uc $s[0] eq 'PING') {
            $server->send('PONG'.(defined $s[1] ? qq( $s[1]) : q..));
            next
        }

        if (uc $s[0] eq 'PONG') {
            # don't care
            next
        }

        if (uc $s[0] eq 'ERROR') {
            log2("received ERROR from $$server{name}");
            $server->{conn}->done('Received ERROR') if $server->{conn};
            return;
        }

        # server is ready for BURST
        if (uc $s[0] eq 'READY') {
            log2("sending burst to $$server{name}");
            send_burst($server);
            next
        }

        next unless defined $s[1];
        my $command = uc $s[1];

        # if it doesn't exist, ignore it and move on.
        # it might make sense to assume incompatibility and drop the server,
        # but I don't want to do that because
        my @handlers = $::pool->server_handlers($command);
        if (!@handlers) {
            log2("unknown command $command; ignoring it");
            next;
        }

        # it exists - parse it.
        foreach my $handler (@handlers) {
            last if !$server->{conn} || $server->{conn}{goodbye};
            
            $handler->{code}($server, $line, @s);

            # forward to children.
            # $server is used here so that it will be ignored.
            send_children($server, $line) if $handler->{forward};
        }
    }
    
    return 1;
}

sub send_burst {
    my $server = shift;
    return if $server->{i_sent_burst};
    
    # BURST.
    my $time = time;
    $server->sendme("BURST $time");

    # fire burst event.
    $server->fire_event(send_burst => $time);

    # ENDBURST.
    $time = time;
    $server->sendme("ENDBURST $time");
    $server->{i_sent_burst} = $time;

    # ask this server to send burst if it hasn't already
    $server->send('READY') unless $server->{sent_burst};

    return 1;
}

# send data to all of my children.
# this actually sends it to all connected servers.
# it is only intended to be called with this server object.
sub send_children {
    my $ignore = shift;

    foreach my $server ($::pool->servers) {

        # don't send to ignored
        if (defined $ignore && $server == $ignore) {
            next;
        }

        # don't try to send to non-locals
        next unless exists $server->{conn};

        # don't send to servers who haven't received my burst.
        next unless $server->{i_sent_burst};

        $server->send(@_);
    }

    return 1
}

sub sendfrom_children {
    my ($ignore, $from) = (shift, shift);
    send_children($ignore, map { ":$from $_" } @_);
    return 1
}

# send data to MY servers.
sub send {
    my $server = shift;
    if (!$server->{conn}) {
        my $sub = (caller 1)[3];
        log2("can't send data to a unconnected server! please report this error by $sub. $$server{name}");
        return
    }
    $server->{conn}->send(@_)
}

# send data to a server from THIS server.
sub sendme {
    my $server = shift;
    $server->sendfrom(v('SERVER', 'sid'), @_)
}

# send data from a UID or SID.
sub sendfrom {
    my ($server, $from) = (shift, shift);
    $server->send(map { ":$from $_" } @_)
}

# convenient for $server->fire_command
sub fire_command {
    my $server = shift;
    return $::pool->fire_command($server, @_);
}

1
