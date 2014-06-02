# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "Account::Remote"
# @package:         "M::Account::Remote"
# @description:     "implements user accounts"
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
    
    # incoming commands.
    $mod->register_server_command(%$_) || return foreach (
        {
            name       => 'acct',
            parameters => 'dummy dummy :rest', # don't even care about source
            code       => \&in_acct
        },
        {
            name       => 'acctinfo',
            parameters => 'dummy dummy @rest',
            code       => \&in_acctinfo,
            forward    => 2 # only when not in burst
        },
        {
            name       => 'acctidk',
            parameters => 'dummy dummy @rest',
            code       => \&in_acctidk
        }
    );
    
    # outgoing commands.
    $mod->register_outgoing_command(
        name => $_->[0],
        code => $_->[1]
    ) || return foreach (
        [ acct     => \&out_acct     ],
        [ acctinfo => \&out_acctinfo ],
        [ acctidk  => \&out_acctidk  ]
    );

    return 1;
}

sub send_burst {  
    my ($server, $fire, $time) = @_;
    return if $server->{accounts_negotiated};
    $server->fire_command(acct => @{ all_accounts() });
    $server->{accounts_negotiated} = 1;
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

#########################
### INCOMING COMMANDS ###
#########################

sub in_acct {
    # server dummy  :rest
    # :sid ACCT info
    my ($server, $data, $str) = @_;
    my @items = split /\W/, trim($str);
    return if @items % 3;
    
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
    $server->fire_command(acctinfo => $_) foreach @u_dk;
    
}

# :sid ACCTIDK 1.1 1.2
sub in_acctidk {
    my ($server, $data, $str) = @_;
    my @items = split /\W/, trim($str);
    return if @items % 2;
    
    # find the accounts.
    my @accts;
    while (my ($sid, $aid) = splice @items, 0, 2) {
        my $act = lookup_sid_aid($sid, $aid) or next;
        push @accts, $act;
    }
    
    # tell the server about them.
    $server->fire_command(acctinfo => $_) foreach @accts;
    
}

# :sid ACCTINFO csid 0 updated 234839344 ...
sub in_acctinfo {
    my ($server, $data, @rest) = @_;
    return if @rest % 2;
    my %act = @rest;
    add_account(\%act);
}

$mod