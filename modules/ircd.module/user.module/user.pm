# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "ircd::user"
# @package:         "user"
# @description:     "represents an IRC user"
# @version:         ircd->VERSION
# @no_bless:        1
# @preserve_sym:    1
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package user;

use warnings;
use strict;
use 5.010;
use parent 'Evented::Object';
use overload
    fallback => 1,
    '""'     => sub { shift->id },
    '0+'     => sub { shift     },
    bool     => sub { 1         };
    
use utils qw(v notice col conf irc_time);
use List::Util 'first';

our ($api, $mod, $pool, $me);

# create a new user.
sub new {
    my ($class, %opts) = @_;
    return bless {
        modes => [],
        flags => [],
        %opts
    }, $class;
}


# user has a mode enabled.
sub is_mode {
    my ($user, $mode) = @_;
    return 1 if defined first { $_ eq $mode } @{ $user->{modes} };
    return;
}

# low-level setting of mode.
sub set_mode {
    my ($user, $name) = @_;
    return if $user->is_mode($name);
    L("$$user{nick} +$name");
    push @{ $user->{modes} }, $name;
}

# low-level unsetting of mode.
sub unset_mode {
    my ($user, $name) = @_;

    # is the user set to this mode?
    if (!$user->is_mode($name)) {
        L("attempted to unset mode $name on that is not set on $$user{nick}; ignoring.");
        return;
    }

    # he is, so remove it.
    L("$$user{nick} -$name");
    @{ $user->{modes} } = grep { $_ ne $name } @{ $user->{modes} };

    return 1;
}

# handle a user quit.
# this does not close a connection; use $user->conn->done() for that.
sub quit {
    my ($user, $reason) = @_;
    notice(user_quit => $user->notice_info, $user->{real}, $user->{server}{name}, $reason);
    
    # send to all users in common channels as well as including himself.
    $user->send_to_channels("QUIT :$reason");

    # remove from all channels.
    $_->remove($user) foreach $user->channels;

    $pool->delete_user($user) if $user->{pool};
    $user->delete_all_events();
}

# low-level nick change.
sub change_nick {
    my ($user, $newnick) = @_;
    $pool->change_user_nick($user, $newnick) or return;
    notice(user_nick_change => $user->notice_info, $newnick);
    $user->{nick} = $newnick;
}

# handle a mode string and convert the mode letters to their mode
# names by searching the user's server's modes. returns the mode
# string, or '+' if no changes were made.
sub handle_mode_string {
    my ($user, $modestr, $force) = @_;
    L("set $modestr on $$user{nick}");
    my $state = 1;
    my $str   = '+';
    letter: foreach my $letter (split //, $modestr) {
        if ($letter eq '+') {
            $str .= '+' unless $state;
            $state = 1;
        }
        elsif ($letter eq '-') {
            $str .= '-' if $state;
            $state = 0;
        }
        else {
            my $name = $user->{server}->umode_name($letter);
            if (!defined $name) {
                L("unknown mode $letter!");
                next;
            }

            # ignore stupid mode changes.
            if ($state && $user->is_mode($name) ||
              !$state && !$user->is_mode($name)) {
                next;
            }

            # don't allow this mode to be changed if the test fails
            # *unless* force is provided. generally ou want to use
            # tests only is local, since servers can do whatever.
            my $win = $pool->fire_user_mode($user, $state, $name);
            next if !$win && !$force;

            # do the change.
            my $do = $state ? 'set_mode' : 'unset_mode';
            $user->$do($name);
            $str .= $letter;
            
        }
    }

    # it's easier to do this than it is to
    # keep track of them
    $str =~ s/\+\+/\+/g;
    $str =~ s/\-\-/\-/g; 
    $str =~ s/\+\-/\-/g;
    $str =~ s/\-\+/\+/g;

    L("end of mode handle");
    return '' if $str eq '+' || $str eq '-';
    return $str;
}

# returns a +modes string.
sub mode_string {
    my $user = shift;
    return '+'.join('', sort map {
        $user->{server}->umode_letter($_)
    } @{ $user->{modes} });
}

# add oper flags.
sub add_flags {
    my $user  = shift;
    my @flags = grep { !$user->has_flag($_) } @_;
    return unless scalar @flags;
    L("adding flags to $$user{nick}: @flags");
    notice(user_opered => $user->notice_info, $user->{server}{name}, "@flags");
    push @{ $user->{flags} }, @flags;
    return @flags;
}

# remove oper flags.
sub remove_flags {
    my $user   = shift;
    my @remove = @_;
    my %r;
    L("removing flags from $$user{nick}: @remove");

    @r{@remove}++;

    my @new = grep { !exists $r{$_} } @{ $user->{flags} };
    $user->{flags} = \@new;
}

