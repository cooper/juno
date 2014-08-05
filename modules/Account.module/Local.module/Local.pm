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

use M::Account qw(register_account lookup_account_name);

our ($api, $mod, $me, $db, $pool);

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
    $db = $M::Account::db or return;
    
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
        return unless $quser->{account};
        $user->numeric(RPL_WHOISACCOUNT => $quser->{nick}, $quser->{account}{name});
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
        $user->server_notice('register', 'You have already registered an account');
        return;
    }
    
    # no account name.
    if (!defined $password) {
        $password = $act_name;
        $act_name = $user->{nick};
    }
    
    # taken.
    if (lookup_account_name($act_name)) {
        $user->server_notice('register', 'Account name taken');
        return;
    }
    
    # success.
    register_account($account, $password, $me, $user);
    $user->server_notice('register', 'Registration successful');
    
    $user->{registered} = 1;
    return 1;
}

# LOGIN command.
# /LOGIN <password>
# /LOGIN <accountname> <password>
sub cmd_login {
    my ($user, $event, $act_name, $password) = @_;
    
}

# inspect accounts.
sub cmd_acctdump {
    my $user = shift;
    my @accounts = sort { $a->{updated} <=> $b->{updated} } @{ all_accounts() };
    $user->server_notice('account dump' => 'Registered user accounts');

    # add all the rows.
      my @rows = ([qw(SID AID Name Updated)], []);
    push @rows, map { [
        $_->{csid},
        $_->{id},
        $_->{name},
        scalar localtime $_->{updated}
    ] } @accounts;
    
    # determine the width of each column.
    my @width;
    for my $col (0..$#{ $rows[0] }) {
        my $max = 0;
        foreach my $row (@rows) {
            my $length = length $row->[$col] or next;
            $max = $length if $length > $max;
        }
        $width[$col] = $max;
    }
    
    # ---- ---- ---- ----
    @{ $rows[1] } = map { '-' x $_ } @width;
    
    # send each row.
    foreach my $row (@rows) {
        my $fmt  = '';
           $fmt .= "  %-${_}s   " foreach @width;
        $user->server_notice(sprintf $fmt, @$row);
    }
    
    my $num = scalar @accounts;
    $user->server_notice('account dump' => "End of user account list ($num total)");
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
