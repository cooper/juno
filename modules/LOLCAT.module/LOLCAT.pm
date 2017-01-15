# Copyright (c) 2012-16, Mitchell Cooper
#
# @name:            "LOLCAT"
# @package:         "M::LOLCAT"
# @description:     "SPEEK LIEK A LOLCATZ!"
#
# @depends.bases+   'UserCommands'
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::LOLCAT;

use warnings;
use strict;
use 5.010;

use Acme::LOLCAT qw(translate);
use utils qw(col);

our ($api, $mod, $pool);

our %user_commands = (LOLCAT => {
    desc   => 'SPEEK LIEK A LOLCATZ!',
    params => 'channel :',
    code   => \&lolcat
});

sub lolcat {
    my ($user, $event, $channel, $msg) = @_;
    $msg = translate($msg);
    $user->handle("ECHO $$channel{name} :$msg");
}

$mod
