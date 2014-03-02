#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
# this handles local user input
package user::mine;

use warnings;
use strict;

use utils qw[col log2 conf v];

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
    my ($source, $numeric) = @_;

    # does it exist?
    if (!exists $numerics{$numeric}) {
        log2("attempted to delete $numeric which does not exists");
        return
    }

    delete $numerics{$numeric};
    log2("$source deleted $numeric");
    
    return 1
}

####################
### USER METHODS ###
####################

sub safe {
    my $user = shift;
    if (!$user->is_local) {
        my $caller = caller;
        log2("Attempted to call ->$caller() on nonlocal user");
        return;
    }
    return ($user, @_);
}

sub handle {
    @_ = &safe or return;
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
    @_ = &safe or return;
    my $user = shift;
    if (!$user->{conn}) {
        my $sub = (caller 1)[3];
        log2("can't send data to a nonlocal or disconnected user! $$user{nick}");
        return;
    }
    $user->{conn}->send(@_);
}

# send data with a source
sub sendfrom {
    my ($user, $source) = (shift, shift);
    $user->send(map { ":$source $_" } @_)
}

# send data with this server as the source
sub sendserv {
    my $user = shift;
    $user->send(map { ':'.v('SERVER', 'name')." $_" } @_)
}

# a notice from server
# revision: supports nonlocal users as well now
sub server_notice {
    @_ = &safe or return;
    my ($user, @args) = @_;
    my $msg = defined $args[1] ? "*** $args[0]: $args[1]" : $args[0];
    
    # user is local.
    if ($user->is_local) {
        $user->send(':'.v('SERVER', 'name')." NOTICE $$user{nick} :$msg");
        return 1;
    }
    
    # not local; pass it on.
    server::mine::fire_command($user->{location}, privmsgnotice =>
        'NOTICE',
        v('SERVER'),
        $user,
        $msg
    );
    
}

# send a numeric to a local user.
sub numeric {
    @_ = &safe or return;
    my ($user, $const, @response) = (shift, shift);
    
    # does not exist.
    if (!$numerics{$const}) {
        log2("attempted to send nonexistent numeric $const");
        return;
    }
    
    my ($num, $val) = @{ $numerics{$const} };

    # CODE reference for numeric response.
    if (ref $val eq 'CODE') {
        @response = $val->($user, @_);
    }
    
    # formatted string.
    else {
        @response = sprintf $val, @_;
    }
    
    $user->sendserv("$num $$user{nick} $_") foreach @response;
    return 1;
    
}

# send welcomes
sub new_connection {
    @_ = &safe or return;
    my $user = shift;

    # set modes
    $user->handle_mode_string(conf qw/users automodes/);

    # send numerics
    $user->numeric(RPL_WELCOME  => conf('network', 'name'), $user->{nick}, $user->{ident}, $user->{host});
    $user->numeric(RPL_YOURHOST => v('SERVER', 'name'), v('NAME').q(-).v('VERSION'));
    $user->numeric(RPL_CREATED  => POSIX::strftime('%a %b %d %Y at %H:%M:%S %Z', localtime v('START')));
    $user->numeric(RPL_MYINFO   =>
        v('SERVER', 'name'),
        v('NAME').q(-).v('VERSION'),
        user::modes::mode_string(),
        channel::modes::mode_string()
    );
    $user->numeric('RPL_ISUPPORT');

    # LUSERS and MOTD
    $user->handle('LUSERS');
    $user->handle('MOTD');

    # send mode string
    $user->sendfrom($user->{nick}, "MODE $$user{nick} :".$user->mode_string);

    # tell other servers
    server::mine::fire_command_all(uid => $user);
}

# send to all members of channels in common
# with a user but only once.
# note: the source user does not need to be local.
# TODO: eventually, I would like to have channels stored in user.
sub send_to_channels {
    my ($user, $what) = @_;
    
    # this user included.
    $user->sendfrom($user->full, $what);
    my %sent = ( $user => 1 );

    # check each channel.
    foreach my $channel ($main::pool->channels) {
    
        # source is not in this channel.
        next unless $channel->has_user($user);

        # send to each member.
        foreach my $usr (@{ $channel->{users} }) {
        
            # not local.
            next unless $usr->is_local;
            
            # already sent there.
            next if $sent{$usr};
            
            $usr->sendfrom($user->full, $what);
            $sent{$usr} = 1;
        }
    }
    
    return 1;
}

1
