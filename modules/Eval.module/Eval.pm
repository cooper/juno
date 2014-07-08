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

our %user_commands = (EVAL => {
    code    => \&_eval,
    desc    => 'evaluate a line of Perl code',
    params  => '-oper(eval) any(opt) :rest',
    fntsy   => 1
});

sub _eval {
    my ($user, $event, $ch_name, $code) = @_;
    my $channel = $pool->lookup_channel($ch_name);
    $code = join(' ', $ch_name, $code // '') unless $channel;

    # start eval block.
    if ($code eq 'BLOCK') {
        $user->{eval_block} = [];
        return 1;
    }
    
    # stop eval black.
    elsif ($code eq 'END') {
        my $block = delete $user->{eval_block} or return;
        $code = join "\n", @$block;
    }
    
    # if there is an eval block in the works, use it.
    elsif ($user->{eval_block}) {
        push @{ $user->{eval_block} }, $code;
        return 1;
    }
    
    # evaluate.
       $code //= '';
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