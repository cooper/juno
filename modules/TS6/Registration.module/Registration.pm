# Copyright (c) 2014, mitchellcooper
#
# Created on Mitchells-Mac-mini.local
# Sat Aug  9 23:22:50 EDT 2014
# Registration.pm
#
# @name:            'TS6::Registration'
# @package:         'M::TS6::Registration'
# @description:     'registration commands for TS6 protocol'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::TS6::Registration;

use warnings;
use strict;
use 5.010;

use utils 'conf';

our ($api, $mod, $pool, $me);

our %registration_commands = (
    CAPAB => {
        code   => \&rcmd_capab,
        params => 1,
        proto  => 'ts6'
    },
    PASS => {
        code   => \&rcmd_pass,
        params => 4,
        proto  => 'ts6'
    },
    SERVER => {
        code   => \&rcmd_server,
        params => 3,
        proto  => 'ts6'
    }
);

# send TS6 registration.
sub send_registration {
    my $connection = shift;
    $connection->send('CAPAB :EUID ENCAP QS');
    $connection->send(sprintf
        'PASS %s TS 6 :%d',
        conf(['listen', $connection->{want} // $connection->{name}], 'send_password'),
        ts6_id($me)
    );
    $connection->send(sprintf
        'SERVER %s %d :%s',
        $me->{name},
        1, # will this ever not be one?
        $me->{desc}
    );
}

# CAPAB
#
# source:       unregistered server
# propagation:  none
# parameters:   space separated capability list
#
# ts6-protocol.txt:209
#
sub rcmd_capab {
    my ($connection, $event, @args) = @_;
}

# PASS
#
# source:       unregistered server
# parameters:   password, 'TS', TS version, SID
#
# ts6-protocol.txt:623
#
sub rcmd_pass {
    my ($connection, $event, $pass, undef, $ts_version, $sid) = @_;
    
    # not supported.
    if ($ts_version ne '6') {
        $connection->done('Incompatible TS version');
        return;
    }
    
    # temporarily store password and SID.
    @$connection{'ts6_sid', 'pass'} = ($sid, $pass);
    
    $connection->reg_continue('id1');
    return 1;
}

# SERVER
#
# 1.
# source:       unregistered server
# parameters:   server name, hopcount, server description
#
# 2.
# source:       server
# propagation:  broadcast
# parameters:   server name, hopcount, server description
#
# ts6-protocol.txt:783
#
sub rcmd_server {
    my ($connection, $event, $name, $desc) = @_;
    @$connection{ qw(name desc) } = ($name, $desc);
    my $s_conf = ['connect', $name];
    
    # haven't gotten SERVER yet.
    if (!defined $connection->{ts6_sid}) {
        $connection->done('Invalid credentials');
        return;
    }
    
    # FIXME: what if this has letters? need conversion method.
    $connection->{sid} = $connection->{ts6_sid} + 0;
    
    # if this was by our request (as in an autoconnect or /connect or something)
    # don't accept any server except the one we asked for.
    if (length $connection->{want} && lc $connection->{want} ne lc $connection->{name}) {
        $connection->done('Unexpected server');
        return;
    }

    # find a matching server.
    if (defined(my $addrs = conf($s_conf, 'address'))) {
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
    
    # check for valid password.
    my $password = utils::crypt(
        $connection->{pass},
        conf($s_conf, 'encryption')
    );
    if ($password ne conf($s_conf, 'receive_password')) {
        $connection->done('Invalid credentials');
        notice(connection_invalid => $connection->{ip}, 'Received invalid password');
        return;
    }

    # send my own CAPAB/PASS/SERVER if I haven't already.
    if (!$connection->{sent_ts6_registration}) {
        send_registration($connection);
    }

    # made it.
    #$connection->fire_event(reg_server => @args); how am I going to do this?
    $connection->{ts6_ircd}  = conf($s_conf, 'ircd') // 'charybdis';
    $connection->{link_type} = 'ts6';
    $connection->reg_continue('id1');
    return 1;
    
}

$mod

