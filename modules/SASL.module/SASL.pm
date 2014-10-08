# Copyright (c) 2014, matthew
#
# Created on mattbook
# Thu Jun 26 22:26:14 EDT 2014
# SASL.pm
#
# @name:            'SASL'
# @package:         'M::SASL'
# @description:     'Provides SASL authentication'
#
# @depends.modules:  ['Base::Capabilities', 'Base::RegistrationCommands', 'Account']
#
# @author.name:     'Matthew Barksdale'
# @author.website:  'https://github.com/mattwb65'
#
package M::SASL;

use warnings;
use strict;
use 5.010;

use MIME::Base64;
use M::Account qw(lookup_account_name);

our ($api, $mod, $pool);

sub init {
    $mod->register_capability('sasl');
    $pool->on('user.initially_propagated' => \&user_propagated, with_eo => 1);
    
    $mod->register_registration_command(
        name       => 'AUTHENTICATE',
        code       => \&rcmd_authenticate,
        paramaters => 1
    ) or return;
    
    $mod->register_user_numeric(
        name    => shift @$_,
        number  => shift @$_,
        format  => shift @$_
    ) or return foreach (
        # Provided by M::Account RPL_LOGGEDIN (900) RPL_LOGGEDOUT (901)
        [ ERR_NICKLOCKED  => 902, ':You must use a nick assigned to you'        ],
        [ RPL_SASLSUCCESS => 903, ':SASL authentication successful'             ],
        [ ERR_SASLFAIL    => 904, ':SASL authentication failed'                 ],
        [ ERR_SASLTOOLONG => 905, ':SASL message too long'                      ],
        [ ERR_SASLABORTED => 906, ':SASL authentication aborted'                ],
        [ ERR_SASLALREADY => 907, ':You have already authenticated using SASL'  ],
        [ RPL_SASLMECHS   => 908, '%s :are available SASL mechanisms'           ]
    );
    
    return 1;
}

# Registration command: AUTHENTICATE
sub rcmd_authenticate {
    my ($connection, $event, $arg) = @_;
    $connection->numeric('ERR_SASLABORTED') and return if $arg eq '*';
    $connection->numeric('ERR_SASLALREADY') and return if $connection->{sasl};
    $connection->numeric(RPL_SASLMECHS => 'PLAIN') and return 1 if uc $arg eq 'M';
    
    if (!exists $connection->{sasl_pending})
    {
        if (uc $arg ne 'PLAIN') {
            $connection->numeric('ERR_SASLFAIL');
            return;
         } else {
             $connection->send('AUTHENTICATE +');
             $connection->{sasl_pending} = 1;
         }
    } else {
        my (undef, $user, $password) = split('\0', decode_base64($arg));
        my $act = lookup_account_name($user);
        if ($act && $act->verify_password($password)) {
            $connection->{sasl_account} = $act;
            $connection->{sasl} = 1;
            
            # do this the ugly way because user object does not yet exist.
            my $c    = $connection;
            my $full = "$$c{nick}!$$c{ident}\@$$c{host}";
            $connection->numeric(RPL_LOGGEDIN => $full, $act->{name}, $act->{name});
            
            $connection->numeric('RPL_SASLSUCCESS');
            delete $connection->{sasl_pending};
        } else {
          $connection->numeric('ERR_SASLFAIL');
          return;
        }
    }
    return 1;
}

# user.new event
sub user_propagated {
    my ($user, $event) = @_;
    my $act = delete $user->{sasl_account} or return;
    $act->login_user($user);
}

$mod

