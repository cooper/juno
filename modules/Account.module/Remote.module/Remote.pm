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
use Scalar::Util 'weaken';
M::Account->import(qw/lookup_account_hash lookup_account_sid_aid add_or_update_account/);

our ($api, $mod, $pool, $me, $table);

sub init {
    $table = $M::Account::table or return;

    # IRCd event for burst.
    $pool->on('server.send_burst' => \&send_burst,
        name  => 'account',
        after => 'core',
        with_eo => 1
    );
    
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
    
    # send accounts.
    if (!$server->{accounts_negotiated}) {
        my @act_refs = $table->rows->select_hash;
        $server->fire_command(acct => map { lookup_account_hash(%$_) } @act_refs);
        $server->{accounts_negotiated} = 1;
    }
    
    # send logins.
    # because this is sent during burst, it should not be propagated.
    $server->fire_command(login => $_, $_->{account}) foreach
        grep { $_->{account} } $pool->all_users;
        
    return 1;
}

#########################
### OUTGOING COMMANDS ###
#########################

sub out_acct {
    return unless @_;
    my $str = '';
    foreach my $act (@_) {
        $str .= ' ' if $str;
        $str .= $act->id.q(,).$act->{updated};
    }
    ":$$me{sid} ACCT $str"
}

sub out_acctinfo {
    my $act = shift;
    my $str = '';
    foreach my $key (keys %$act) {
        my $value = $act->{$key};
        next unless defined $value;
        next if ref $value;
        $str .= "$key $value ";
    }
    ":$$me{sid} ACCTINFO $str"
}

sub out_acctidk {
    my $str = '';
    while (@_) {
        my $item = shift;
        $str .= ' ' if $str;
        if (ref $item eq 'ARRAY') {
            $str .= "$$item[0].$$item[1]";
            next;
        }
        $item->can('id') or next
        $str .= $item->id;
    }
    ":$$me{sid} ACCTIDK $str"
}

sub out_login {
    my ($user, $act) = @_;
    my $id = $act->id;
    ":$$user{uid} LOGIN $id,$$act{updated}"
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
        if (my $act = lookup_account_sid_aid($sid, $aid)) {
        
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
        push @i_dk, [$sid, $aid];
        
    }
    
    # add the rest of the accounts.
    foreach my $act_ref ($table->rows->select_hash('csid', 'id')) {
        my $act = lookup_account_hash(%$act_ref) or next;
        next if $done{ $act->id };
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
        my $act = lookup_account_sid_aid($sid, $aid) or next;
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
    return unless defined $act{csid} && defined $act{id};
    add_or_update_account(%act);
}

# :uid LOGIN sid.aid,updated
sub in_login {
    my ($server, $data, $user, $str) = @_;
    my ($sid, $aid, $updated) = split /\W/, $str or return;
    my $act = lookup_account_sid_aid($sid, $aid) or return;
    
    # we know about this account. log in
    if ($act) {
        return $act->login_user($user);
    }
    
    # not familiar with this account.
    # this will be set aside until ACCTINFO received.
    my $users = $M::Account::users_waiting{"$sid.$aid"} ||= [];
    push @$users, $user;
    weaken($users->[$#$users]);
    
    # TODO: if this updated time is newer than what we know,
    # or if the account is unknown (thought it shouldn't be),
    # send ACCTIDK. then update any logged in users' {account}.

}

# :uid LOGOUT
sub in_logout {
    my ($server, $data, $user) = @_;
    $user->{account}->logout_user($user) if $user->{account};
}

$mod