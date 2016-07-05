# Copyright (c) 2016, Mitchell Cooper
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
# @depends.modules:  ['Base::Capabilities', 'Base::RegistrationCommands', 'Base::UserNumerics']
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
    # TODO: once reauthentication is possible,
    # this command must be available post-registration
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

    # already authenticated successfully.
    # TODO: when reauthentication is possible, don't do this.
    if ($connection->{sasl_complete}) {
        $connection->numeric('ERR_SASLALREADY');
        return;
    }

    # if the arg is >400, do not process.
    if (length $arg > 400) {
        $connection->numeric('ERR_SASLTOOLONG');
        return;
    }

    # aborted!
    if ($arg eq '*') {
        abort_sasl($connection);
        return;
    }

    # SaslServ not found or is not a service
    my $saslserv = conf('services', 'saslserv');
    $saslserv = $pool->lookup_user_nick($saslserv);
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
        $saslserv = $agent;
        $saslserv_serv = $saslserv->{location};
        $saslserv_serv->fire_command(sasl_client_data =>
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

# the client has aborted authentication
sub abort_sasl {
    my $connection = shift;

    # tell the user it's over.
    $connection->numeric('ERR_SASLABORTED');

    # find the SASL agent.
    my $saslserv = $pool->lookup_user($connection->{sasl_agent}) or return;

    # tell the agent that the user aborted the exchange.
    my $saslserv_serv = $saslserv->{location};
    $saslserv_serv->fire_command(sasl_aborted =>
        $me,                        # source server
        $saslserv_serv->name,       # server mask target
        $connection->{uid},         # the connection's temporary UID
        $saslserv->{uid}            # UID of SASL service
    );

}

# update user mask. * = unchanged
sub update_user_info {
    my ($conn, $nick, $ident, $cloak) = @_;

    # TODO: if the nickname is already in use, kill it. use ->nick_in_use()?

    # which things are we updating?
    my $update_nick  = length $nick  && $nick  ne '*' && utils::validnick($nick);
    my $update_ident = length $ident && $ident ne '*' && utils::validident($ident);
    my $update_cloak = length $cloak && $cloak ne '*' && 1; # TODO: validhost()

    # registered user.
    my $user = $conn->{type};
    if ($user && $user->isa('user')) {
        # TODO: this, for SASL reauthentication
        return;
    }

    # non-registered connection.
    $conn->{nick}  = $nick  if $update_nick;
    $conn->{ident} = $ident if $update_ident;
    $conn->{cloak} = $cloak if $update_cloak;

    return 1;
}

# update the account name. none = logout
sub update_account {
    my ($conn, $act_name) = @_;
    my $cloak = $conn->{cloak} // $conn->{host};

    # TODO: for SASL reauthentication, update $user->{account}

    # log in
    if ($act_name) {
        $conn->{sasl_account} = $act_name;
        $conn->numeric(RPL_LOGGEDIN =>
            $conn->{nick}.'!'.$conn->{ident}.'@'.$cloak,
            $act_name, $act_name
        );
    }

    # log out
    else {
        delete $conn->{sasl_account};
        $conn->numeric(RPL_LOGGEDOUT =>
            $conn->{nick}.'!'.$conn->{ident}.'@'.$cloak
        );
    }

    return 1;
}

# we've already sent RPL_LOGGEDIN at this point.
sub on_user_propagated {
    my ($user, $event) = @_;
    my $act_name = delete $user->{sasl_account} or return;
    L("SASL login $$user{nick} as $act_name");
    $user->{account} = { name => $act_name };
}

$mod
