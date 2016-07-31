# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-Mac-mini.local
# Thu Aug  7 19:33:03 EDT 2014
# Eval.pm
#
# @name:            'Eval'
# @package:         'M::Eval'
# @description:     'evaluate Perl code'
#
# @depends.modules: ['Base::UserCommands']
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Eval;

use warnings;
use strict;
use 5.010;

use utils qw(trim);

our ($api, $mod, $me, $pool, $conf);

my %allowed;
our $depth = 1;

our %user_commands = (EVAL => {
    code    => \&_eval,
    desc    => 'evaluate Perl code',
    params  => 'any(opt) :rest'
});

# consider: perhaps we should use IO::Async::File to automatically
# reload the evalers file every now and then. or maybe it's not worth it.
sub init {
    load();
    return 1;
}

# load the eval configuration.
sub load {
    %allowed = ();
    open my $fh, '<', "$::run_dir/etc/evalers.conf" or return;
    while (my $oper_name = <$fh>) {
        chomp $oper_name;
        $allowed{$oper_name} = 1;
    }
    close $fh;
}

sub _eval {
    my ($user, $event, $ch_name, $code) = @_;

    # unauthorized attempt.
    if (!user_authorized($user)) {
        $user->numeric(ERR_NOPRIVILEGES => 'eval');
        return;
    }

    # find destination and code
    my $channel = $pool->lookup_channel($ch_name);
    $code = join(' ', $ch_name, $code // '') unless $channel;
    return if !length $code;

    # create a function to write to the destination
    my $write = sub {
        my ($text, $pfx) = @_;
        $user or return;
        if ($channel) {
            $channel->notice_all("$pfx: $text", undef, 1);
            return;
        }
        $user->server_notice(eval => "$pfx: $text");
    };

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
    my ($error, $result);
    my $passed = eval {

        # catch timeouts
        local $SIG{ALRM} = sub { die "Timed out\n" };

        # catch warnings
        local $SIG{__WARN__} = sub {
            $user && $channel or return;
            my @lines = split "\n", shift; my $i = 1;
            $write->($_, $#lines ? 'W'.$i++ : 'W') for @lines;
        };

        # do the eval
        alarm 10;
        my $r = eval $code;
        alarm 0;

        # store the results
        $error  = $@;
        $result = $r;

        !length $error
    };

    # determine the results
    my $pfx = 'R';
    if (!$passed) {
        $result = trim($error || $@ || 'unknown');
        $pfx = 'E';
    }
    $result //= "(undef)";
    my @result = split "\n", "$result\n", -1;
    pop @result;

    # send the result.
    my $i = 0;
    foreach (@result) {
        $i++;
        my $line = length() ? $_ : '(empty string)';
        my $pfx  = $#result ? "$pfx$i" : $pfx;
        $write->($line, $pfx);
    }

    undef $write;
    return 1;
}

# is a user authorized to eval?
sub user_authorized {
    my $user = shift;
    return unless $user->is_local && $user->is_mode('ircop') && defined $user->{oper};
    return $allowed{ lc $user->{oper} };
}

#############################
### convenience functions ###
#############################

use utils qw(conf ref_to_list);

sub Dumper {
    ircd::load_or_reload('Data::Dumper', 0) or return;
    my $d = Data::Dumper->new([ @_ ]);
    return trim($d->Maxdepth($depth)->Dump);
}

sub user { $pool->lookup_user    (@_)  || $pool->lookup_user_nick   (@_) }
sub serv { $pool->lookup_server  (@_)  || $pool->lookup_server_mask (@_) }
sub chan { $pool->lookup_channel (@_)  }

sub Dump;       *Dump    = *Dumper;
sub server;     *server  = *serv;
sub channel;    *channel = *chan;

$mod
