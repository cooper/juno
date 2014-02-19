#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
# this handles local user input
package user::mine;

use warnings;
use strict;

use utils qw[col log2 conf gv];

our (%numerics, %commands);

# register command handlers
sub register_handler {
    my ($source, $command) = (shift, uc shift);

    # does it already exist?
    if (exists $commands{$command}) {
        log2("attempted to register $command which already exists");
        return
    }

    my $params = shift;

    # ensure that it is CODE
    my $ref = shift;
    if (ref $ref ne 'CODE') {
        log2("not a CODE reference for $command");
        return
    }

    # one per source
    if (exists $commands{$command}{$source}) {
        log2("$source already registered $command; aborting");
        return
    }

    my $desc = shift;

    # success
    $commands{$command}{$source} = {
        code    => $ref,
        params  => $params,
        source  => $source,
        desc    => $desc
    };
    log2("$source registered $command: $desc");
    return 1
}

# unregister
sub delete_handler {
    my $command = uc shift;
    log2("deleting handler $command");
    delete $commands{$command}
}

# register user numeric
sub register_numeric {
    my ($source, $numeric, $num, $fmt) = @_;
print "REG: @_\n";
    # does it already exist?
    if (exists $numerics{$numeric}) {
        log2("attempted to register $numeric which already exists");
        return
    }

    $numerics{$numeric} = [$num, $fmt];
    log2("$source registered $numeric $num");
    return 1
}

# unregister user numeric
sub delete_numeric {
    my ($source, $numeric) = (shift, shift);

    # does it exist?
    if (!exists $numerics{$numeric}) {
        log2("attempted to delete $numeric which does not exists");
        return
    }

    delete $numerics{$numeric};
    log2("$source deleted $numeric");
    
    return 1
}

sub handle {
    my $user = shift;
    foreach my $line (split "\n", shift) {

        my @s = split /\s+/, $line;

        if ($s[0] =~ m/^:/) { # lazy way of deciding if there is a source provided
            shift @s
        }

        my $command = uc $s[0];

        if ($commands{$command}) { # an existing handler

            foreach my $source (keys %{$commands{$command}}) {
                if ($#s >= $commands{$command}{$source}{params}) {
                    $commands{$command}{$source}{code}($user, $line, @s)
                }
                else { # not enough parameters
                    $user->numeric('ERR_NEEDMOREPARAMS', $s[0])
                }
            }

        }
        else { # unknown command
            $user->numeric('ERR_UNKNOWNCOMMAND', $s[0])
        }

    }
    return 1
}

sub send {
    my $user = shift;
    if (!$user->{conn}) {
        my $sub = (caller 1)[3];
        log2("can't send data to a nonlocal user! please report this error by $sub. $$user{nick}");
        return
    }
    $user->{conn}->send(@_)
}

# send data with a source
sub sendfrom {
    my ($user, $source) = (shift, shift);
    if (!$user->{conn}) {
        my $sub = (caller 1)[3];
        log2("can't send data to a nonlocal user! please report this error by $sub. $$user{nick}");
        return
    }
    $user->{conn}->send(map { ":$source $_" } @_)
}

# send data with this server as the source
sub sendserv {
    my $user = shift;
    if (!$user->{conn}) {
        my $sub = (caller 1)[3];
        log2("can't send data to a nonlocal user! please report this error by $sub. $$user{nick}");
        return
    }
    $user->{conn}->send(map { ':'.gv('SERVER', 'name')." $_" } @_)
}

# a notice from server
# revision: supports nonlocal users as well now
sub server_notice {
    my ($user, @args) = @_;
    my $msg = $args[1] ? "*** $args[0]: $args[1]" : $args[0];
    if ($user->is_local) {
        $user->{conn}->send(':'.gv('SERVER', 'name')." NOTICE $$user{nick} :$msg");
    }
    else {
        server::mine::fire_command($user->{location}, privmsgnotice => 'NOTICE', gv('SERVER'), $user, $msg);
    }
}

# send a numeric to a local user.
sub numeric {
    my ($user, $const, $response) = (shift, shift);
    
    # does not exist.
    if (!$numerics{$const}) {
        log2("attempted to send nonexistent numeric $const");
        return;
    }
    
    my ($num, $val) = @{ $numerics{$const} };

    # CODE reference for numeric response.
    if (ref $val eq 'CODE') {
        $response = $val->($user, @_);
    }
    
    # formatted string.
    else {
        $response = sprintf $val, @_;
    }
    
    $user->sendserv("$num $$user{nick} $response");
    return 1;
    
}

# send welcomes
sub new_connection {
    my $user = shift;

    # set modes
    $user->handle_mode_string(conf qw/users automodes/);

    # send numerics
    $user->numeric('RPL_WELCOME', conf('network', 'name'), $user->{nick}, $user->{ident}, $user->{host});
    $user->numeric('RPL_YOURHOST', gv('SERVER', 'name'), gv('NAME').q(-).gv('VERSION'));
    $user->numeric('RPL_CREATED', POSIX::strftime('%a %b %d %Y at %H:%M:%S %Z', localtime gv('START')));
    $user->numeric('RPL_MYINFO', gv('SERVER', 'name'), gv('NAME').q(-).gv('VERSION'), user::modes::mode_string(), channel::modes::mode_string());
    $user->user::numerics::rpl_isupport();

    # LUSERS and MOTD
    $user->handle('LUSERS');
    $user->handle('MOTD');

    # send mode string
    $user->sendfrom($user->{nick}, "MODE $$user{nick} :".$user->mode_string);

    # tell other servers
    server::mine::fire_command_all(uid => $user);
}

1
