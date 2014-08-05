# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "Account"
# @package:         "M::Account"
# @description:     "implements user accounts"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Account;

use warnings;
use strict;
use 5.010;

use utils qw(conf notice import);
use Scalar::Util qw(weaken blessed);

our ($api, $mod, $pool, $me, $conf, $table, %users_waiting);
my %table_format;

sub init {
    $table = $conf->table('accounts');
    
    # create or update the table.
    %table_format = my @format = (
        id       => 'INTEGER',      # numerical account ID
        name     => 'TEXT COLLATE NOCASE',  # account name
        password => 'TEXT',         # (hopefully encrypted) account password
        encrypt  => 'TEXT',         # password encryption type
        salt     => 'TEXT',         # password encryption salt
        created  => 'INTEGER',      # UNIX time of account creation
        cserver  => 'TEXT',         # server name on which the account was registered
        csid     => 'INTEGER',      # SID of the server where registered
        updated  => 'INTEGER',      # UNIX time of last account update
        userver  => 'TEXT',         # server name on which the account was last updated
        usid     => 'INTEGER'       # SID of the server where last updated
    );
    $table->create_or_alter(@format);
    
    # upgrade from older versions.
    upgrade();

    $mod->load_submodule('Local')  or return;
    $mod->load_submodule('Remote') or return;
    
    return 1;
}

# find an account by name.
#
# if it's cached, return the exact object.
# otherwise, look up in database.
#
sub lookup_account_name {
    my $act_name = shift;
    return $ircd::account_names{ lc $act_name } if $ircd::account_names{ lc $act_name };
    my %act = $table->row(name => $act_name)->select_hash or return;
    return __PACKAGE__->new(%act);
}

# find an account by SID and account ID.
#
# if it's cached, return the exact object.
# otherwise, look up in database.
#
sub lookup_account_sid_aid {
    my ($sid, $aid) = @_;
    ($sid, $aid) = split /\./, $sid, 2 if @_ == 1;
    return $ircd::account_ids{"$sid.$aid"} if $ircd::account_ids{"$sid.$aid"};
    my %act = $table->row(csid => $sid, id => $aid)->select_hash or return;
    return __PACKAGE__->new(%act);
}

# find an account by hash.
#
# this is used just to prevent multiple account objects for the same account.
# note it can only be promised that 'csid' and 'id' keys exist.
#
sub lookup_account_hash {
    my %act = @_;
    return $ircd::account_ids{ $act{csid}.q(.).$act{id} } || __PACKAGE__->new(%act);
}

# register an account.
#
# this is used for actual REGISTER command as well as any other
# instance where an account should be inserted into the database.
#
# it is used for both local and remote users, and it is also used
# even when a user is absent (such as account burst).
#
# $act_name     = account name being registered
# $password     = plaintext password OR [password, salt, crypt]
# $source_serv  = server on which the account originated or [sid, name]
# $source_user  = (optional) user registering the account
#
sub register_account {
    my ($act_name, $pwd, $source_serv, $source_user) = @_;
    return if lookup_account_name($act_name);
    
    # determine the account ID.
    my $id = $table->meta('last_id') || -1;
    $table->set_meta(last_id => ++$id);
    
    my ($password, $salt, $crypt) = handle_password($pwd);
    my ($sid, $s_name) = ref $source_serv eq 'ARRAY' ?
        @$source_serv : ($source_serv->id, $source_serv->name);
    my $time = time;

    # create the account.
    $table->insert(
        id       => $id,
        name     => $act_name,
        password => $password,
        encrypt  => $crypt,
        salt     => $salt,
        created  => $time,
        cserver  => $s_name,
        csid     => $sid,
        updated  => $time,
        userver  => $s_name,
        usid     => $sid
    );
    my $act = lookup_account_sid_aid($sid, $id) or return;
    
    # if a user registered this just now, log him in.
    $act->login_user($source_user) if $source_user;

    return $act;
}

# update an account if it exists, otherwise create it.
sub add_or_update_account {
    my %act = shift;
    my $act = lookup_account_hash(%act);
    
    # it exists. update it.
    if ($act) {
        $act->update_info(%act);
        return $act;
    }
    
    # it doesn't exist. make sure everything is present.
    defined $act{$_} || return foreach qw(name password csid cserver);
    
    # register it.
    # note that if there is a user logged in, it should be 
    $act = register_account($act{name}, $act{password}, [ $act{csid}, $act{cserver} ])
    or return;
    
    # if any users were waiting for this account info, log them in.
    while (my $user = shift @{ $users_waiting{ $act->id } || [] }) {
        ref $user or next;
        $act->login_user($user);
    }
    
    return $act;
}

# conveniently deal with passwords.
sub handle_password {
    my $pwd = shift;
    return @$pwd if ref $pwd && ref $pwd eq 'ARRAY';
    # TODO: otherwise, determine salt and crypt and do it.
    # configuration? not sure.
}

