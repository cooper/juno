#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
# this handles local user input
package user::mine;

use warnings;
use strict;

use utils qw[col log2 conf v];

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
    return if !$user->{conn} || $user->{conn}{goodbye};

    foreach my $line (split "\n", shift) {

        my @s = split /\s+/, $line;

        if ($s[0] =~ m/^:/) { # lazy way of deciding if there is a source provided
            shift @s
        }

        my $command = uc $s[0];

        if ($::pool->user_handlers($command)) { # an existing handler

            foreach my $handler ($::pool->user_handlers($command)) {
                if ($#s >= $handler->{params}) {
                    $handler->{code}($user, $line, @s)
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
    $user->send(map { ":$source $_" } @_);
}

# send data with this server as the source
sub sendme {
    my $user = shift;
    $user->sendfrom(v('SERVER', 'name'), @_);
}

# a notice from server
# revision: supports nonlocal users as well now
sub server_notice {
    @_ = &safe or return;
    my ($user, @args) = @_;
    my $msg = defined $args[1] ? "*** $args[0]: $args[1]" : $args[0];
    
    # user is local.
    if ($user->is_local) {
        $user->sendme("NOTICE $$user{nick} :$msg");
        return 1;
    }
    
    # not local; pass it on.
    $user->{location}->fire_command(privmsgnotice =>
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
    if (!$::pool->numeric($const)) {
        log2("attempted to send nonexistent numeric $const");
        return;
    }
    
    my ($num, $val) = @{ $::pool->numeric($const) };

    # CODE reference for numeric response.
    if (ref $val eq 'CODE') {
        @response = $val->($user, @_);
    }
    
    # formatted string.
    else {
        @response = sprintf $val, @_;
    }
    
    $user->sendme("$num $$user{nick} $_") foreach @response;
    return 1;
    
}

# send welcomes
sub new_connection {
    @_ = &safe or return;
    my $user = shift;

    # set modes.
    # note: we don't use do_mode_string() because we wait until afterward to send MODE.
    $user->handle_mode_string(conf qw/users automodes/);

    # send numerics
    $user->numeric(RPL_WELCOME  => conf('network', 'name'), $user->{nick}, $user->{ident}, $user->{host});
    $user->numeric(RPL_YOURHOST => v('SERVER', 'name'), v('NAME').q(-).v('VERSION'));
    $user->numeric(RPL_CREATED  => POSIX::strftime('%a %b %d %Y at %H:%M:%S %Z', localtime v('START')));
    $user->numeric(RPL_MYINFO   =>
        v('SERVER', 'name'),
        v('NAME').q(-).v('VERSION'),
        ircd::user_mode_string(),
        ircd::channel_mode_string()
    );
    $user->numeric('RPL_ISUPPORT');

    # LUSERS and MOTD
    $user->handle('LUSERS');
    $user->handle('MOTD');

    # send mode string
    $user->sendfrom($user->{nick}, "MODE $$user{nick} :".$user->mode_string);

    # tell other servers
    $::pool->fire_command_all(uid => $user);
}

# send to all members of channels in common
# with a user but only once.
# note: the source user does not need to be local.
# TODO: eventually, I would like to have channels stored in user.
sub send_to_channels {
    my ($user, $what) = @_;
    
    # this user included.
    $user->sendfrom($user->full, $what) if $user->is_local;
    my %sent = ( $user => 1 );

    # check each channel.
    foreach my $channel ($::pool->channels) {
    
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

# handle a modestring, send to the local user, send to other servers.
sub do_mode_string {
    my ($user, $modestr, $force) = @_;
    
    # handle.
    my $result = $user->handle_mode_string($modestr, $force) or return;
    
    # not local; don't do more.
    return unless $user->is_local;
    
    # tell the user himself and other servers.
    $user->sendfrom($user->{nick}, "MODE $$user{nick} :$result");
    $::pool->fire_command_all(umode => $user, $result);
    
}

1
