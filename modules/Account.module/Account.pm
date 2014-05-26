# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "Account"
# @package:         "M::Account"
# @description:     "implements user accounts"
#
# @depends.modules: ['Base::Database']
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Account;

use warnings;
use strict;
use 5.010;

use utils qw(conf notice);

our ($api, $mod, $me, $db);

sub init {
    $db = $mod->database('account') or return;
    
    # create or update the table if necessary.
    $mod->create_or_alter_table($db, 'accounts',
        id       => 'INT',          # numerical account ID
        name     => 'VARCHAR(50) COLLATE NOCASE',  # account name
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

    $mod->load_submodule('Local')  or return;
    $mod->load_submodule('Remote') or return;
    
    return 1;
}

##########################
### ACCOUNT MANAGEMENT ###
##########################

# fetch account information
sub account_info {
    my $account = shift;
    return $mod->db_hashref($db, 'SELECT * FROM accounts WHERE name=? COLLATE NOCASE', $account);
}

# fetch the next available account ID.
sub next_available_id {
    my $current = $mod->db_single($db, 'SELECT MAX(id) FROM accounts') // 0;
    return $current + 1;
}

# register an account if it does not already exist.
# $user is optional.
sub register_account {
    my ($account, $password, $server, $user) = @_;
    
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
    
    notice(account_register =>
        $user->notice_info,
        $account,
        $user->{server}{name}
    ) if $user;
    
    return 1;
}

# log a user into an account.
sub login_account {
    my ($account, $user, $password, $just_registered) = @_;
    
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
    delete $act->{password};
    $user->{account} = $act;
    
    # handle and send mode string if local.
    my $mode = $me->umode_letter('registered');
    $user->do_mode_string("+$mode", 1);
    
    # if local, send logged in numeric.
    $user->numeric(RPL_LOGGEDIN => $act->{name}, $act->{name}) if $user->is_local;
    
    # logged in event.
    $user->fire_event(logged_in => $act);
    
    notice(account_login =>
        $user->notice_info,
        $act->{name},
        $user->{server}{name}
    ) unless $just_registered;
    
    return 1;
}

# log a user out.
sub logout_account {
    my ($user, $in_mode_unset) = @_;
    
    # not logged in.
    if (!$user->{account}) {
        # TODO: this.
        return;
    }

    # success.
    my $account = $user->{account}{name};
    delete $user->{account};
    
    # handle & send mode string if we're not doing so already.
    my ($mode, $str);
    if (!$in_mode_unset) {
        $mode = $me->umode_letter('registered');
        $user->do_mode_string("-$mode", 1);
    }
    
    # send logged out if local.
    $user->numeric('RPL_LOGGEDOUT') if $user->is_local;
    
    notice(account_logout =>
        $user->notice_info,
        $account,
        $user->{server}{name}
    );

    return 1;
}

$mod