######################
### Account object ###
######################

sub new {
    my ($class, %opts) = @_;
    $opts{users} ||= [];
    return bless \%opts, $class;
}

# log a user into an account.
#
# this is used for both local and remote users.
# modes are set locally but never propagated.
#
sub login_user {
    my ($act, $user) = @_;
    
    # user was previously logged in.
    my $oldact = $user->{account};
    if ($oldact) {
        return if $act == $oldact;
        delete $user->{account};
        $oldact->logout_user_silently($user) if blessed $oldact; # compat
    }
    
    # if the user is local, send RPL_LOGGEDIN and tell other servers.
    if ($user->is_local) {
        $user->numeric(RPL_LOGGEDIN => $user->full, $act->{name}, $act->{name});
        $pool->fire_command_all(login => $user, $act);
    }
    
    # set +registered.
    # this is only done locally; the mode change is not propagated.
    # all other servers will do this same thing upon receiving LOGIN.
    my $mode = $me->umode_letter('registered');
    $user->do_mode_string_local("+$mode", 1);
    
    # lots of weak references.
    # the only strong reference is that on the user object.
    $user->{account} = $act;
    weaken( $ircd::account_ids  {    $act->id     } = $act );
    weaken( $ircd::account_names{ lc $act->{name} } = $act );
    my $users = $act->{users};
    push @$users, $user;
    weaken($users->[$#$users]);
        
    $user->fire_event(account_logged_in => $act, $oldact);
    return $act;
}

# logout with numerics and modes.
# $unsetting = true if called from inside mode unset.
sub logout_user {
    my ($act, $user, $unsetting) = @_;
    return unless $user->{account} && $user->{account} == $act;
    $act->logout_user_silently($act);
    
    # if the user is local, send RPL_LOGGEDOUT and tell other servers.
    if ($user->is_local) {
        $user->numeric('RPL_LOGGEDOUT');
        $pool->fire_command_all(logout => $user);
    }
    
    # set -registered.
    # this is only done locally; the mode change is not propagated.
    # all other servers will do this same thing upon receiving LOGOUT.
    if (!$unsetting) {
        my $mode = $me->umode_letter('registered');
        $user->do_mode_string_local("-$mode", 1);
    }
    
    return 1;
}

# this does the actual logout.
# it does not, however, unset modes or send numerics.
# this is ONLY for logging out before logging into another account.
sub logout_user_silently {
    my ($act, $user) = @_;
    return unless $user->{account} && $user->{account} == $act;
    $act->{users} = [ grep { $_ != $user } @{ $act->{users} } ];
    delete $user->{account};
    
    # keep in mind that the logout event is fired here,
    # meaning that other servers will see:
    # :uid LOGOUT
    # :uid LOGIN
    # if the user logs into another account while logged in already.
    $user->fire_event(account_logged_out => $act);
    
}

# update account information.
sub update_info {
    
}

# verify account password.
sub verify_password {
    my ($act, $password) = @_;
    $password = utils::crypt($password, $act->{encrypt}, $act->{salt});
    return $password eq $act->{password};
}

# unique identifier.
# id = sid.aid
sub id {
    my $act = shift;
    return $act->{csid}.q(.).$act->{id};
}

# users logged into this account currently.
sub users {
    my $act = shift;
    $act->{users} = [ grep { $_ } @{ $act->{users} } ];
    return @{ $act->{users} };
}

#####################
### Compatibility ###
#####################

sub upgrade {

    # upgrade the old format to new database.
    my $old_db_file = "$::run_dir/db/account.db";
    if (-f $old_db_file) {
        L("Upgrading $old_db_file to new database");
        my $i = join ', ', map { "`$_`" } keys %table_format;
        $conf->{db}->do("ATTACH DATABASE '$::run_dir/db/account.db' AS old_accounts") and
        $conf->{db}->do("INSERT INTO accounts ($i) SELECT $i FROM old_accounts.accounts")
        and rename $old_db_file, "$old_db_file.old";
    }

    # if users are logged in with old format, log them in with the new format.
    my $mode = $me->umode_letter('registered');
    foreach my $user ($pool->all_users) {
    
        # these guys aren't logged in or already upgraded.
        next unless $user->{account};
        last if blessed $user->{account};
        
        # find the new account data.
        my $act = lookup_account_hash(%{ $user->{account} });
        
        # just an extra check in case something went wrong.
        if (!$act) {
            delete $user->{account};
            $user->do_mode_string_local("-$mode", 1);
            next;
        }
        
        # everything looks ok.
        $act->login_user($user);
        $user->server_notice(
            'Your account was upgraded, and you were logged back in automatically.');
        L("Upgraded user $$user{nick} to new account format");
        
    }
    
}
$mod