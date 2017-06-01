# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-Mac-mini.local
# Sat Aug  9 23:11:08 EDT 2014
# Registration.pm
#
# @name:            'JELP::Registration'
# @package:         'M::JELP::Registration'
# @description:     'JELP registration commands'
#
# @depends.bases+   'RegistrationCommands'
# @depends.modules+ 'JELP::Base'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::JELP::Registration;

use warnings;
use strict;
use 5.010;

use utils qw(conf notice irc_match irc_lc);

our ($api, $mod, $pool);

our %registration_commands = (
    SERVER => {
        code   => \&rcmd_server,
        params => 6,
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
    my ($conn, $event, @args) = @_;
    $conn->{desc} = pop   @args;
    $conn->{$_}   = shift @args for qw(sid name proto ircd);
    my $their_time      = shift @args;

    # check if the time delta is enormous
    server::protocol::check_ts_delta($conn, time, $their_time)
        or return;

    # hidden?
    my $sub = \substr($conn->{desc}, 0, 4);
    if (length $sub && $$sub eq '(H) ') {
        $$sub = '';
        $conn->{hidden} = 1;
    }

    # if this was by our request (as in an autoconnect or /connect or something)
    # don't accept any server except the one we asked for.
    if (length $conn->{want} &&
      irc_lc($conn->{want}) ne irc_lc($conn->{name})) {
        $conn->done('Unexpected server');
        return;
    }

    # find a matching server.
    if (defined(my $addrs =
      conf([ 'connect', $conn->{name} ], 'address'))) {
        $addrs = [$addrs] if !ref $addrs;
        if (!irc_match($conn->{ip}, @$addrs)) {
            $conn->done('Invalid credentials');
            notice(connection_invalid =>
                $conn->{ip}, 'IP does not match configuration');
            return;
        }
    }

    # no such server.
    else {
        $conn->done('Invalid credentials');
        notice(connection_invalid =>
            $conn->{ip}, 'No block for this server');
        return;
    }

    # send my own SERVER if I haven't already.
    if (!$conn->{i_sent_server}) {
        M::JELP::Base::send_server_server($conn);
    }

    # otherwise, I am going to expose my password.
    # this means that I was the one that issued the connect.
    else {
        M::JELP::Base::send_server_pass($conn);
    }

    # made it.
    $conn->fire('looks_like_server');
    $conn->reg_continue('id1');
    return 1;

}

sub rcmd_pass {
    my ($conn, $event, @args) = @_;
    $conn->{pass} = shift @args;

    # moron hasn't sent SERVER yet.
    my $name = $conn->{name};
    return if !length $name;

    $conn->{link_type} = 'jelp';

    # check for valid password.
    my $password = utils::crypt(
        $conn->{pass},
        conf(['connect', $name ], 'encryption')
    );
    if ($password ne conf(['connect', $name], 'receive_password')) {
        $conn->done('Invalid credentials');
        notice(connection_invalid =>
            $conn->{ip}, 'Received invalid password');
        return;
    }

    # send my own PASS if I haven't already.
    # this is postponed so that the burst will not be triggered until
    # hostname resolve, ident, etc. are done.
    $conn->on(ready_done => sub {
        my $c = shift;
        M::JELP::Base::send_server_pass($c);
        $c->send('READY');
    }, name => 'jelp.send.password', with_eo => 1)
        if !$conn->{i_sent_pass};

    $conn->reg_continue('id2');
    return 1;
}

sub _send_burst {
    my $conn = shift;

    # the server is registered on our end.
    my $server = $conn->server or return;

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
    my ($conn, $event) = @_;

    # the server is registered, and we haven't sent burst. do so.
    _send_burst($conn) and return;

    # the server is not yet registered; postpone the burst.
    $conn->on(ready_done => \&_send_burst, with_eo => 1)
        unless $conn->{ready};

}

$mod
