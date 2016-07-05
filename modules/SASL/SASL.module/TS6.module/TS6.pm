# Copyright (c) 2016, Mitchell Cooper
#
# TS6.pm
#
# @name:            'SASL::TS6'
# @package:         'M::SASL::TS6'
# @description:     'TS6 SASL implementation'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
# depends on TS6::Base, but don't put that here.
# companion submodule loading takes care of it.
#
package M::SASL::TS6;

use warnings;
use strict;
use 5.010;

use utils qw(keys_values conf);
use M::TS6::Utils qw(ts6_uid ts6_id uid_from_ts6);

our ($api, $mod, $pool, $me);

our %ts6_incoming_commands = (
    ENCAP_SASL => {
                  # :sid ENCAP     serv_mask  SASL agent_uid target_uid mode data
        params => '-source(server) *          *    *         *          *    *',
        code   => \&encap_sasl
    },
    ENCAP_SVSLOGIN => {
                  # :sid ENCAP     serv_mask SVSLOGIN target_uid nick ident cloak act_name
        params => '-source(server) *         *        *          *    *     *     *',
        code   => \&encap_svslogin
    }
);

our %ts6_outgoing_commands = (
    sasl_host_info      => \&out_sasl_h,
    sasl_initiate       => \&out_sasl_s,
    sasl_client_data    => \&out_sasl_c,
    sasl_aborted        => \&out_sasl_d
);

sub init {
    return 1;
}

#########################
### INCOMING COMMANDS ###
#########################

sub encap_sasl {
    my ($server, $msg,
        $source_serv,   # the source server is the services server.
        $serv_mask,     # the server mask. it must be our server name ONLY.
        undef,          # 'SASL'
        $agent_uid,     # the UID of the SASL service
        $target_uid,    # the UID of the target
        $mode,          # 'C' (client data) or 'D' (done, abort)
        $data           # base64-encoded data (with 'C') OR (with 'D'):
                        #   'A'     aborted
                        #   'F'     failed to authenticate
                        #   'S'     successfully authenticated
    ) = @_;

    $msg->{encap_forwarded} = 1;
    $agent_uid  = uid_from_ts6($agent_uid);
    $target_uid = uid_from_ts6($target_uid);

    # if the server mask is not exactly equal to this server's name,
    # propagate the message and do nothing else. only SASL agents are permitted
    # to respond to broadcast ('*') messages.
    if (lc $serv_mask ne lc $me->name) {
        # TODO: custom forward
        # $msg->forward_to_mask()
        return;
    }

    # find SaslServ using the PROVIDED UID. we do NOT have to check here that
    # it's a service, only that it exists and that the source server is its owner.
    my $saslserv = $pool->lookup_user($agent_uid);
    if (!$saslserv || $saslserv->{server} != $source_serv) {
        L("could not find SASL agent OR server/UID mistatch");
        return;
    }

    # find the target connection. ensure that its sasl_agent is the one
    # specified in this command ($saslserv).
    #
    # note that the target MAY OR MAY NOT be registered as a user.
    # we are only concerned with the actual connection here.
    #
    my $conn = $pool->uid_in_use($target_uid);
    $conn = $conn->conn if $conn && $conn->isa('user');
    $conn->{sasl_agent} //= $saslserv->id;
    if (!$conn || $conn->{sasl_agent} ne $saslserv->id) {
        L("could not find target connection OR wrong agent");
        return;
    }

    # EVERYTHING LOOKS OK.
    #==============================

    # Mode C = Client data.
    if ($mode eq 'C') {
        $conn->send("AUTHENTICATE $data");
        $conn->{sasl_messages}++;
    }

    # Mode D = Done.
    # when $mode eq 'D', $data is the reason for being done.
    elsif ($mode eq 'D') {

        # F - authentication failure.
        if ($data eq 'F') {
            $conn->numeric('ERR_SASLFAIL');

            # if we never received client data,
            # these are just unknown mechanism errors.
            if ($conn->{sasl_messages}) {
                # TODO: check if they've failed 9000 times.
                $conn->{sasl_failures}++;
            }

        }

        # S - authentication success.
        elsif ($data eq 'S') {
            $conn->numeric('RPL_SASLSUCCESS');
            delete $conn->{sasl_failures};
            $conn->{sasl_complete} = 1;
        }

        # not sure. do NOT return, though.
        else {
            L("unknown SASL termination code $data");
        }

        # SASL is complete. reset this stuff.
        delete $conn->{sasl_agent};
        delete $conn->{sasl_messages};

    }

    # Mode M = Mechanisms.
    elsif ($mode eq 'M') {
        $conn->numeric(RPL_SASLMECHS => $data);
    }

    # unknown mode.
    else {
        L("unknown SASL mode $mode");
        return;
    }

    return 1;
}

