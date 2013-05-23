# Copyright (c) 2012, Mitchell Cooper
#
# provides LOLCAT command
# requires Acme::LOLCAT
#
# works exactly like PRIVMSG except translates your message to LOLCAT.
# unlike privmsg, it boings a PRIVMSG back to the client who sent it.
# it only works for channels.

package API::Module::LOLCAT;

use warnings;
use strict;

use Acme::LOLCAT;
use utils qw[cut_to_limit col];

our $mod = API::Module->new(
    name        => 'LOLCAT',
    version     => '0.1',
    description => 'SPEEK LIEK A LOLCATZ!',
    requires    => ['UserCommands'],
    initialize  => \&init
);
 
sub init {

    # register user commands
    $mod->register_user_command(
        name        => 'lolcat',
        description => 'SPEEK LIEK A LOLCATZ!',
        parameters  => 2,
        code        => \&lolcat
    ) or return;

    return 1
}


sub lolcat {
    my ($user, $data, @args) = @_;
    my $msg   = translate(col((split /\s+/, $data, 3)[2]));
    return unless my $where = channel::lookup_by_name($args[1]);
    my $cmd   = q(:).$user->full." PRIVMSG $$where{name} :$msg";
    $user->send($cmd) if $user->handle("PRIVMSG $$where{name} :$msg");
}

$mod
