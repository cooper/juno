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

sub init {
    $mod->register_user_command(
        name        => 'lolcat',
        description => 'SPEEK LIEK A LOLCATZ!',
        parameters  => 2,
        code        => \&lolcat,
        fantasy     => 1
    ) or return;
    
    return 1;
}

sub lolcat {
    my ($user, $data, @args) = @_;
    my $msg = translate(col((split /\s+/, $data, 3)[2]));
    return unless my $where = $pool->lookup_channel($args[1]);
    my $cmd = ':'.$user->full." PRIVMSG $$where{name} :$msg";
    $user->send($cmd) if $user->handle("PRIVMSG $$where{name} :$msg");
}

$mod