sub encap_svslogin {
    my ($server, $msg,
        $source_serv,   # the source server is the services server
        $serv_mask,     # the server mask. it must be our server name ONLY
        undef,          # 'SVSLOGIN'
        $target_uid,    # the UID of the target
        $nick,          # new nick  or '*' if unchanged
        $ident,         # new ident or '*' if unchanged
        $cloak,         # new cloak or '*' if unchanged
        $act_name,      # the account name or '0' to log out
    ) = @_;

    $msg->{encap_forwarded} = 1;
    $target_uid = uid_from_ts6($target_uid);

    # if the server mask is not exactly equal to this server's name,
    # propagate the message and do nothing else. only SASL agents are permitted
    # to respond to broadcast ('*') messages.
    if (lc $serv_mask ne lc $me->name) {
        # TODO: custom forward
        # $msg->forward_to_mask()
        return;
    }

    # FIXME: SVSLOGIN is only permitted from services. check that.

    # find the target connection.
    #
    # note that the target MAY OR MAY NOT be registered as a user.
    # we are only concerned with the actual connection here.
    #
    # TODO: I guess actually if the user is registered, update all this
    # info the correct way... then send SIGNON.
    # this is for IRCv3.2 reauthentication
    #
    my $conn = $pool->uid_in_use($target_uid);
    return if $conn && $conn->isa('user');          # FIXME: not yet implemented
    if (!$conn) {
        L("could not find target connection");
        return;
    }

    # OK, update all the stuff on $conn...
    # FIXME: don't assume that these are all valid!
    my %stuff = keys_values(
        [ qw(nick ident cloak sasl_account) ],
        [ $nick, $ident, $cloak, $act_name  ]
    );
    foreach my $key (keys %stuff) {
        my $value = $stuff{$key};
        next if $value eq '*';
        $conn->{$key} = $value;
    }

    # TODO: if the nickname is already in use, kill it. use ->nick_in_use().

    # send the logged in/out numerics now.
    if ($act_name) {
        $conn->numeric(RPL_LOGGEDIN =>
            $conn->{nick}.'!'.$conn->{ident}.'@'.($conn->{cloak} // $conn->{host}),
            $act_name, $act_name
        );
    }
    else {
        $conn->numeric(RPL_LOGGEDOUT =>
            $conn->{nick}.'!'.$conn->{ident}.'@'.($conn->{cloak} // $conn->{host})
        );
    }

    return 1;
}

#########################
### OUTGOING COMMANDS ###
#########################

sub out_sasl_h {
    my (
        $to_server,         # server we're sending to
        $source_serv,       # source server
        $target_mask,       # server mask target
        $temp_uid,          # the connection's temporary UID
        $saslserv_uid,      # UID of SASL service
        $temp_host,         # the connection's temporary host
        $temp_ip            # the connection's temporary IP
    ) = @_;

    return sprintf ':%s ENCAP %s SASL %s %s H %s %s',
    ts6_id($source_serv),
    $target_mask,
    ts6_uid($temp_uid),     # convert UID to TS6
    ts6_uid($saslserv_uid), # convert UID to TS6
    $temp_host,
    $temp_ip;
}

sub out_sasl_s {
    my (
        $to_server,         # server we're sending to
        $source_serv,       # source server
        $target_mask,       # server mask target
        $temp_uid,          # the connection's temporary UID
        $saslserv_uid,      # UID of SASL service
        $auth_method        # authentication method; e.g. PLAIN
    ) = @_;

    return sprintf ':%s ENCAP %s SASL %s %s S %s',
    ts6_id($source_serv),
    $target_mask,
    ts6_uid($temp_uid),     # convert UID to TS6
    ts6_uid($saslserv_uid), # convert UID to TS6
    $auth_method;
}

sub out_sasl_c {
    my (
        $to_server,         # server we're sending to
        $source_serv,       # source server
        $target_mask,       # server mask target
        $temp_uid,          # the connection's temporary UID
        $saslserv_uid,      # UID of SASL service
        $client_data        # base64 encoded data
    ) = @_;

    return sprintf ':%s ENCAP %s SASL %s %s C %s',
    ts6_id($source_serv),
    $target_mask,
    ts6_uid($temp_uid),     # convert UID to TS6
    ts6_uid($saslserv_uid), # convert UID to TS6
    $client_data;
}

sub out_sasl_d {
    my (
        $to_server,         # server we're sending to
        $source_serv,       # source server
        $target_mask,       # server mask target
        $temp_uid,          # the connection's temporary UID
        $saslserv_uid,      # UID of SASL service
    ) = @_;

    return sprintf ':%s ENCAP %s SASL %s %s D A',
    ts6_id($source_serv),
    $target_mask,
    ts6_uid($temp_uid),     # convert UID to TS6
    ts6_uid($saslserv_uid); # convert UID to TS6
}

$mod
