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

use utils qw(irc_lc);
use M::TS6::Utils qw(ts6_uid ts6_id uid_from_ts6);

our ($api, $mod, $pool, $me);

our %ts6_incoming_commands = (
    ENCAP_SASL => {
                  # :sid ENCAP     serv_mask  SASL  agent_uid target_uid mode data  ip
        params => '-source(server) *          skip  *         *          *    *     *(opt)',
        code   => \&encap_sasl
    },
    ENCAP_SVSLOGIN => {
                  # :sid ENCAP     serv_mask SVSLOGIN target_uid nick ident cloak act_name
        params => '-source(server) *         skip     *          *    *     *     *',
        code   => \&encap_svslogin
    }
);

our %ts6_outgoing_commands = (
    sasl_host_info      => \&out_sasl_h,    # sent to agent for client info
    sasl_initiate       => \&out_sasl_s,    # sent to agent to initiate auth
    sasl_client_data    => \&out_sasl_c,    # sent to agent with data
    sasl_done           => \&out_sasl_d,    # sent to agent when aborted
    sasl_mechanisms     => \&out_sasl_m,    # request mechanisms
    sasl_conn_info      => \&out_svslogin   # forwarding services-set user fields
);

#########################
### INCOMING COMMANDS ###
#########################

sub encap_sasl {
    my ($server, $msg,

        $source_serv,   # the source server is the services server.
        $serv_mask,     # the server mask. it must be our server name ONLY.
        $agent_uid,     # the UID of the SASL service
        $target_uid,    # the UID of the target

        $mode,          # one of:
                        # 'C' (client data),    'D' (done, abort),
                        # 'H' (host info),      'M' (mechanisms)

        $data,          # base64-encoded data (with 'C') OR (with 'D'):
                        #   'A'     aborted
                        #   'F'     failed to authenticate
                        #   'S'     successfully authenticated

        $ip             # IP address - only used for mode 'H'
    ) = @_;

    $msg->{encap_forwarded}++;

    $agent_uid  = uid_from_ts6($agent_uid);
    $target_uid = uid_from_ts6($target_uid);

    # if the server mask is not exactly equal to this server's name,
    # propagate the message and do nothing else. only SASL agents are permitted
    # to respond to broadcast ('*') messages.
    if (irc_lc($serv_mask) ne irc_lc($me->name)) {
        my @common = (
            $source_serv,       # source server
            $serv_mask,         # server mask target
            $agent_uid,         # the connection's temporary UID
            $target_uid         # UID of SASL service (these are swapped here)
        );

        # start
        if ($mode eq 'S') {
            $msg->forward_to_mask($serv_mask, sasl_initiate =>
                @common,
                $data       # authentication method
            );
        }

        # client data
        elsif ($mode eq 'C') {
            $msg->forward_to_mask($serv_mask, sasl_client_data =>
                @common,
                $data       # base64 encoded client data
            );
        }

        # done
        elsif ($mode eq 'D') {
            $msg->forward_to_mask($serv_mask, sasl_done =>
                @common,
                $data       # done mode
            );
        }

        # host info
        elsif ($mode eq 'H') {
            $msg->forward_to_mask($serv_mask, sasl_host_info =>
                @common,
                $data,      # hostname
                $ip // '0'  # IP address
            );
        }

        # mechanisms
        elsif ($mode eq 'M') {
            $msg->forward_to_mask($serv_mask, sasl_mechanisms =>
                @common,
                $data       # mechanisms
            );
        }

        # don't know
        else {
            L("SASL $mode not known; not forwarded to $serv_mask");
        }

        return 1;
    }

    # find SaslServ using the PROVIDED UID.
    my $saslserv = $pool->lookup_user($agent_uid);
    if (!$saslserv || $saslserv->{server} != $source_serv ||
      !$saslserv->is_mode('service')) {
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
                $conn->{sasl_failures}++;
                M::SASL::check_failures($conn) or return;
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
        $target_uid,    # the UID of the target
        $nick,          # new nick  or '*' if unchanged
        $ident,         # new ident or '*' if unchanged
        $cloak,         # new cloak or '*' if unchanged
        $act_name,      # the account name or '0' to log out
    ) = @_;

    $msg->{encap_forwarded}++;
    $target_uid = uid_from_ts6($target_uid);

    # if the server mask is not exactly equal to this server's name,
    # propagate the message and do nothing else. only SASL agents are permitted
    # to respond to broadcast ('*') messages.
    if (irc_lc($serv_mask) ne irc_lc($me->name)) {
        $msg->forward_to_mask($serv_mask, sasl_conn_info =>
            $source_serv, $serv_mask, $target_uid,
            $nick, $ident, $cloak, $act_name
        );
        return 1;
    }

    # FIXME: (#123) SVSLOGIN is only permitted from services. check that.

    # find the target connection.
    # note that the target MAY OR MAY NOT be registered as a user.
    my $conn = $pool->uid_in_use($target_uid);
    $conn = $conn->conn if $conn && $conn->isa('user');
    if (!$conn) {
        L("could not find target connection");
        return;
    }

    # undef optionals
    undef $nick     if $nick     eq '*';
    undef $ident    if $ident    eq '*';
    undef $cloak    if $cloak    eq '*';
    undef $act_name if $act_name eq '*';

    # update nick, ident, visual host.
    if (!M::SASL::update_user_info($source_serv, $conn,
      $nick, $ident, $cloak, $act_name)) {
        L("failed to update user info");
        return;
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
        $source_uid,        # juno UID source (might be unregistered)
        $target_uid,        # juno UID target
        $temp_host,         # the connection's temporary host
        $temp_ip            # the connection's temporary IP
    ) = @_;

    return sprintf ':%s ENCAP %s SASL %s %s H %s %s',
    ts6_id($source_serv),
    $target_mask,
    ts6_uid($source_uid),   # convert UID to TS6
    ts6_uid($target_uid),   # convert UID to TS6
    $temp_host,
    $temp_ip;
}

