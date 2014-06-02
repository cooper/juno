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

use utils qw(conf notice import);

our ($api, $mod, $me, $db);

sub init {
    $db = $mod->database('account') or return;
    
    # create or update the table if necessary.
    $mod->create_or_alter_table($db, 'accounts',
        id       => 'INTEGER',      # numerical account ID
        name     => 'TEXT COLLATE NOCASE',  # account name
        password => 'TEXT',         # (hopefully encrypted) account password
        encrypt  => 'TEXT',         # password encryption type
                                    #     255 is max varchar size on mysql<5.0.3
        created  => 'INTEGER',      # UNIX time of account creation
                                    #     in SQLite, the max size is very large...
                                    #     in mysql and others, not so much.
        cserver  => 'TEXT',         # server name on which the account was registered
        csid     => 'INTEGER',      # SID of the server where registered
        updated  => 'INTEGER',      # UNIX time of last account update
        userver  => 'TEXT',         # server name on which the account was last updated
        usid     => 'INTEGER',      # SID of the server where last updated
        salt     => 'TEXT'          # password encryption salt
    ) or return;

    $mod->load_submodule('Local')  or return;
    $mod->load_submodule('Remote') or return;
    
    return 1;
}

##########################
### ACCOUNT MANAGEMENT ###
##########################

# select info for all accounts.
# returns an arrayref of hashrefs.
sub all_accounts {
    return $mod->db_hashrefs($db, 'SELECT * FROM accounts');
}

# fetch account information.
sub account_info {
    my $account = shift;
    return $mod->db_hashref($db, 'SELECT * FROM accounts WHERE name=? COLLATE NOCASE', $account);
}

# lookup an account by SID and account ID.
sub lookup_sid_aid {
    my ($sid, $aid) = @_;
    return $mod->db_hashref($db, 'SELECT * FROM accounts WHERE csid=? AND id=? COLLATE NOCASE', $sid, $aid);
}

# fetch the next available account ID.
sub next_available_id {
    my $current = $mod->db_single($db, 'SELECT MAX(id) FROM accounts') // 0;
    return $current + 1;
}

# add an account to the table.
sub add_account {
    my $act = shift;

    # account already exists.
    return if lookup_sid_aid($act->{csid}, $act->{id});
    
    # insert the account.
    $mod->db_insert_hash($db, 'accounts', %$act);
    
}

# update an account.
sub update_account {
    my $act = shift;
    return unless lookup_sid_aid($act->{csid}, $act->{id});
    $mod->db_update_hash($db, 'accounts', {
        csid => $act->{csid},
        id   => $act->{id}
    }, $act);
}

# add account if not exists, otherwise update info.
sub add_or_update_account {
    my $act = shift;
    return update_account($act) || add_account($act);
}

# same account.
sub accounts_equal {
    my ($act1, $act2) = @_;
    return if $act1->{id}   != $act2->{id};
    return if $act1->{csid} != $act2->{csid};
    return 1;
}

# register an account if it does not already exist.
# $user is optional. TODO: reconsider: why?
# I think that I originally intended for register_account() to handle registrations
# of accounts that may or may not have actual users, but add_account() handles that now.
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
    ) or return;
    
    notice(account_register =>
        $user->notice_info,
        $account,
        $user->{server}{name}
    ) if $user;
    
    # registered event.
    $user->fire_event(account_registered => lookup_sid_aid($server->{sid}, $id)) if $user;
    
    return 1;
}

# log a user into an account.
sub login_account {
    my ($account, $user, $password, $just_registered) = @_;
    
    # fetch the account information.
    my $act = ref $account ? $account : account_info($account);
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
    $user->fire_event(account_logged_in => $act);
    
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
    my $act     = delete $user->{account};
    my $account = $act->{name};
    
    # handle & send mode string if we're not doing so already.
    my ($mode, $str);
    if (!$in_mode_unset) {
        $mode = $me->umode_letter('registered');
        $user->do_mode_string("-$mode", 1);
    }
    
    # send logged out if local.
    $user->numeric('RPL_LOGGEDOUT') if $user->is_local;
    
    # logged out event.
    $user->fire_event(account_logged_out => $act);
    
    notice(account_logout =>
        $user->notice_info,
        $account,
        $user->{server}{name}
    );

    return 1;
}

$mod