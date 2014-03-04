# Copyright (c) 2012-14, Mitchell Cooper
package API::Module::Account;

use warnings;
use strict;
use 5.010;

our $db;

use utils qw(v log2 conf);

our $mod = API::Module->new(
    name        => 'Account',
    version     => '0.3',
    description => 'Account management',
    requires    => [
                        'Database', 'UserCommands', 'UserNumerics',
                        'UserModes', 'Matching', 'ServerCommands'
                    ],
    initialize  => \&init
);
 
sub init {
    $db = $mod->database('account') or return;
    
    # create or update the table if necessary.
    $mod->create_or_alter_table($db, 'accounts',
        id       => 'INT',          # numerical account ID
        name     => 'VARCHAR(50)',  # account name
        password => 'VARCHAR(512)', # (hopefully encrypted) account password
        encrypt  => 'VARCHAR(20)',  # password encryption type
                                    #     255 is max varchar size on mysql<5.0.3
        created  => 'UNSIGNED INT', # UNIX time of account creation
                                    #     in SQLite, the max size is very large...
                                    #     in mysql and others, not so much.
        cserver  => 'VARCHAR(512)', # server name on which the account was registered
        csid     => 'INT(4)',       # SID of the server where registered
        updated  => 'UNSIGNED INT', # UNIX time of last account update
        userver  => 'VARCHAR(512)', # server name on which the account was last updated
        usid     => 'INT(4)'        # SID of the server where last updated
    ) or return;
    
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
    
    return 1;
}

# fetch account information
sub account_info {
    my $account = shift;
    return $mod->db_hashref($db, 'SELECT * FROM accounts WHERE name=?', $account);
}

# fetch the next available account ID.
sub next_available_id {
    my $current = $mod->db_single($db, 'SELECT MAX(id) FROM accounts') // 0;
    return $current + 1;
}

# register an account if it does not already exist.
sub register_account {
    my ($account, $password, $server) = @_;
    
    # it exists already.
    return if account_info($account);
    
    # determine ID.
    my $time = time;
    my $id   = next_available_id();

    # encrypt password.
    my $encrypt = conf('account', 'encryption')     || 'sha1';
    $password   = utils::crypt($password, $encrypt) || $password;

    # insert.
    $db->do(q{INSERT INTO accounts(
        id, name, password, encrypt, created, cserver, csid, updated, userver, usid
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) }, undef,
        $id,
        $account,
        $password,
        $encrypt,
        $time,
        $server->{name},
        $server->{sid},
        $time,
        $server->{name},
        $server->{sid}
    );
}

# log a user into an account.
sub login_account {
    my ($account, $user, $password) = @_;
    
    # fetch the account information.
    my $act = account_info($account);
    if (!$act) {
        $user->server_notice('login', 'No such account') if $user->is_local;
        return;
    }
    
    # if password is defined, we're checking the password.
    if (defined $password) {
        $password = utils::crypt($password, $act->{encrypt});
        if ($password ne $act->{password}) {
            $user->server_notice('login', 'Password incorrect') if $user->is_local;
            return;
        }
    }
    
    # log in.
    $user->{account}{id}   = $act->{id};
    $user->{account}{name} = $act->{name};
    my $mode = v('SERVER')->umode_letter('registered');
    my $str  = $user->handle_mode_string("+$mode", 1);
    if ($user->is_local) {
        $user->numeric(RPL_LOGGEDIN => $act->{name}, $act->{name});
        $user->sendfrom($user->{nick}, "MODE $$user{nick} :$str") if $str;
    }
    
    return 1;
}

# log a user out.
sub logout_account {
    my ($user, $mode_set) = @_;
    
    # not logged in.
    if (!$user->{account}) {
        # TODO: this.
        return;
    }

    # success.
    delete $user->{account};
    
    # mode already unset?
    my ($mode, $str);
    if (!$mode_set) {
        $mode = v('SERVER')->umode_letter('registered');
        $str  = $user->handle_mode_string("-$mode");
    }
    
    # send logged out.
    if ($user->is_local) {
        $user->sendfrom($user->{nick}, "MODE $$user{nick} :$str") if $str;
        $user->numeric('RPL_LOGGEDOUT');
    }

    return 1;
}

# logged in mode.
sub umode_registered {
    my ($user, $state) = @_;
    return if $state; # never allow setting.

    # but always allow them to unset it.
    logout_account($user, 1);
    return 1;
}

# REGISTER command.
# /REGISTER <password>
# /REGISTER <accountname> <password>
sub cmd_register {
    my ($user, $data, $account, $password) = @_;
    
    # no account name.
    if (!defined $password) {
        $password = $account;
        $account  = $user->{nick};
    }
    
    # taken.
    if (!register_account($account, $password, v('SERVER'))) {
        $user->server_notice('register', 'Account name taken');
        return;
    }
    
    # success.
    $user->server_notice('register', 'Registration successful');
    login_account($account, $user, undef, 1);
    
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
    
    return unless grep { $_ eq '$r' } @list;
    return $event->{matched} = 1;
    return;
}

$mod
