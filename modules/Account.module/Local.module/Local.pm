# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "Account::Local"
# @package:         "M::Account::Local"
# @description:     "implements account modes and commands"
#
# @depends.modules: ['Base::UserCommands', 'Base::UserNumerics', 'Base::UserModes', 'Base::Matchers', 'Base::OperNotices']
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Account::Local;

use warnings;
use strict;
use 5.010;

M::Account->import(qw/register_account lookup_account_name/);

our ($api, $mod, $me, $pool);

# user commands.
our %user_commands = (
    REGISTER => {
        desc   => 'register an account',
        params => 'any any(opt)',
        code   => \&cmd_register
    },
    LOGIN => {
        desc   => 'log in to an account',
        params => 'any any(opt)',
        code   => \&cmd_login
    },
    ACCTDUMP => {
        desc   => 'inspect accounts',
        params => '-oper(acctdump)',
        code   => \&cmd_acctdump
    }
);

sub init {
    
    # RPL_LOGGEDIN and RPL_LOGGEDOUT.
    $mod->register_user_numeric(
        name   => 'RPL_LOGGEDIN',
        number => 900,
        format => '%s %s :You are now logged in as %s'
    );
    $mod->register_user_numeric(
        name   => 'RPL_LOGGEDOUT',
        number => 901,
        format => ':You have logged out'
    );
    $mod->register_user_numeric(
        name   => 'RPL_WHOISACCOUNT',
        number => 330,
        format => '%s %s :is logged in as'
    );
    
    # registered user mode.
    $mod->register_user_mode_block(
        name => 'registered',
        code => \&umode_registered
    );
    
    # account matcher.
    $mod->register_matcher(
        name => 'account',
        code => \&account_matcher
    ) or return;
    
    # oper notices.
    $mod->register_oper_notice(
        name   => $_->[0],
        format => $_->[1]
    ) || return foreach (
        [ account_register => '%s (%s@%s) registered the account \'%s\' on %s' ],
        [ account_login    => '%s (%s@%s) authenticated as \'%s\' on %s'       ],
        [ account_logout   => '%s (%s@%s) logged out from \'%s\' on %s'        ]
    );
    
    # WHOIS account line.
    $pool->on('user.whois_query' => sub {
        my ($user, $event, $quser) = @_;
        return unless $quser->account;
        $user->numeric(RPL_WHOISACCOUNT => $quser->{nick}, $quser->account->{name});
    }, name     => 'RPL_WHOISACCOUNT',
        after   => ['RPL_WHOISMODES', 'RPL_WHOISHOST'],
        before  => 'RPL_ENDOFWHOIS',
        with_eo => 1
    );

    return 1;
}


#############
### MODES ###
#############

# logged in mode.
sub umode_registered {
    my ($user, $state) = @_;
    return if $state; # never allow setting.

    # but always allow them to unset it.
    $user->account->logout_user($user, 1) if $user->account;
    
    return 1;
}

#####################
### USER COMMANDS ###
#####################

# REGISTER command.
# /REGISTER <password>
# /REGISTER <accountname> <password>
sub cmd_register {
    my ($user, $event, $act_name, $password) = @_;
    
    # already registered.
    # this is to prevent several registrations in one connection.
    if (defined $user->{registered}) {
        $user->server_notice(register => 'You have already registered an account');
        return;
    }
    
    # no account name.
    if (!defined $password) {
        $password = $act_name;
        $act_name = $user->{nick};
    }
    
    # taken.
    if (lookup_account_name($act_name)) {
        $user->server_notice(register => 'Account name taken');
        return;
    }
    
    # attempt.
    my $act = register_account($act_name, $password, $me, $user);
    if (!$act) {
        $user->server_notice(register => 'Registration error');
        return;
    }
    
    # success.
    $user->server_notice(register => 'Registration successful');
    $pool->fire_command_all(acctinfo => $act);

    $user->{registered} = 1;
    return 1;
}

# LOGIN command.
# /LOGIN <password>
# /LOGIN <accountname> <password>
sub cmd_login {
    my ($user, $event, $act_name, $password) = @_;
    
    # no account name.
    if (!defined $password) {
        $password = $act_name;
        $act_name = $user->{nick};
    }
    
    # find account.
    my $act = lookup_account_name($act_name);
    if (!$act) {
        $user->server_notice(login => 'No such account');
        return;
    }
    
    # check password.
    if (!$act->verify_password($password)) {
        $user->server_notice(login => 'Incorrect password');
        return;
    }
    
    # success.
    $act->login_user($user);
    
}

# inspect accounts.
sub cmd_acctdump {

}

################
### MATCHERS ###
################

# account mask matcher.
sub account_matcher {
    my ($event, $user, @list) = @_;
    return unless $user->is_mode('registered');
    foreach my $item (@list) {
    
        # just check if registered.
        return $event->{matched} = 1 if $item eq '$r';
        
        # match a specific account.
        next unless $item =~ m/^\$r:(.+)$/;
        return $event->{matched} = 1 if lc $user->account->{name} eq lc $1;
        
    }
    return;
}

$mod
