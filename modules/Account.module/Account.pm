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
use Scalar::Util 'weaken';

our ($api, $mod, $me, $conf, $table);
our (%account_ids, %account_names);

sub init {
    $table = $conf->table('accounts');
    
    # create or update the table.
    $table->create_or_alter(
        id       => 'INTEGER',      # numerical account ID
        name     => 'TEXT COLLATE NOCASE',  # account name
        password => 'TEXT',         # (hopefully encrypted) account password
        encrypt  => 'TEXT',         # password encryption type
        salt     => 'TEXT'          # password encryption salt
        created  => 'INTEGER',      # UNIX time of account creation
        cserver  => 'TEXT',         # server name on which the account was registered
        csid     => 'INTEGER',      # SID of the server where registered
        updated  => 'INTEGER',      # UNIX time of last account update
        userver  => 'TEXT',         # server name on which the account was last updated
        usid     => 'INTEGER'       # SID of the server where last updated
    );

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
    return $account_names{ lc $act_name } if $account_names{ lc $act_name };
    my %act = $table->row(name => $act_name)->select_hash or return;
    return __PACKAGE__->new(%act);
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
# $source_serv  = server on which the account originated
# $source_user  = (optional) user registering the account
#
sub register_account {
    my ($act_name, $password, $source_serv, $source_user) = @_;
    return if lookup_account_name($act_name);
    
    # determine the account ID.
    my $id = $table->meta('last_id') || -1;
    $table->set_meta(last_id => ++$id);
    
    my ($password, $salt, $crypt) = handle_password($password);
    my ($sid, $s_name) = ($source_serv->id, $source_serv->name);
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
    $act->login_user($user) if $user;

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

#
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
        $oldact->logout_user_silently($user);
    }
    
    # if the user is local, send RPL_LOGGEDIN.
    $user->numeric(RPL_LOGGEDIN => $user->full, $act->{name}, $act->{name})
        if $user->is_local;
    
    # set +registered.
    # this is only done locally; the mode change is not propagated.
    # all other servers will do this same thing upon receiving LOGIN.
    my $mode = $me->umode_letter('registered');
    $user->do_mode_string_local("+$mode", 1);
    
    # lots of weak references.
    # the only strong reference is that on the user object.
    $user->{account} = $act;
    weaken( $account_ids  {    $act->id     } = $act );
    weaken( $account_names{ lc $act->{name} } = $act );
    push @{ my $users = $act->{users} }, $user;
    weaken($users->[$#$users]);
    
    $user->fire_event(account_logged_in => $act, $oldact);
    return $act;
}

# logout with numerics and modes.
sub logout_user {
    my ($act, $user) = @_;
    return unless $user->{account} && $user->{account} == $act;
    $act->logout_user_silently($act);
    
    # if the user is local, send RPL_LOGGEDOUT.
    $user->numeric('RPL_LOGGEDOUT') if $user->is_local;
    
    # set -registered.
    # this is only done locally; the mode change is not propagated.
    # all other servers will do this same thing upon receiving LOGOUT.
    my $mode = $me->umode_letter('registered');
    $user->do_mode_string_local("-$mode", 1);
    
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
    $user->fire_event(account_logged_out, $act);
    
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
    return $act->{users} = [ grep { $_ } @{ $act->{users} } ];
}

$mod