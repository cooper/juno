# Copyright (c) 2016, Mitchell Cooper
#
# JELP.pm
#
# @name:            'SASL::JELP'
# @package:         'M::SASL::JELP'
# @description:     'JELP SASL implementation'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
# depends on JELP::Base, but don't put that here.
# companion submodule loading takes care of it.
#
package M::SASL::JELP;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool, $me);

our %jelp_incoming_commands = (
    SASLHOST => {
                  # :sid SASLHOST   serv_mask source_uid target_uid host ip
        params => '-source(server)  *         *          *          *    *',
        code   => \&saslhost
    },
    SASLSTART => {
                  # :sid SASLSTART   serv_mask source_uid target_uid auth_method
        params => '-source(server)   *         *          *          *',
        code   => \&saslstart
    },
    SASLDATA => {
                  # :sid SASLDATA    serv_mask source_uid target_uid client_data
        params => '-source(server)   *         *          *          *',
        code   => \&sasldata
    },
    SASLDONE => {
                  # :sid SASLDONE    serv_mask source_uid target_uid done_mode
        params => '-source(server)   *         *          *          *',
        code   => \&sasldone
    },
    SASLSET => {
                  # :sid SASLSET   serv_mask target_uid nick ident cloak act_name
        params => '-source(server) *         *          *    *     *     *',
        code   => \&saslset
    },
    SASLMECHS => {
                  # # :sid SASLDONE    serv_mask source_uid target_uid  mechs
        params => '-source(server)     *         *          *           *',
        code   => \&saslmechs
    }
);

our %jelp_outgoing_commands = (
    sasl_host_info      => \&out_saslhost,
    sasl_initiate       => \&out_saslstart,
    sasl_client_data    => \&out_sasldata,
    sasl_done           => \&out_sasldone,
    sasl_conn_info      => \&out_saslset,
    sasl_mechanisms     => \&out_saslmechs
);

#########################
### INCOMING COMMANDS ###
#########################

sub saslhost {
    my ($server, $msg,
        $source_serv,   # services server
        $serv_mask,     # server mask
        $source_uid,    # source UID
        $target_uid,    # target UID
        $host,          # user hostname
        $ip             # user IP address
    ) = @_;

    # we don't do anything with this.
    return 1 if lc $serv_mask eq lc $me->name;

    #=== Forward ===#
    $msg->forward_to_mask($serv_mask, sasl_client_data => @_[2..7]);

    return 1;
}

sub saslstart {
    my ($server, $msg,
        $source_serv,   # services server
        $serv_mask,     # server mask
        $source_uid,    # source UID
        $target_uid,    # target UID
        $auth_method    # authentication method
    ) = @_;

    # we don't do anything with this.
    return 1 if lc $serv_mask eq lc $me->name;

    #=== Forward ===#
    $msg->forward_to_mask($serv_mask, sasl_initiate => @_[2..6]);

    return 1;
}

sub sasldata {
    my ($server, $msg,
        $source_serv,   # services server
        $serv_mask,     # server mask
        $source_uid,    # source UID
        $target_uid,    # target UID
        $data           # client data
    ) = @_;

    #=== Forward ===#
    # it has to be me.
    if (lc $serv_mask ne lc $me->name) {
        $msg->forward_to_mask($serv_mask, sasl_client_data => @_[2..6]);
        return 1;
    }

    my $conn = find_connection($target_uid) or return;

    # send AUTHENTICATE
    $conn->send("AUTHENTICATE $data");
    $conn->{sasl_messages}++;

    return 1;
}

sub sasldone {
    my ($server, $msg,
        $source_serv,   # services server
        $serv_mask,     # server mask
        $source_uid,    # source UID
        $target_uid,    # target UID
        $done_mode      # reason for being done
    ) = @_;

    #=== Forward ===#
    # it has to be me.
    if (lc $serv_mask ne lc $me->name) {
        $msg->forward_to_mask($serv_mask, sasl_done => @_[2..6]);
        return 1;
    }

    my $conn = find_connection($target_uid) or return;

    # F - authentication failure.
    if ($done_mode eq 'F') {
        $conn->numeric('ERR_SASLFAIL');

        # if we never received client data,
        # these are just unknown mechanism errors.
        if ($conn->{sasl_messages}) {
            # TODO: check if they've failed 9000 times.
            $conn->{sasl_failures}++;
        }

    }

    # S - authentication success.
    elsif ($done_mode eq 'S') {
        $conn->numeric('RPL_SASLSUCCESS');
        delete $conn->{sasl_failures};
        $conn->{sasl_complete} = 1;
    }

    # not sure. do NOT return, though.
    else {
        L("unknown SASL termination code $done_mode");
    }

    # SASL is complete. reset this stuff.
    delete $conn->{sasl_agent};
    delete $conn->{sasl_messages};

    return 1;
}