# has oper flag.
sub has_flag {
    my ($user, $flag) = @_;
    foreach (@{ $user->{flags} }) {
        return 1 if $_ eq $flag;
        return 1 if $_ eq 'all';
    }
    return;
}

# set away msg.
sub set_away {
    my ($user, $reason) = @_;
    $user->{away} = $reason;
    L("$$user{nick} is now away: $reason");
}

# return from away.
sub unset_away {
    my $user = shift;
    L("$$user{nick} has returned from being away: $$user{away}");
    delete $user->{away};
}

# channels. I need to make this more efficient eventually.
sub channels {
    my ($user, @channels) = shift;
    foreach my $channel ($pool->channels) {
        next unless $channel->has_user($user);
        push @channels, $channel;
    }
    return @channels;
}

# user is a member of this server.
sub is_local { shift->{server} == $me }

# full visible mask, e.g. w/ cloak.
sub full {
    my $user = shift;
    "$$user{nick}!$$user{ident}\@$$user{cloak}"
}

# full actual mask.
sub fullreal {
    my $user = shift;
    "$$user{nick}!$$user{ident}\@$$user{host}"
}

# full mask w/ IP rather than host.
sub fullip {
    my $user = shift;
    "$$user{nick}!$$user{ident}\@$$user{ip}"
}

# convenience for passing info to notice().
sub notice_info {
    my $user = shift;
    return ($user->{nick}, $user->{ident}, $user->{host});
}

sub DESTROY {
    my $user = shift;
    L("$user destroyed");
}

sub id            { shift->{uid}  }
sub name          { shift->{nick} }
sub conn          { shift->{conn} }

############
### MINE ###
############

# check for local user
sub safe {
    my $user = shift;
    if (!$user->is_local) {
        my $sub = (caller 1)[3];
        L("Attempted to call ->${sub}() on nonlocal user");
        return;
    }
    return unless $user->conn;
    return ($user, @_);
}

# handle incoming data.
sub handle        { @_ = &safe or return; _handle(undef, @_) }
sub handle_unsafe { _handle(1, @_) }
sub _handle       {
    my ($unsafe, $user, $data) = @_;
    return if !$unsafe && !$user->{conn};
    return if $user->{conn} && $user->{conn}{goodbye};
    
    # this is a lazy way of eliminating a source.
    my @s = split /\s+/, $data;
    shift @s if substr($s[0], 0, 1) eq ':';
    
    # ignore empty lines.
    return if not length $s[0];
    my $command = uc $s[0];
    
    foreach my $handler ($pool->user_handlers($command)) {
    
        # not enough parameters.
        if ($handler->{params} && $#s < $handler->{params}) {
            $user->numeric(ERR_NEEDMOREPARAMS => $s[0]);
            return;
        }

        # everything's good; call the handler.
        return $handler->{code}($user, $data, @s);
        
    }

    # unknown command.
    $user->numeric(ERR_UNKNOWNCOMMAND => $s[0]);
    return;
    
}

# send data to a local user.
sub send {
    @_ = &safe or return;
    my $user = shift;
    if (!$user->{conn}) {
        my $sub = (caller 1)[3];
        L("can't send data to a nonlocal or disconnected user! $$user{nick}");
        return;
    }
    $user->{conn}->send(@_);
}

# send data with a source.
sub sendfrom {
    my ($user, $source) = (shift, shift);
    $user->send(map { ":$source $_" } @_);
}

# send data with this server as the source.
sub sendme {
    my $user = shift;
    $user->sendfrom($me->{name}, @_);
}

# a notice from server.
# revision: supports nonlocal users as well now.
sub server_notice {
    my ($user, @args) = @_;
    my $cmd = ucfirst $args[0];
    my $msg = defined $args[1] ? "*** \2$cmd:\2 $args[1]" : $args[0];
    
    # user is local.
    if ($user->is_local) {
        $user->sendme("NOTICE $$user{nick} :$msg");
        return 1;
    }
    
    # not local; pass it on.
    $user->{location}->fire_command(privmsgnotice => 'NOTICE', $me, $user, $msg);
    
}

# send a numeric to a local user.
sub numeric {
    my ($user, $const, @response) = (shift, shift);
    
    # does not exist.
    if (!$pool->numeric($const)) {
        L("attempted to send nonexistent numeric $const");
        return;
    }
    
    my ($num, $val) = @{ $pool->numeric($const) };

    # CODE reference for numeric response.
    if (ref $val eq 'CODE') {
        @response = $val->($user, @_);
    }
    
    # formatted string.
    else {
        @response = sprintf $val, @_;
    }
    
    # local user.
    if ($user->is_local) {
        $user->sendme("$num $$user{nick} $_") foreach @response;
    }
    
    # remote user.
    else {
        $user->{location}->fire_command(num => $me, $user, $num, $_)
            foreach @response;
    }
    
    return 1;
    
}

