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

M::Account->import(qw(login_account logout_account register_account account_info all_accounts));

our ($api, $mod, $pool, $db, $me);

sub init {
    $db = $M::Account::db or return;

    # IRCd event for burst.
    $pool->on('server.send_burst' => \&send_burst,
        name  => 'account',
        after => 'core',
        with_evented_obj => 1
    );
    
    $mod->register_outgoing_command(
        name => 'acct',
        code => \&out_acct
    ) or return;
    
    $mod->register_outgoing_command(
        name => 'acctinfo',
        code => \&out_acctinfo
    ) or return;
    
    return 1;
}

sub send_burst {  
    my ($server, $fire, $time) = @_;
    $server->fire_command(acct => @{ all_accounts() });
    # XXX:
    $server->fire_command(acctinfo => all_accounts()->[0]);
}

#########################
### OUTGOING COMMANDS ###
#########################

sub out_acct {
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

#########################
### INCOMING COMMANDS ###
#########################



$mod