sub saslset {
    my ($server, $msg,
        $source_serv,   # services server
        $serv_mask,     # server mask
        $target_uid,    # target UID
        $nick,          # nickname or '*'
        $ident,         # ident or '*'
        $cloak,         # cloak or '*'
        $act_name       # account name or '*'
    ) = @_;

    #=== Forward ===#
    # it has to be me.
    if (lc $serv_mask ne lc $me->name) {
        $msg->forward_to_mask($serv_mask, sasl_done => @_[2..8]);
        return 1;
    }

    my $conn = find_connection($target_uid) or return;

    # update nick, ident, visual host.
    if (!M::SASL::update_user_info($conn, $nick, $ident, $cloak)) {
        L("failed to update user info");
        return;
    }

    # TODO: for reauthentication, need to send out some broadcast command to
    # notify other servers of several user field changes at once. this would be
    # similar to TS6's SIGNON command.

    # update the account.
    if (!M::SASL::update_account($conn, $act_name || undef)) {
        L("failed to update account");
        return;
    }

    return 1;
}

sub saslmechs {
    my ($server, $msg,
        $source_serv,   # services server
        $serv_mask,     # server mask
        $source_uid,    # source UID
        $target_uid,    # target UID
        $mechs          # mechanisms
    ) = @_;

    # we don't do anything with this.
    return 1 if lc $serv_mask eq lc $me->name;

    #=== Forward ===#
    $msg->forward_to_mask($serv_mask, sasl_mechanisms => @_[2..6]);

    return 1;
}

#########################
### OUTGOING COMMANDS ###
#########################

sub out_saslhost {
    my (
        $to_server,         # server we're sending to
        $source_serv,       # source server
        $target_mask,       # server mask target
        $source_uid,        # juno UID source (might be unregistered)
        $target_uid,        # juno UID target
        $temp_host,         # the connection's temporary host
        $temp_ip            # the connection's temporary IP
    ) = @_;

    return sprintf ':%s SASLHOST %s %s %s %s %s',
    $source_serv->id,
    $target_mask,
    $source_uid,
    $target_uid,
    $temp_host,
    $temp_ip;
}

sub out_saslstart {
    my (
        $to_server,         # server we're sending to
        $source_serv,       # source server
        $target_mask,       # server mask target
        $source_uid,        # juno UID source (might be unregistered)
        $target_uid,        # juno UID target
        $auth_method        # authentication method; e.g. PLAIN
    ) = @_;

    return sprintf ':%s SASLSTART %s %s %s %s',
    $source_serv->id,
    $target_mask,
    $source_uid,
    $target_uid,
    $auth_method;
}

sub out_sasldata {
    my (
        $to_server,         # server we're sending to
        $source_serv,       # source server
        $target_mask,       # server mask target
        $source_uid,        # juno UID source (might be unregistered)
        $target_uid,        # juno UID target
        $client_data        # base64 encoded data
    ) = @_;

    return sprintf ':%s SASLDATA %s %s %s %s',
    $source_serv->id,
    $target_mask,
    $source_uid,
    $target_uid,
    $client_data;
}

sub out_sasldone {
    my (
        $to_server,         # server we're sending to
        $source_serv,       # source server
        $target_mask,       # server mask target
        $source_uid,        # juno UID source (might be unregistered)
        $target_uid,        # juno UID target
        $done_mode          # 'A' (aborted), 'F' (failed), or 'S' (succeeded)
    ) = @_;

    return sprintf ':%s SASLDONE %s %s %s %s',
    $source_serv->id,
    $target_mask,
    $source_uid,
    $target_uid,
    $done_mode;
}

sub out_saslset {
    my (
        $to_server,     # server we're sending to
        $source_serv,   # source server
        $target_mask,   # server mask target
        $source_uid,    # juno UID source (might be unregistered)
        $nick,          # nickname or '*'
        $ident,         # ident or '*'
        $cloak,         # visible host or '*'
        $act_name       # account name or '*'
    ) = @_;

    return sprintf ':%s SASLSET %s %s %s %s %s %s',
    $source_serv->id,
    $target_mask,
    $source_uid,
    $nick,
    $ident,
    $cloak,
    $act_name;
}

sub out_saslmechs {
    my (
        $to_server,         # server we're sending to
        $source_serv,       # source server
        $target_mask,       # server mask target
        $source_uid,        # juno UID source (might be unregistered)
        $target_uid,        # juno UID target
        $mechs
    ) = @_;

    return sprintf ':%s SASLMECHS %s %s %s :%s',
    $source_serv->id,
    $target_mask,
    $source_uid,
    $target_uid,
    $mechs;
}

# find the target connection.
#
# note that the target MAY OR MAY NOT be registered as a user.
# we are not yet supported registered users.
#
sub find_connection {
    my $target_uid = shift;
    my $conn = $pool->uid_in_use($target_uid);

    # TODO: not yet implemented
    return if $conn && $conn->isa('user');

    # not found
    if (!$conn) {
        L("could not find target connection for $target_uid");
        return;
    }

    return $conn;
}

$mod
