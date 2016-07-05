# Copyright (c) 2014, matthew
#
# Created on mattbook
# Thu Jun 26 22:26:14 EDT 2014
# SASL.pm
#
# @name:            'SASL'
# @package:         'M::SASL'
# @description:     'Provides SASL authentication'
#
# @depends.modules:  ['Base::Capabilities', 'Base::RegistrationCommands']
#
# @author.name:     'Matthew Barksdale'
# @author.website:  'https://github.com/mattwb65'
#
package M::SASL;

use warnings;
use strict;
use 5.010;

use MIME::Base64;
use utils qw(conf);

our ($api, $mod, $pool, $me);

our %user_numerics = (
    # Provided by Core: RPL_LOGGEDIN, RPL_LOGGEDOUT, RPL_NICKLOCKED
    RPL_SASLSUCCESS => [ 903, ':SASL authentication successful'             ],
    ERR_SASLFAIL    => [ 904, ':SASL authentication failed'                 ],
    ERR_SASLTOOLONG => [ 905, ':SASL message too long'                      ],
    ERR_SASLABORTED => [ 906, ':SASL authentication aborted'                ],
    ERR_SASLALREADY => [ 907, ':You have already authenticated using SASL'  ],
    RPL_SASLMECHS   => [ 908, '%s :are available SASL mechanisms'           ]
);

sub init {

    # sasl capability
    $mod->register_capability('sasl');

    # AUTHENTICATE command
    $mod->register_registration_command(
        name       => 'AUTHENTICATE',
        code       => \&rcmd_authenticate,
        paramaters => 1
    ) or return;

    # log the user in once registered
    $pool->on('user.initially_propagated' => \&on_user_propagated,
        with_eo => 1
    );

    # load SASL::TS6 when TS6::Base is loaded
    $mod->add_companion_submodule('TS6::Base', 'TS6');

    return 1;
}

# Registration command: AUTHENTICATE
sub rcmd_authenticate {
    my ($connection, $event, $arg) = @_;

    # if the connection does not have the sasl capability, drop the message.
    return if !$connection->has_cap('sasl');

    # if the arg is >400, do not process.
    if (length $arg > 400) {
        $connection->numeric('ERR_SASLTOOLONG');
        return;
    }

    # aborted!
    if ($arg eq '*') {
        $connection->numeric('ERR_SASLABORTED');
        return;
    }

    # already authenticated successfully.
    if ($connection->{sasl_complete}) {
        $connection->numeric('ERR_SASLALREADY');
        return;
    }

    # SaslServ not found or is not a service
    my $saslserv = find_saslserv();
    if (!$saslserv || !$saslserv->is_mode('service') || $saslserv->is_local) {
        $connection->numeric('ERR_SASLABORTED');
        return;
    }

    # allocate a UID if we haven't already.
    if (!length $connection->{uid}) {
        my $uid = $connection->{uid} = $me->{sid}.$pool->{user_i}++;
        $pool->reserve_uid($uid, $connection);
    }

    # find this connection's SASL agent server. sasl_agent is stored only after
    # the SASL S request has been sent to the SASL agent.
    my $agent = $pool->lookup_user($connection->{sasl_agent});

    # this client has no agent.
    # send out SASL S and SASL H.
    my $saslserv_serv = $saslserv->{location};
    if (!$agent) {

        # shared between SASL S and SASL H.
        my @common = (
            $me,                        # source server
            $saslserv_serv->name,       # server mask target
            $connection->{uid},         # the connection's temporary UID
            $saslserv->{uid},           # UID of SASL service
        );

        # send SASL H.
        $saslserv_serv->fire_command(sasl_host_info =>
            @common,                    # common parameters
            $connection->{host},        # connection host
            $connection->{ip}           # connection IP address
        );

        # send SASL S.
        $saslserv_serv->fire_command(sasl_initiate =>
            @common,                    # common parameters
            $arg                        # authentication method; e.g. PLAIN
        );

        # store the SASL agent.
        $connection->{sasl_agent} = $saslserv->id;

    }

    # the client has an agent. this is the AUTHENTICATE <base64>.
    # send out SASL C.
    elsif (length $arg) {
        $agent->{location}->fire_command(sasl_client_data =>
            $me,                        # source server
            $saslserv_serv->name,       # server mask target
            $connection->{uid},         # the connection's temporary UID
            $saslserv->{uid},           # UID of SASL service
            $arg                        # base64 encoded client data
        );
    }

    # not sure what to do with this.
    else {
        $connection->numeric('ERR_SASLABORTED');
        return;
    }

    return 1;
}

sub find_saslserv {
    my $saslserv = conf('services', 'saslserv');
    return $pool->lookup_user_nick($saslserv);
}

# we've already sent RPL_LOGGEDIN at this point.
sub on_user_propagated {
    my ($user, $event) = @_;
    my $act_name = delete $user->{sasl_account} or return;
    L("SASL login $$user{nick} as $act_name");
    $user->{account} = { name => $act_name };
}

$mod
