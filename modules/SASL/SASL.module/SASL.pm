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
use Scalar::Util qw(weaken);
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
    $mod->register_capability('sasl', sticky => 1, manual_enable => 1);

    # AUTHENTICATE command
    # TODO: (#83) once reauthentication is possible,
    # this command must be available post-registration
    $mod->register_registration_command(
        name       => 'AUTHENTICATE',
        code       => \&rcmd_authenticate,
        paramaters => 1
    ) or return;

    # log the user in once registered
    $pool->on('user.initially_set_modes' => \&on_user_set_modes,
        with_eo => 1
    );

    # protocol submodules
    $mod->add_companion_submodule('TS6::Base',  'TS6');
    $mod->add_companion_submodule('JELP::Base', 'JELP');

    # find saslserv to immediately enable the sasl capability
    # if it is present now
    find_saslserv();

    return 1;
}

sub is_valid_agent {
    my $agent = shift;
    return if !$agent || !$agent->is_mode('service');
    return $agent;
}

my $looking_for_saslserv;
sub find_saslserv {
    my $saslserv = conf('services', 'saslserv') or return;
    $saslserv = $pool->lookup_user_nick($saslserv);

    # we can't find saslserv
    if (!is_valid_agent($saslserv)) {

        # already watching
        return if $looking_for_saslserv;
        $looking_for_saslserv++;
        L('Watching for SASL agent');

        # watch for the agent
        weaken(my $weak_pool = $pool);
        $pool->on('user.new' => sub {
            my ($user, $event) = @_;
            return if !is_valid_agent($user) || !find_saslserv() || !$weak_pool;

            # we found it, so delete this
            $weak_pool->delete_callback('user.new', 'saslserv.detector');
            undef $looking_for_saslserv;

        }, 'saslserv.detector');

        return;
    }

    # this is the first time we've found this agent
    if (!$saslserv->{monitoring}) {
        $saslserv->{monitoring}++;

        # watch SaslServ in case it disappears
        weaken(my $weak_mod = $mod);
        $saslserv->on(quit => sub {
            my ($saslserv) = @_;
            $weak_mod or return;
            $weak_mod->disable_capability('sasl');
            L('Lost SaslServ');
        }, 'saslserv.monitor');

        # enable the capability for now
        $mod->enable_capability('sasl');
        L('Found SASL agent');
    }

    return $saslserv;
}

# Registration command: AUTHENTICATE
sub rcmd_authenticate {
    my ($connection, $event, $arg) = @_;

    # if the connection does not have the sasl capability, drop the message.
    return if !$connection->has_cap('sasl');

    # already authenticated successfully.
    # TODO: (#83) when reauthentication is possible, don't do this.
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

    # SaslServ not found
    my $saslserv = find_saslserv();
    if (!$saslserv) {
        abort_sasl($connection);
        return;
    }

    # allocate a UID if we haven't already.
    if (!length $connection->{uid}) {
        my $uid = $connection->{uid} = $me->{sid}.$pool->{user_i}++;
        $pool->reserve_uid($uid, $connection);
    }

    # find this connection's SASL agent server. sasl_agent is stored only after
    # the SASL S request has been sent to the SASL agent.
    my $agent = is_valid_agent($pool->lookup_user($connection->{sasl_agent}));

    # this client has no agent.
    # send out SASL S and SASL H.
    if (!$agent) {
        my $saslserv_serv = $saslserv->{server};
        my $saslserv_loc  = $saslserv->{location};

        # shared between SASL S and SASL H.
        my @common = (
            $me,                        # source server
            $saslserv_serv->name,       # server mask target
            $connection->{uid},         # the connection's temporary UID
            $saslserv->{uid},           # UID of SASL service
        );

        # send SASL H.
        $saslserv_loc->fire_command(sasl_host_info =>
            @common,                    # common parameters
            $connection->{host},        # connection host
            $connection->{ip}           # connection IP address
        );

        # send SASL S.
        $saslserv_loc->fire_command(sasl_initiate =>
            @common,                    # common parameters
            $arg                        # authentication method; e.g. PLAIN
        );

        # store the SASL agent.
        $connection->{sasl_agent} = $saslserv->id;

    }

    # the client has an agent. this is the AUTHENTICATE <base64>.
    # send out SASL C.
    elsif (length $arg) {
        my $agent_serv = $agent->{server};
        my $agent_loc  = $agent->{location};

        # send data
        $agent_loc->fire_command(sasl_client_data =>
            $me,                        # source server
            $agent_serv->name,          # server mask target
            $connection->{uid},         # the connection's temporary UID
            $agent->{uid},              # UID of SASL service
            $arg                        # base64 encoded client data
        );

    }

    # not sure what to do with this.
    else {
        abort_sasl($connection);
        return;
    }

    return 1;
}

# the client has aborted authentication
sub abort_sasl {
    my $connection = shift;
    return if $connection->{sasl_complete};

    # tell the user it's over.
    $connection->numeric('ERR_SASLABORTED');

    # find the SASL agent.
    my $agent = $pool->lookup_user($connection->{sasl_agent}) or return;

    # tell the agent that the user aborted the exchange.
    my $agent_serv = $agent->{server};
    my $agent_loc  = $agent->{location};
    $agent_loc->fire_command(sasl_done =>
        $me,                        # source server
        $agent_serv->name,          # server mask target
        $connection->{uid},         # the connection's temporary UID
        $agent->{uid},              # UID of SASL service
        'A'                         # for abort
    );

}

# update user mask. * = unchanged
sub update_user_info {
    my ($conn, $nick, $ident, $cloak) = @_;

    # which things are we updating?
    my $update_nick  = length $nick  && $nick  ne '*' && utils::validnick($nick, 1);
    my $update_ident = length $ident && $ident ne '*' && utils::validident($ident);
    my $update_cloak = length $cloak && $cloak ne '*' && 1; # TODO: (#157) validhost()

    # look for an existing user/conn by this nick.
    # TODO: (#83) for reauth, check if $existing == the user OR the conn
    my $existing = $pool->nick_in_use($nick); # could be a user
    if ($update_nick && $existing && $existing != $conn) {

        # for connections, just drop them.
        if ($existing->isa('connection')) {
            $existing->done('Overriden');
        }

        # for users, kill locally or remotely.
        else {
            my $reason = 'Nickname regained by services';
            $existing->get_killed_by($me, $reason);
            $pool->fire_command_all(kill => $me, $existing, $reason);
        }

    }

    # registered user.
    if (my $user = $conn->user) {
        # TODO: (#83) this, for SASL reauthentication
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

    # TODO: (#83) for SASL reauthentication, update $user->{account}

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
sub on_user_set_modes {
    my ($user, $event) = @_;
    my $act_name = delete $user->{sasl_account} or return;
    L("SASL login $$user{nick} as $act_name");
    $user->do_login($act_name, 1); # the 1 means no RPL_LOGGED*
}

$mod
