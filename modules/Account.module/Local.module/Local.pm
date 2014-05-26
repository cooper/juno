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

our ($api, $mod, $me, $db);

sub init {
    $db = $M::Account::db or return;

    # REGISTER command.
    # /REGISTER <password>
    # /REGISTER <accountname> <password>
    $mod->register_user_command(
        name        => 'REGISTER',
        description => 'register an account',
        parameters  => 'any any(opt)',
        code        => \&cmd_register
    );
    
    # LOGIN command.
    # /LOGIN <password>
    # /LOGIN <accountname> <password>
    $mod->register_user_command(
        name        => 'LOGIN',
        description => 'log in to an account',
        parameters  => 'any any(opt)',
        code        => \&cmd_login
    );
    
    # RPL_LOGGEDIN and RPL_LOGGEDOUT.
    $mod->register_user_numeric(
        name   => 'RPL_LOGGEDIN',
        number => 900,
        format => '%s :You are now logged in as %s'
    );
    $mod->register_user_numeric(
        name   => 'RPL_LOGGEDOUT',
        number => 901,
        format => ':You have logged out'
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
    logout_account($user, 1);
    return 1;
}

#####################
### USER COMMANDS ###
#####################

# REGISTER command.
# /REGISTER <password>
# /REGISTER <accountname> <password>
sub cmd_register {
    my ($user, $data, $account, $password) = @_;
    
    # already registered.
    if (defined $user->{registered}) {
        $user->server_notice('register', 'You have already registered');
        return;
    }
    
    # no account name.
    if (!defined $password) {
        $password = $account;
        $account  = $user->{nick};
    }
    
    # taken.
    if (!register_account($account, $password, $me, $user)) {
        $user->server_notice('register', 'Account name taken');
        return;
    }
    
    # success.
    $user->server_notice('register', 'Registration successful');
    login_account($account, $user, undef, 1);
    $user->{registered} = 1;
    
    return 1;
}

# LOGIN command.
# /LOGIN <password>
# /LOGIN <accountname> <password>
sub cmd_login {
    my ($user, $data, $account, $password) = @_;
    
    # no account name.
    if (!defined $password) {
        $password = $account;
        $account  = $user->{nick};
    }
    
    # login.
    login_account($account, $user, $password);
    
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
        next unless $item =~ m/^\$r:(.+)/;
        return $event->{matched} = 1 if lc $user->{account}{name} eq lc $1;
        
    }
    return;
}

$mod
