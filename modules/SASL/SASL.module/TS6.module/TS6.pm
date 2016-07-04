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

use M::TS6::Utils qw(ts6_uid ts6_id);

our ($api, $mod, $pool, $me);

our %ts6_outgoing_commands = (
    sasl_host_info      => \&out_sasl_h,
    sasl_initiate       => \&out_sasl_s,
    sasl_client_data    => \&out_sasl_c
);

sub init {
    return 1;
}

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


$mod
