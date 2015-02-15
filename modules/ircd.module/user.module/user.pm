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
use List::Util   'first';
use Scalar::Util 'blessed';

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
    my ($user, $newnick, $time) = @_;
    $pool->change_user_nick($user, $newnick) or return;
    notice(user_nick_change => $user->notice_info, $newnick);
    $user->{nick} = $newnick;
    $user->{nick_time} = $time if $time;
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
    # FIXME: PLEASE!
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
    my $user   = shift;
    my $server = shift || $user->{server};
    return '+'.join('', sort map {
        $server->umode_letter($_) // ''
    } @{ $user->{modes} });
}

# add oper flags.
sub add_flags {
    my $user  = shift;
    my %has   = map  { $_ => 1   } @{ $user->{flags} };
    my @flags = grep { !$has{$_} } @_;
    return unless scalar @flags;
    L("adding flags to $$user{nick}: @flags");
    notice(user_opered => $user->notice_info, $user->{server}{name}, "@flags");
    push @{ $user->{flags} }, @flags;
    return @flags;
}

# remove oper flags.
sub remove_flags {
    my $user   = shift;
    my %remove = map { $_ => 1 } @_;
    L("removing flags from $$user{nick}: @{[ keys %remove ]}");
    my (@new, @removed);
    foreach my $flag (@{ $user->{flags} }) {
        if ($remove{$flag}) {
            push @removed, $flag;
            next;
        }
        push @new, $flag;
    }
    $user->{flags} = \@new;
    return @removed;
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

# hops to another user.
sub hops_to {
    my ($server1, $target) = (shift->{server}, shift);
    my $server2 = $target->{server} || $target;
    return $server1->hops_to($server2);
}

sub DESTROY {
    my $user = shift;
    L("$user destroyed");
}

sub id            { shift->{uid}  }
sub name          { shift->{nick} }
sub conn          { shift->{conn} }
sub account       { my $act = shift->{account}; blessed $act ? $act : undef }

############
### MINE ###
############

# check for local user
sub safe {
    my $user = $_[0];
    if (!$user->is_local) {
        my $sub = (caller 1)[3];
        L("Attempted to call ->${sub}() on nonlocal user");
        return;
    }
    return unless $user->conn;
    return @_;
}

# handle incoming data.
sub handle        { _handle_with_opts(undef, @_[0,1]) }
sub handle_unsafe { _handle_with_opts(1,     @_[0,1]) }

# returns the events for an incoming message.
sub events_for_message {
    my ($user, $msg) = @_;
    my $cmd = $msg->command;
    return (
        [ $user,  message       => $msg ],
        [ $user, "message_$cmd" => $msg ]
    );
}

# handle data (new method) with options.
sub  handle_with_opts        { _handle_with_opts(undef, @_) }
sub _handle_with_opts_unsafe { _handle_with_opts(1,     @_) }
sub _handle_with_opts        {
    my ($allow_nonlocal, $user, $line, %opts) = @_;
    
    # nonlocal user on ->handle() or some other safe method.
    return if !$allow_nonlocal && !$user->is_local;
    
    my $msg = blessed $line ? $line : message->new(data => $line);
    
    # fire commands with options.
    my @events = $user->events_for_message($msg);
    $user->prepare(@events)->fire('safe', data => \%opts);
    
}

# send data to a local user.
sub send {
    &safe or return;
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
    
    # first parameter can be a server
    my $server = $me;
    if (blessed $args[0] && $args[0]->isa('server')) {
        $server = shift @args;
    }
    
    my $cmd = ucfirst $args[0];
    my $msg = defined $args[1] ? "*** \2$cmd:\2 $args[1]" : $args[0];
    
    # user is local.
    if ($user->is_local) {
        $user->sendfrom($server->name, "NOTICE $$user{nick} :$msg");
        return 1;
    }
    
    # not local; pass it on.
    $user->{location}->fire_command(privmsgnotice => 'NOTICE', $server, $user, $msg);
    
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
    &safe or return;
    my $user = shift;

    # set modes.
    # note: we don't use do_mode_string() because we wait until afterward to send MODE.
    $user->handle_mode_string(conf qw/users automodes/);
    $user->set_mode('ssl') if $user->conn->{listener}{ssl};
    
    # tell other servers
    $pool->fire_command_all(new_user => $user);
    $user->fire_event('initially_propagated');
    
    # send numerics.
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
    return if !$user->is_local || !$user->{init_complete};
    
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
sub has_cap    { &safe or return; shift->conn->has_cap(@_)    }
sub add_cap    { &safe or return; shift->conn->add_cap(@_)    }
sub remove_cap { &safe or return; shift->conn->remove_cap(@_) }

$mod
