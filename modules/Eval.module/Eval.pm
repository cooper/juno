# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "Eval"
# @package:         "M::Eval"
# @description:     "evaluate a line of Perl code"
#
# @depends.modules: ['Base::UserCommands']
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Eval;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $me, $pool);

sub init {
    $mod->register_user_command(
        name        => 'eval',
        code        => \&_eval,
        description => 'evaluate a line of Perl code',
        parameters  => '-oper(eval) any(opt) :rest',
        fantasy     => 1
    ) or return;
}

sub _eval {
    my ($user, $data, $ch_name, $code) = @_;
    my $channel = $pool->lookup_channel($ch_name);
    $code = join(' ', $ch_name, $code // '') unless $channel;
    
    # evaluate.
    my $result = eval $code;
    my @result = split "\n", $result // ($@ || "\2undef\2");

    # send the result to the channel.
    my $i = 0;
    if ($channel) {
        foreach (@result) {
            $i++;
            my $e = ($#result ? "($i): " : '').$_;
            $user->sendfrom($user->full, "PRIVMSG $$channel{name} :$e")
            if $user->handle("PRIVMSG $$channel{name} :$e");
        }
    }
    
    # send the result to the user.
    else {
        $user->server_notice($i++ ? "eval ($i)" : 'eval', $_) foreach @result;
    }
    
    return 1;
}

$mod