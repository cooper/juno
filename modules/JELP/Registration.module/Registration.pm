# Copyright (c) 2014, mitchellcooper
#
# Created on Mitchells-Mac-mini.local
# Sat Aug  9 23:11:08 EDT 2014
# Registration.pm
#
# @name:            'JELP::Registration'
# @package:         'M::JELP::Registration'
# @description:     'JELP registration commands'
#
# @depends.modules: 'Base::RegistrationCommands'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::JELP::Registration;

use warnings;
use strict;
use 5.010;

use utils qw(conf notice irc_match);

our ($api, $mod, $pool);

our %registration_commands = (
    SERVER => {
        code   => \&rcmd_server,
        params => 5,
        proto  => 'jelp'
    },
    PASS => {
        code   => \&rcmd_pass,
        params => 1,
        proto  => 'jelp'
    },
    READY => {
        code  => \&rcmd_ready,
        proto => 'jelp',
        after_reg => 1
    }
);

###########################
### SERVER REGISTRATION ###
###########################

sub rcmd_server {
    my ($connection, $event, @args) = @_;
    $connection->{$_} = shift @args foreach qw[sid name proto ircd desc];

    # hidden?
    my $sub = \substr($connection->{desc}, 0, 4);
    if (length $sub && $$sub eq '(H) ') {
        $$sub = '';
        $connection->{hidden} = 1;
    }

    # if this was by our request (as in an autoconnect or /connect or something)
    # don't accept any server except the one we asked for.
    if (length $connection->{want} && lc $connection->{want} ne lc $connection->{name}) {
        $connection->done('Unexpected server');
        return;
    }

    # find a matching server.
    if (defined(my $addrs = conf(['connect', $connection->{name}], 'address'))) {
        $addrs = [$addrs] if !ref $addrs;
        if (!irc_match($connection->{ip}, @$addrs)) {
            $connection->done('Invalid credentials');
            notice(connection_invalid => $connection->{ip}, 'IP does not match configuration');
            return;
        }
    }

    # no such server.
    else {
        $connection->done('Invalid credentials');
        notice(connection_invalid => $connection->{ip}, 'No block for this server');
        return;
    }

    # send my own SERVER if I haven't already.
    if (!$connection->{i_sent_server}) {
        $connection->send_server_server;
    }

    # otherwise, I am going to expose my password.
    # this means that I was the one that issued the connect.
    else {
        $connection->send_server_pass;
    }

    # made it.
    $connection->fire_event(reg_server => @args);
    $connection->reg_continue('id1');
    return 1;

}

sub rcmd_pass {
    my ($connection, $event, @args) = @_;
    $connection->{pass} = shift @args;

    # moron hasn't sent SERVER yet.
    my $name = $connection->{name};
    return if !length $name;

    $connection->{link_type} = 'jelp';

    # check for valid password.
    my $password = utils::crypt(
        $connection->{pass},
        conf(['connect', $name ], 'encryption')
    );
    if ($password ne conf(['connect', $name], 'receive_password')) {
        $connection->done('Invalid credentials');
        notice(connection_invalid => $connection->{ip}, 'Received invalid password');
        return;
    }

    # send my own PASS if I haven't already.
    # this is postponed so that the burst will not be triggered until
    # hostname resolve, ident, etc. are done.
    $connection->on(ready_done => sub {
        my $c = shift;
        $c->send_server_pass;
        $c->send('READY');
    }, name => 'jelp.send.password', with_eo => 1) if !$connection->{i_sent_pass};

    $connection->reg_continue('id2');
    return 1;
}

sub _send_burst {
    my $connection = shift;

    # the server is registered on our end.
    my $server = $connection->server or return;

    # send the burst.
    if (!$server->{i_sent_burst}) {
        $server->send_burst;
        return 1;
    }

    # already did?
    L("$$server{name} is requesting burst, but I already sent it");
    return;

}

# the server is ready to receive burst.
sub rcmd_ready {
    my ($connection, $event) = @_;

    # the server is registered, and we haven't sent burst. do so.
    _send_burst($connection) and return;

    # the server is not yet registered; postpone the burst.
    $connection->on(ready_done => \&_send_burst, with_eo => 1)
        unless $connection->{ready};

}

$mod
