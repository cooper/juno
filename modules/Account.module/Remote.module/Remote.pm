# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "Account::Remote"
# @package:         "M::Account::Remote"
# @description:     "synchronizes user accounts across servers"
#
# @depends.modules: ['JELP::Base']
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Account::Remote;

use warnings;
use strict;
use 5.010;

use utils qw(trim);
M::Account->import(qw(
    login_account logout_account register_account
    account_info all_accounts lookup_sid_aid add_account
    add_or_update_account accounts_equal
));

our ($api, $mod, $pool, $db, $me);

sub init {
    $db = $M::Account::db or return;

    # IRCd event for burst.
    $pool->on('server.send_burst' => \&send_burst,
        name  => 'account',
        after => 'core',
        with_evented_obj => 1
    );
    
    # user account events.
    $pool->on('user.account_logged_in'  => \&user_logged_in,  with_evented_obj => 1);
    $pool->on('user.account_logged_out' => \&user_logged_out, with_evented_obj => 1);
    $pool->on('user.account_registered' => \&user_registered, with_evented_obj => 1);
    
    # incoming commands.
    $mod->register_server_command(%$_) || return foreach (
        {
            name       => 'acct',
            parameters => 'dummy :rest', # don't even care about source
            code       => \&in_acct,
            forward    => 1
        },
        {
            name       => 'acctinfo',
            parameters => 'dummy @rest',
            code       => \&in_acctinfo,
            forward    => 1
        },
        {
            name       => 'acctidk',
            parameters => 'dummy @rest',
            code       => \&in_acctidk
        },
        {
            name       => 'login',
            parameters => 'user any',
            code       => \&in_login,
            forward    => 1
        },
        {
            name       => 'logout',
            parameters => 'user',
            code       => \&in_logout,
            forward    => 1
        }
    );
    
    # outgoing commands.
    $mod->register_outgoing_command(
        name => $_->[0],
        code => $_->[1]
    ) || return foreach (
        [ acct     => \&out_acct     ],
        [ acctinfo => \&out_acctinfo ],
        [ acctidk  => \&out_acctidk  ],
        [ login    => \&out_login    ],
        [ logout   => \&out_logout   ]
    );

    return 1;
}

sub send_burst {  
    my ($server, $fire, $time) = @_;
    return if $server->{accounts_negotiated};
    $server->fire_command(acct => @{ all_accounts() });
    $server->{accounts_negotiated} = 1;
}

######################
### ACCOUNT EVENTS ###
######################

sub user_registered {
    my ($user, $event, $act) = @_;
    $pool->fire_command_all(acctinfo => $act);
}

sub user_logged_in {
    my ($user, $event, $act) = @_;
    
    # if it's the same account as logged in already, ignore.
    # this was probably already handled.
    return if $user->{account} && accounts_equal($act, $user->{account});
    
    $pool->fire_command_all(login => $user, $act);
}

sub user_logged_out {
    my ($user, $event, $act) = @_;
    
    # if they're not logged in, don't log out.
    # it was probably already handled.
    return unless $user->{account};
    
    $pool->fire_command_all(logout => $user);
}

#########################
### OUTGOING COMMANDS ###
#########################

sub out_acct {
    return unless @_;
    my $str = '';
    foreach my $act (@_) {
        $str .= $act->{csid}.q(.).$act->{id}.q(,).$act->{updated}.q( );
    }
    ":$$me{sid} ACCT $str"
}

sub out_acctinfo {
    my $act = shift;
    my $str = '';
    foreach my $key (keys %$act) {
        my $value = $act->{$key};
        next unless defined $value;
        $str .= "$key $value ";
    }
    ":$$me{sid} ACCTINFO $str"
}

sub out_acctidk {
    my $str = '';
    while (@_) {
        my $item = shift;
        if (ref $item eq 'HASH') {
            $str .= "$$item{csid}.$$item{id} ";
            next;
        }
        my $id = shift;
        $str .= "$item.$id ";
    }
    ":$$me{sid} ACCTIDK $str"
}

sub out_login {
    my ($user, $act) = @_;
    ":$$user{uid} LOGIN $$act{csid}.$$act{id},$$act{updated}"
}

sub out_logout {
    my $user = shift;
    ":$$user{uid} LOGOUT"
}

#########################
### INCOMING COMMANDS ###
#########################

sub in_acct {
    # server  :rest
    # :sid ACCT info
    my ($server, $data, $str) = @_;
    print "data($data) str($str)\n";
    my @items = split /\W/, trim($str);
    return if @items % 3;
    
    # if the server is bursting, we can assume that the accounts
    # have been or are being negotiated, so we won't need to send
    # ACCT in our own burst later.
    $server->{accounts_negotiated} = 1 if $server->{is_burst};

    
    my %done;          # done = accts I've already dealt with.
    my (@i_dk, @u_dk); # i_dk = [sid, aid] of accounts I don't know.
                       # u_dk = {acct}     of accounts the other server doesn't know.
    while (@items) {
        my ($sid, $aid, $utime) = splice @items, 0, 3;
        $done{"$sid.$aid"} = 1;

        # if this account exists, check the times.
        if (my $act = lookup_sid_aid($sid, $aid)) {
        
            # my info is newer.
            if ($act->{updated} > $utime) {
                push @u_dk, $act;
                next;
            }
            
            # the info is equal.
            elsif ($act->{updated} == $utime) {
                next;
            }
            
            # their info is newer.
            push @i_dk, $act;
            next;
            
        }
        
        # if the account does not exist, we need it.
        push @i_dk, $sid, $aid;
        
    }
    
    # add the rest of the accounts.
    foreach my $act (@{ all_accounts() }) {
        next if $done{"$$act{csid}.$$act{id}"};
        push @u_dk, $act;
    }
        
    # request info for the accounts I don't know.
    $server->fire_command(acctidk => @i_dk) if @i_dk;
    
    # send info for the accounts they don't know.
    # (IF the server is in burst)
    if ($server->{is_burst}) {
        $server->fire_command(acctinfo => $_) foreach @u_dk;
    }
    
}

# :sid ACCTIDK 1.1 1.2
sub in_acctidk {
    my ($server, $data, @items) = @_;
    
    # find the accounts.
    my @accts;
    foreach my $str (@items) {
        my ($sid, $aid) = split /\W/, $str, 2;
        my $act = lookup_sid_aid($sid, $aid) or next;
        push @accts, $act;
    }
    
    # tell the server about them.
    $server->fire_command(acctinfo => $_) foreach @accts;
    
}

# :sid ACCTINFO csid 0 updated 234839344 ...
# TODO: if any users are logged into an account that is updated,
# update that information in their {account}.
sub in_acctinfo {
    my ($server, $data, @rest) = @_;
    return if @rest % 2;
    my %act = @rest;
    add_or_update_account(\%act);
}

# :uid LOGIN sid.aid,updated
sub in_login {
    my ($server, $data, $user, $str) = @_;
    my ($sid, $aid, $updated) = split /\W/, $str or return;
    my $act = lookup_sid_aid($sid, $aid) or return;
    login_account($act, $user);
    
    # TODO: if this updated time is newer than what we know,
    # or if the account is unknown (thought it shouldn't be),
    # send ACCTIDK. then update any logged in users' {account}.

}

# :uid LOGOUT
sub in_logout {
    my ($server, $data, $user) = @_;
    logout_account($user);
}

$mod