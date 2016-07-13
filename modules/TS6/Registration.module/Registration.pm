# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-Mac-mini.local
# Sat Aug  9 23:22:50 EDT 2014
# Registration.pm
#
# @name:            'TS6::Registration'
# @package:         'M::TS6::Registration'
# @description:     'registration commands for TS6 protocol'
#
# @depends.modules: ['Base::RegistrationCommands', 'TS6::Utils']
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::TS6::Registration;

use warnings;
use strict;
use 5.010;

use utils qw(conf irc_match notice ref_to_list irc_lc);
use M::TS6::Utils qw(ts6_id sid_from_ts6 user_from_ts6 ts6_uid);

our ($api, $mod, $pool, $conf, $me);

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
    },
    PING => {
        code   => \&rcmd_ping,
        params => 1,
        proto  => 'ts6'
    }
);

sub init {
    $pool->on('connection.server_ready' => \&server_ready,
        with_eo => 1,
        name    => 'ts6.server_ready'
    );
    $pool->on('connection.ready_done' => \&connection_ready,
        with_eo => 1,
        name    => 'ts6.ready_done'
    );
    return 1;
}

# send TS6 registration.
sub send_registration {
    my $connection = shift;

    # EUID      = extended user burst support
    # ENCAP     = enhanced command routing support
    # QS        = quit storm support
    # TB        = topic burst support
    # EOPMOD    = special rules for +z, extended topic burst support
    # EX        = ban exception (+e) support
    # IE        = invite exception (+I) support
    # SERVICES  = support for +S (network service) and +r (channel registered)

    $connection->send(sprintf
        'PASS %s TS 6 :%s',
        conf(['connect', $connection->{want} // $connection->{name}], 'send_password'),
        ts6_id($me)
    );

    $connection->send('CAPAB :EUID ENCAP QS TB EOB EX IE SERVICES SAVE RSFNC');

    $connection->send(sprintf
        'SERVER %s %d :%s',
        $me->{name},
        1, # will this ever not be one?
        $me->{desc}
    );

    $connection->send("PING :$$me{name}");
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
    my ($connection, $event, @flags) = @_;
    $connection->add_cap(map { split /\s+/ } @flags);
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
    my ($connection, $event, $name, undef, $desc) = @_;
    @$connection{ qw(name desc ircd proto) } = ($name, $desc, -1, -1);
    my $s_conf = ['connect', $name];

    # hidden?
    my $sub = \substr($connection->{desc}, 0, 4);
    if (length $sub && $$sub eq '(H) ') {
        $$sub = '';
        $connection->{hidden} = 1;
    }

    # haven't gotten PASS yet.
    if (!defined $connection->{ts6_sid}) {
        $connection->done('Invalid credentials');
        return;
    }

    $connection->{sid} = sid_from_ts6($connection->{ts6_sid});

    # if this was by our request (as in an autoconnect or /connect or something)
    # don't accept any server except the one we asked for.
    if (length $connection->{want} &&
    irc_lc($connection->{want}) ne irc_lc($connection->{name})) {
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
    # this is postponed until the connection is ready.
    $connection->{ts6_reg_pending} = 1;

    # made it.
    #$connection->fire_event(reg_server => @args); how am I going to do this?
    $connection->{ts6_ircd}  = conf($s_conf, 'ircd') // 'charybdis';
    $connection->{link_type} = 'ts6';
    $connection->reg_continue('id2');

    return 1;

}

# the first ping here indicates end of burst.
sub rcmd_ping {
    my ($connection, $event) = @_;
    my $server = $connection->server or return;
    $server->{is_burst} or return;

    # how much time has elapsed?
    my $time    = delete $server->{is_burst};
    my $elapsed = time - $time;
    $server->{sent_burst} = time;

    L("end of burst from $$server{name}");
    notice(server_endburst => $server->{name}, $server->{sid}, $elapsed);
}

sub server_ready {
    my $server = shift->server or return;
    return unless $server->{link_type} eq 'ts6';

    # apply modes.
    M::TS6::Utils::register_modes($server);

    # add user lookup functions.
    $server->set_functions(
        uid_to_user => \&user_from_ts6,
        user_to_uid => \&ts6_uid
    );

}

# connection is ready event.
sub connection_ready {
    my $connection = shift;
    my $server = $connection->server or return;
    return unless $server->{link_type} eq 'ts6';
    return unless delete $server->{ts6_reg_pending};

    # search for required CAPABs.
    foreach my $need (qw(EUID TB ENCAP QS)) {
        next if $server->has_cap($need);
        $connection->done("Missing required CAPABs ($need)");
        return;
    }

    # time to send my own credentials.
    send_registration($connection);

    # since I did not initiate this, I have to send my burst first.
    # I am to send it now, immediately after sending my registration,
    # even before the initiator has verified my credentials.
    $server->send_burst if !$server->{i_sent_burst};

    # at this point, we will say that the server is starting its burst.
    # however, it still may deny our own credentials.
    $server->{is_burst} = time;
    L("$$server{name} is bursting information");
    notice(server_burst => $server->{name}, $server->{sid});

}

$mod
