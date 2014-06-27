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
# @depends.modules  ['Base::Capabilities', 'Base::RegistrationCommands', 'M::Account']
#
# @author.name:     'Matthew Barksdale'
# @author.website:  'https://github.com/mattwb65'
#
package M::SASL;

use warnings;
use strict;
use 5.010;

use MIME::Base64;
use M::Account qw(verify_password login_account);

our ($api, $mod, $pool);

sub init {
    $mod->register_registration_cmmand(
        name       => 'AUTHENTICATE',
        code       => \&rcmd_authenticate,
        paramaters => 1
    ) or return;
    $mod->register_capability('sasl');
    $pool->on('user.new' => \&user_new, with_eo => 1);
}

# Registration command: AUTHENTICATE
sub rcmd_authenticate {
    my ($connection, $event, $arg) = @_;
    $connection->early_reply(906, ':SASL authentication aborted') and return if $arg eq '*';
    $connection->early_reply(907, ':You have already authenticated using SASL') and return if $connection->{sasl};
    $connection->early_reply(908, 'PLAIN :are availiable SASL mechanisms') and return if uc $arg eq 'M';
    $connection->{sasl_started} = 1;
    if ($connection->{sasl_started})
    {
        if (uc $arg ne 'PLAIN') {
            $connection->early_reply(904, ':SASL authentication failed');
            delete $connection->{sasl_started};
            return;
         } else {
             $connection->send('AUTHENTICATE +');
         }
    } else {
        my (undef, $user, $password) = split('\0', decode_base64($arg));
        if (!(my $act = verify_password($user, $password))) {
            $connection->early_reply(904, ':SASL authentication failed');
            return;
        } else {
            $connection->{sasl_account} = $act;
            $connection->{sasl} = 1;
            $connection->early_reply(900 => "$$connection{nick}!$$connection{user}\@$$connection{host} $$act{name} :You are now logged in as $$act{name}.");
            $connection->early_reply(903 => ':SASL authentication successful');
            delete $connection->{sasl_started};
        }
    }
}

# user.new event
sub user_new {
    my ($event, $user) = @_;
    if ($user->{sasl_acount}) {
        login_account(delete $user->{sasl_account}, $user, undef, undef, 1);
    }
}

$mod