# send welcomes
sub new_connection {
    @_ = &safe or return;
    my $user = shift;

    # set modes.
    # note: we don't use do_mode_string() because we wait until afterward to send MODE.
    $user->handle_mode_string(conf qw/users automodes/);
    $user->set_mode('ssl') if $user->conn->{listener}{ssl};
    
    # send numerics
    my $network = conf('server', 'network') // conf('network', 'name');
    $user->numeric(RPL_WELCOME  => $network, $user->{nick}, $user->{ident}, $user->{host});
    $user->numeric(RPL_YOURHOST => $me->{name}, v('NAME').q(-).v('VERSION'));
    $user->numeric(RPL_CREATED  => irc_time(v('START')));
    $user->numeric(RPL_MYINFO   =>
        $me->{name},
        v('SNAME').q(-).v('NAME').q(-).v('VERSION'),
        $pool->user_mode_string,
        $pool->channel_mode_string
    );
    $user->numeric('RPL_ISUPPORT');

    # LUSERS and MOTD
    $user->handle('LUSERS');
    $user->handle('MOTD');

    # send mode string
    $user->sendfrom($user->{nick}, "MODE $$user{nick} :".$user->mode_string);

    # tell other servers
    $pool->fire_command_all(uid => $user);
    
    return $user->{init_complete} = 1;
}

# send to all members of channels in common with a user but only once.
# note: the source user does not need to be local.
# also, the source user will receive the message as well if local.
sub send_to_channels {
    my ($user, $message) = @_;    
    sendfrom_to_many($user->full, $message, $user, map { $_->users } $user->channels);
    return 1;
}

# class function:
# send to a number of users but only once per user.
# returns the number of users affected.
# user::sendfrom_to_many($from, $message, @users)
sub sendfrom_to_many {
    my ($from, $message, @users) = @_;
    my %done;
    foreach my $user (@users) {
        next if !$user->is_local;
        next if $done{$user};
        $user->sendfrom($from, $message);
        $done{$user} = 1;
    }
    return scalar keys %done;
}

# handle a mode string, send to the local user, send to other servers.
sub do_mode_string { _do_mode_string(undef, @_) }

# same as do_mode_string() except it does not send to other servers.
sub do_mode_string_local { _do_mode_string(1, @_) }

sub _do_mode_string {
    my ($local_only, $user, $modestr, $force) = @_;
    
    # handle.
    my $result = $user->handle_mode_string($modestr, $force) or return;
    
    # not local or not done registering; stop.
    return if !$user->is_local || !$user->{ready};
    
    # tell the user himself and other servers.
    $user->sendfrom($user->{nick}, "MODE $$user{nick} :$result");
    $pool->fire_command_all(umode => $user, $result) unless $local_only;
    
}

# has a notice flag
sub has_notice {
    my ($user, $flag) = (shift, lc shift);
    return unless $user->{notice_flags};
    foreach my $f (@{ $user->{notice_flags} }) {
        return 1 if $f eq 'all';
        return 1 if $f eq $flag;
    }
    
    return;
}

# add a notice flag
sub add_notices {
    my ($user, @flags) = (shift, map { lc } @_);
    foreach my $flag (@flags) {
        next if $user->has_notice($flag);
        push @{ $user->{notice_flags} ||= [] }, $flag;
    }
}

# handle a kill on a local user.
sub get_killed_by {
    my ($user, $murderer, $reason) = @_;
    return unless $user->is_local;
    my $name = $murderer->name;
    $user->{conn}->done("Killed by $name: $reason");
    notice(user_killed => $user->notice_info, $murderer->full, $reason);
}

# handle an invite for a local user.
# $channel might be an object or a channel name.
sub get_invited_by {
    my ($user, $i_user, $ch_name) = @_;
    return unless $user->is_local;
    
    # it's an object.
    if (ref(my $channel = $ch_name)) {
        $ch_name = $channel->name;
        
        # user is already in channel.
        return if $channel->has_user($user);

    }
    
    $user->{invite_pending}{ lc $ch_name } = 1;
    $user->sendfrom($i_user->full, "INVITE $$user{nick} $ch_name");
}

# CAP shortcuts.
sub has_cap    { @_ = &safe or return; shift->conn->has_cap(@_)    }
sub add_cap    { @_ = &safe or return; shift->conn->add_cap(@_)    }
sub remove_cap { @_ = &safe or return; shift->conn->remove_cap(@_) }

$mod
