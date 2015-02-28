# Copyright (c) 2012-14, Mitchell Cooper
#
# @name:            "LOLCAT"
# @package:         "M::LOLCAT"
# @description:     "SPEEK LIEK A LOLCATZ!"
#
# @depends.modules: "Base::UserCommands"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::LOLCAT;

use warnings;
use strict;
use 5.010;

use Acme::LOLCAT;
use utils qw(col);

our ($api, $mod, $pool);

our %user_commands = (LOLCAT => {
    desc   => 'SPEEK LIEK A LOLCATZ!',
    params => 'channel *',
    code   => \&lolcat,
    fntsy  => 1
});

sub lolcat {
    my ($user, $event, $channel, $msg) = @_;
    my $cmd = ':'.$user->full." PRIVMSG $$channel{name} :$msg";
    $user->handle("ECHO $$channel{name} :$msg");
}

$mod