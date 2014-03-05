#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
package connection;

use warnings;
use strict;
use 5.010;
use parent 'Evented::Object';

use Socket::GetAddrInfo;
use Scalar::Util 'weaken';

use utils qw[log2 col conn conf match v set];

sub new {
    my ($class, $stream) = @_;
    return unless defined $stream;

    bless my $connection = {
        stream        => $stream,
        ip            => $stream->{write_handle}->peerhost,
        host          => $stream->{write_handle}->peerhost,
        source        => v('SERVER', 'sid'),
        time          => time,
        last_ping     => time,
        last_response => time,
        wait          => 0
    }, $class;

    # two initial waits:
    # in clients - one for NICK, one for USER.
    # in servers - one for PASS, one for SERVER.
    $connection->reg_wait(2);

    return $connection;
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
            if ($main::pool->lookup_user_nick($nick)) {
                $connection->send(':'.v('SERVER', 'name')." 433 * $nick :Nickname is already in use.");
                return
            }

            # invalid chars
            if (!utils::validnick($nick)) {
                $connection->send(':'.v('SERVER', 'name')." 432 * $nick :Erroneous nickname");
                return
            }

            # set the nick
            $connection->{nick} = $nick;
            $connection->reg_continue;

        }

        when ('USER') {

            # set ident and real name
            if (defined $args[3]) {
                $connection->{ident} = $args[0];
                $connection->{real}  = col((split /\s+/, $data, 5)[4]);
                $connection->reg_continue;
            }

            # not enough parameters
            else {
                return $connection->wrong_par('USER')
            }

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
                if (lc $connection->{ip} ne $addr) {
                    $connection->done('Invalid credentials');
                    return;
                }

            }

            # no such server
            else {
                $connection->done('Invalid credentials');
                return;
            }

            # made it.
            $connection->reg_continue;

        }

        when ('PASS') {

            # parameter check
            return $connection->wrong_par('PASS') if not defined $args[0];

            $connection->{pass} = shift @args;
            $connection->reg_continue;
            
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
    $connection->send(':'.v('SERVER', 'name').' 461 '
      .($connection->{nick} ? $connection->{nick} : '*').
      " $cmd :Not enough parameters");
    return
}

# increase the wait count.
sub reg_wait {
    my ($connection, $inc) = (shift, shift || 1);
    $connection->{wait} += $inc;
}

# decrease the wait count.
sub reg_continue {
    my ($connection, $inc) = (shift, shift || 1);
    $connection->ready unless $connection->{wait} -= $inc;
}

sub ready {
    my $connection = shift;

    # must be a user
    if (exists $connection->{nick}) {

        # if the client limit has been reached, hang up
        # FIXME: completely broken since pool creation. not sure what to do with this.
        #my $count = scalar grep { ($_->{type} || '')->isa('user') } values %connection;
        #if ($count >= conf('limit', 'client')) {
        #    $connection->done('Not accepting clients');
        #    return;
        #}
        
        $connection->{server}   = v('SERVER');
        $connection->{location} = v('SERVER');
        $connection->{cloak}  //= $connection->{host};


        # create a new user.
        $connection->{type}     = $main::pool->new_user(%$connection);
    }

    # must be a server
    elsif (exists $connection->{name}) {

        # check for valid password.
        my $password = utils::crypt($connection->{pass}, conn($connection->{name}, 'encryption'));

        if ($password ne conn($connection->{name}, 'receive_password')) {
            $connection->done('Invalid credentials');
            return
        }

        $connection->{parent} = v('SERVER');
        $connection->{type}   = $main::pool->new_server(%$connection);
        $main::pool->fire_command_all(sid => $connection->{type});

        # send server credentials
        if (!$connection->{sent_creds}) {
            $connection->send(sprintf 'SERVER %s %s %s %s :%s', v('SERVER', 'sid'), v('SERVER', 'name'), v('PROTO'), v('VERSION'), v('SERVER', 'desc'));
            $connection->send('PASS '.conn($connection->{name}, 'send_password'))
        }

        $connection->send('READY');

    }

    
    else {
        # must be an intergalactic alien
        warn 'intergalactic alien has been found';
    }
    
    weaken($connection->{type}{conn} = $connection);
    $connection->{type}->new_connection if $connection->{type}->isa('user');
    return $connection->{ready} = 1;
}

# send data to the socket
sub send {
    my $connection = shift;
    return unless $connection->{stream};
    return if $connection->{goodbye};
    return $connection->{stream}->write(shift()."\r\n");
}

sub sock {
    return shift->{stream}{read_handle};
}

# end a connection

sub done {
    my ($connection, $reason, $silent) = @_;
    return if $connection->{goodbye};
    
    log2("Closing connection from $$connection{ip}: $reason");

    if ($connection->{type}) {
        # share this quit with the children
        $main::pool->fire_command_all(quit => $connection, $reason);

        # tell user.pm or server.pm that the connection is closed
        $connection->{type}->quit($reason)
    }
    $connection->send("ERROR :Closing Link: $$connection{host} ($reason)") unless $silent;

    # remove from connection list
    $connection->{pool}->delete_connection($connection) if $connection->{pool};
    
    $connection->{stream}->close_when_empty; # will close it WHEN the buffer is empty

    # destroy these references, just in case.
    delete $connection->{type}{conn};
    delete $connection->{type};

    # prevent confusion if more data is received
    delete $connection->{ready};
    $connection->{goodbye} = 1;

    return 1

}

###########################
### CLIENT CAPABILITIES ###
###########################


# has client capability
sub has_cap {
    my ($connection, $flag) = @_;
    return $flag ~~ @{$connection->{cap}}
}

# add client capability
sub add_cap {
    my $connection = shift;
    my @flags = grep { !$connection->has_cap($_) } @_;
    log2("adding capability flags to $connection: @flags");
    push @{$connection->{cap}}, @flags
}

# remove client capability
sub remove_cap {
    my $connection = shift;
    my @remove     = @_;
    my %r;
    log2("removing capability flags from $connection: @remove");

    @r{@remove}++;

    my @new        = grep { !exists $r{$_} } @{$connection->{cap}};
    $connection->{flags} = \@new;
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
