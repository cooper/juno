#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
package server::mine;

use warnings;
use strict;
use utils qw[log2 col v conf];

our (%commands, %outgoing);

# register command handlers
# ($source, $command, $callback, $forward)
sub register_handler {
    my ($source, $command) = (shift, uc shift);

    # does it already exist?
    if (exists $commands{$command}) {
        log2("attempted to register $command which already exists");
        return
    }

    # ensure that it is CODE
    my $ref = shift;
    if (ref $ref ne 'CODE') {
        log2("not a CODE reference for $command");
        return
    }

    # one per source
    if (exists $commands{$command}{$source}) {
        log2("$source already registered $command; aborting");
        return
    }

    #success
    $commands{$command}{$source} = {
        code    => $ref,
        source  => $source,
        forward => shift
    };
    log2("$source registered $command");
    return 1
}

# unregister
sub delete_handler {
    my $command = uc shift;
    log2("deleting handler $command");
    delete $commands{$command}
}

# register outgoing command handlers
sub register_outgoing_handler {
    my ($source, $command) = (shift, uc shift);

    # does it already exist?
    if (exists $outgoing{$command}) {
        log2("attempted to register $command which already exists");
        return
    }

    # ensure that it is CODE
    my $ref = shift;
    if (ref $ref ne 'CODE') {
        log2("not a CODE reference for $command");
        return
    }

    #success
    $outgoing{$command} = {
        code    => $ref,
        source  => $source
    };
    log2("$source registered $command");
    return 1
}

# unregister
sub delete_outgoing_handler {
    my $command = uc shift;
    log2("deleting handler $command");
    delete $outgoing{$command}
}

# fire outgoing
sub fire_command {
    my ($server, $command, @args) = (shift, uc shift, @_);
    if (!$outgoing{$command}) {
        log2((caller)[0]." fired $command which does not exist");
        return
    }

    # send
    $server->send($outgoing{$command}{code}(@args));

    return 1
}

sub fire_command_all {
    my ($command, @args) = (uc shift, @_);
    if (!$outgoing{$command}) {
        log2((caller)[0]." fired $command which does not exist");
        return
    }

    # send
    send_children(undef, $outgoing{$command}{code}(@args));

    return 1
}

# handle local user data
sub handle {
    my $server = shift;
    
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
            next
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
        if (!$commands{$command}) {
            log2("unknown command $command; ignoring it");
            next
        }

        # it exists- parse it.
        foreach my $source (keys %{$commands{$command}}) {
            $commands{$command}{$source}{code}($server, $line, @s);

            # forward to children
            send_children($server, $line) if $commands{$command}{$source}{forward};
        }
    }
    return 1
}

sub send_burst {
    my $server = shift;

    if ($server->{i_sent_burst}) {
        log2("trying to send burst to a server we have already sent burst to. (no big deal, probably just lag)");
        return
    }

    $server->sendme('BURST '.time);

    # servers and mode names
    my ($do, %done);
   
    # first, send modes of this server.
    fire_command($server, aum => v('SERVER'));
    fire_command($server, acm => v('SERVER'));
        
    $done{$server}      = 1;
    $done{v('SERVER')} = 1;
    
    $do = sub {
        my $serv = shift;
        
        # already did this one.
        return if $done{$serv};
        
        # we need to do the parent first.
        if (!$done{$serv->{parent}} && $serv->{parent} != $serv) {
            $do->($serv->{parent});
        }
        
        # fire the command.
        fire_command($server, sid => $serv);
        $done{$serv} = 1;
        
        # send modes using compact AUM and ACM
        fire_command($server, aum => $serv);
        fire_command($server, acm => $serv);
        
    }; $do->($_) foreach values %server::server;
    

    # users
    foreach my $user (values %user::user) {
    
        # ignore users the server already knows!
        next if $user->{server} == $server || $server->{sid} == $user->{source};
        
        fire_command($server, uid => $user);

        # oper flags
        if (scalar @{$user->{flags}}) {
            fire_command($server, oper => $user, @{$user->{flags}})
        }

        # away reason
        if (exists $user->{away}) {
            fire_command($server, away => $user)
        }
        
    }

    # channels, using compact CUM
    foreach my $channel (values %channel::channels) {
        fire_command($server, cum => $channel);
        fire_command($server, topicburst => $channel) if $channel->{topic}
    }

    $server->sendme('ENDBURST '.time);
    $server->{i_sent_burst} = 1;

    # ask this server to send burst if it hasn't already
    $server->send('READY') unless $server->{sent_burst};

    return 1
}

# send data to all of my children
sub send_children {
    my $ignore = shift;

    foreach my $server (values %server::server) {

        # don't send to ignored
        if (defined $ignore && $server == $ignore) {
            next
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

# send data from ME

sub sendme {
    my $server = shift;
    $server->sendfrom(v('SERVER', 'sid'), @_)
}

sub sendserv { &sendme }

# send data from a UID or SID
sub sendfrom {
    my ($server, $from) = (shift, shift);
    $server->send(map { ":$from $_" } @_)
}

1