sub out_sasl_s {
    my (
        $to_server,         # server we're sending to
        $source_serv,       # source server
        $target_mask,       # server mask target
        $source_uid,        # juno UID source (might be unregistered)
        $target_uid,        # juno UID target
        $auth_method        # authentication method; e.g. PLAIN
    ) = @_;

    return sprintf ':%s ENCAP %s SASL %s %s S %s',
    ts6_id($source_serv),
    $target_mask,
    ts6_uid($source_uid),   # convert UID to TS6
    ts6_uid($target_uid),   # convert UID to TS6
    $auth_method;
}

sub out_sasl_c {
    my (
        $to_server,         # server we're sending to
        $source_serv,       # source server
        $target_mask,       # server mask target
        $source_uid,        # juno UID source (might be unregistered)
        $target_uid,        # juno UID target
        $client_data        # base64 encoded data
    ) = @_;

    return sprintf ':%s ENCAP %s SASL %s %s C %s',
    ts6_id($source_serv),
    $target_mask,
    ts6_uid($source_uid),   # convert UID to TS6
    ts6_uid($target_uid),   # convert UID to TS6
    $client_data;
}

sub out_sasl_d {
    my (
        $to_server,         # server we're sending to
        $source_serv,       # source server
        $target_mask,       # server mask target
        $source_uid,        # juno UID source (might be unregistered)
        $target_uid,        # juno UID target
        $done_mode          # 'A' (aborted), 'F' (failed), or 'S' (succeeded)
    ) = @_;

    return sprintf ':%s ENCAP %s SASL %s %s D %s',
    ts6_id($source_serv),
    $target_mask,
    ts6_uid($source_uid),   # convert UID to TS6
    ts6_uid($target_uid),   # convrert UID to TS6
    $done_mode;
}

sub out_sasl_m {
    my (
        $to_server,         # server we're sending to
        $source_serv,       # source server
        $target_mask,       # server mask target
        $source_uid,        # juno UID source (might be unregistered)
        $target_uid,        # juno UID target
        $mechs
    ) = @_;

    return sprintf ':%s ENCAP %s SASL %s %s M :%s',
    ts6_id($source_serv),
    $target_mask,
    ts6_uid($source_uid),   # convert UID to TS6
    ts6_uid($target_uid),
    $mechs;   # convrert UID to TS6
}

sub out_svslogin {
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
    return sprintf ':%s ENCAP %s SVSLOGIN %s %s %s %s %s',
    ts6_id($source_serv),
    $target_mask,
    ts6_uid($source_uid),   # convert UID to TS6
    $nick,
    $ident,
    $cloak,
    $act_name;
}

$mod
