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
use utils qw(conf broadcast);

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
    $mod->register_registration_command(
        name       => 'AUTHENTICATE',
        code       => \&rcmd_authenticate,
        after_reg  => 1,
        parameters => 1
    ) or return;

    # log the user in once registered
    $pool->on('user.initially_set_modes' =>
        \&on_user_set_modes, 'sasl.monitor');

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

my $have_saslserv;
sub find_saslserv {
    my $saslserv = conf('services', 'saslserv') or return;
    $saslserv = $pool->lookup_user_nick($saslserv);
    undef $saslserv if !is_valid_agent($saslserv);

    # we can't find the agent, so start looking for it.
    if (!$saslserv) {
        undef $have_saslserv;
        L('Watching for SASL agent');
    }

    # we found the agent.
    if (!$have_saslserv && $saslserv) {
        $have_saslserv++;

        # watch SaslServ in case it disappears
        weaken(my $weak_mod = $mod);
        $saslserv->on(quit => sub {
            my ($saslserv) = @_;
            $weak_mod or return;

            # disable it and start monitoring again
            $weak_mod->disable_capability('sasl');
            L('Lost SaslServ');
            undef $have_saslserv;

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

    # already authenticated successfully, so this is a reauthentication
    if ($connection->{sasl_complete}) {
        if (!conf('services', 'saslserv_allow_reauthentication')) {
            $connection->numeric('ERR_SASLALREADY');
            return;
        }
        delete $connection->{sasl_complete};
        delete $connection->{sasl_agent};
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

        # shared between SASL S and SASL H.
        my @common = (
            $me,                        # source server
            $saslserv->server->name,    # server mask target
            $connection->{uid},         # the connection's temporary UID
            $saslserv->{uid},           # UID of SASL service
        );

        # send SASL H.
        $saslserv->forward(sasl_host_info =>
            @common,                    # common parameters
            $connection->{host},        # connection host
            $connection->{ip}           # connection IP address
        );

        # send SASL S.
        $saslserv->forward(sasl_initiate =>
            @common,                    # common parameters
            $arg                        # authentication method; e.g. PLAIN
        );

        # store the SASL agent.
        $connection->{sasl_agent} = $saslserv->id;

    }

    # the client has an agent. forward this as client data to the agent.
    elsif (length $arg) {
        $agent->forward(sasl_client_data =>
            $me,                        # source server
            $agent->server->name,       # server mask target
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

    # find the SASL agent. if no SASL agent is set, that's fine.
    # that means abort_sasl() was called before even determining it.
    my $agent = $pool->lookup_user($connection->{sasl_agent}) or return;

    # tell the agent that the user aborted the exchange.
    $agent->forward(sasl_done =>
        $me,                        # source server
        $agent->server->name,       # server mask target
        $connection->{uid},         # the connection's temporary UID
        $agent->{uid},              # UID of SASL service
        'A'                         # for abort
    );
}

# update user mask. * = unchanged
sub update_user_info {
    my ($source, $conn, $nick, $ident, $cloak, $act_name) = @_;
    my $user = $conn->user;
    my $nick_ts = time;

    # which things are we updating?
    my $update_nick  = length $nick  && utils::validnick($nick, 1);
    my $update_ident = length $ident && utils::validident($ident);
    my $update_cloak = length $cloak && 1; # TODO: (#157) validhost()

    # updating nick. we may have to deal with a collision.
    if ($update_nick) {

        # look for an existing user/conn by this nick.
        my $existing = $pool->nick_in_use($nick);
        my $is_the_user = $user == $existing if $existing && $user;
        my $is_the_conn = $conn == $existing if $existing;

        # unless the nick belongs to the existing user, we have to kill it.
        if (!$is_the_user && !$is_the_conn) {

            # for connections, just drop them.
            if ($existing->isa('connection')) {
                $existing->done('Overriden');
            }

            # for users, kill locally or remotely.
            else {
                my $reason = 'Nickname regained by services';
                $existing->get_killed_by($me, $reason);
                broadcast(kill => $me, $existing, $reason);
            }
        }
    }

    # registered user.
    # each protocol implementation will send out some command to notify
    # servers that the existing user's fields have changed.
    if ($user) {
        if ($update_nick) {
            $user->send_to_channels("NICK $nick")
                unless $nick eq $user->{nick};
            $user->change_nick($nick, $nick_ts);
        }
        if ($update_ident || $update_cloak) {
            $user->get_mask_changed(
                $update_ident ? $ident : $user->{ident},    # ident
                $update_cloak ? $cloak : $user->{cloak},    # cloak
                $source->name                               # setby
            );
        }
        broadcast(signon =>
            $user,                                          # user
            $update_nick  ? $nick    : $user->{nick},       # new nick
            $update_ident ? $ident   : $user->{ident},      # new ident
            $update_cloak ? $cloak   : $user->{cloak},      # new cloak
            $update_nick  ? $nick_ts : $user->{nick_time},  # new nick TS
            $act_name                               # new account name or undef
        );
    }

    # non-registered connection.
    # we don't need to send anything out because (E)UID has not been sent yet.
    else {
        $conn->{nick}  = $nick  if $update_nick;
        $conn->{ident} = $ident if $update_ident;
        $conn->{cloak} = $cloak if $update_cloak;
    }

    return update_account($conn, $user, $act_name);
}

# update the account name. none = logout
sub update_account {
    my ($conn, $user, $act_name) = @_;
    my $cloak = $conn->{cloak} // $conn->{host};

    # log in
    if ($act_name) {
        $user->{account} = { name => $act_name } if $user;
        $conn->{sasl_account} = $act_name;
        $conn->numeric(RPL_LOGGEDIN =>
            $conn->{nick}.'!'.$conn->{ident}.'@'.$cloak,
            $act_name, $act_name
        );
    }

    # log out
    else {
        delete $user->{account} if $user;
        delete $conn->{sasl_account};
        $conn->numeric(RPL_LOGGEDOUT =>
            $conn->{nick}.'!'.$conn->{ident}.'@'.$cloak
        );
    }

    return 1;
}

sub check_failures {
    my $conn = shift;
    my $max = conf('services', 'saslserv_max_failures');
    return 1 if $conn->{sasl_failures} <= $max;
    $conn->done('Too many SASL authentication failures');
    return;
}

# we've already sent RPL_LOGGEDIN at this point.
sub on_user_set_modes {
    my ($user, $event) = @_;

    # if we're looking for the SASL agent, this might be it
    if (!$have_saslserv && is_valid_agent($user)) {
        find_saslserv();
    }

    # this might be a local user which is now ready to login
    $user->is_local or return;
    my $act_name = delete $user->{sasl_account} or return;
    L("SASL login $$user{nick} as $act_name");
    $user->do_login_local($act_name, 1); # the 1 means no RPL_LOGGED*
}

$mod
