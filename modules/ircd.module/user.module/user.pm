# Copyright (c) 2009-16, Mitchell Cooper
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

use utils qw(v notice col conf irc_time cut_to_limit irc_lc);
use List::Util   'first';
use Scalar::Util 'blessed';

our ($api, $mod, $pool, $me);

#########################
### LOW-LEVEL METHODS ###
################################################################################

# create a new user.
sub new {
    my ($class, %opts) = @_;
    return bless {
        modes => [],
        flags => [],
        nick_time => time,
        %opts
    }, $class;
}

#=============#
#=== Modes ===#
#=============#

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
                notice(user_mode_unknown =>
                    ($state ? '+' : '-').$letter,
                    $user->{server}{name}, $user->{server}{sid}
                ) unless $user->{server}{told_missing_umode}{$letter}++;
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

#=============#
#=== Flags ===#
#=============#

# has oper flag.
sub has_flag {
    my ($user, $flag) = @_;
    foreach (@{ $user->{flags} }) {
        return 1 if $_ eq $flag;
        return 1 if $_ eq 'all';
    }
    return;
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

#===============#
#=== Actions ===#
#===============#

# low-level nick change.
sub change_nick {
    my ($user, $newnick, $time) = @_;
    $pool->change_user_nick($user, $newnick) or return;
    notice(user_nick_change => $user->notice_info, $newnick);
    $user->{nick} = $newnick;
    $user->{nick_time} = $time if $time;
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
    return if !defined $user->{away};
    L("$$user{nick} has returned from being away: $$user{away}");
    delete $user->{away};
}

# handle a user quit.
# this does not close a connection; use $user->conn->done() for that.
sub quit {
    my ($user, $reason, $quiet) = @_;
    notice(user_quit =>
        $user->notice_info, $user->{real}, $user->{server}{name}, $reason)
        unless $quiet;

    # send to all users in common channels as well as himself.
    $user->send_to_channels("QUIT :$reason");

    # remove from all channels.
    $_->remove($user) foreach $user->channels;

    $pool->delete_user($user) if $user->{pool};
    $user->delete_all_events();
}

#==================#
#=== Properties ===#
#==================#

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

# hops to another server or user.
sub hops_to {
    my ($server1, $target) = (shift->{server}, shift);
    my $server2 = $target->{server} || $target;
    return $server1->hops_to($server2);
}

sub id            { shift->{uid}    }
sub name          { shift->{nick}   }
sub server        { shift->{server} }

##########################
### HIGH-LEVEL METHODS ###
################################################################################

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

# send a numeric to a local or remote user.
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

# handle incoming data or emulate it.
# these work both locally and remotely.
# see ->handle() and ->handle_with_opts() for local-only versions.
sub handle_unsafe           { _handle_with_opts(1,     @_[0,1]) }
sub handle_with_opts_unsafe { _handle_with_opts(1,     @_)      }

# handle a kill on a local or remote user.
# does NOT propgate.
sub get_killed_by {
    my ($user, $source, $reason) = @_;

    # if the reason is not passed as a ref, add the name.
    if (!ref $reason) {
        my $name = $source->name;
        $reason = \ "$name ($reason)";
    }

    # local user, use ->done().
    if ($user->is_local) {
        $user->{conn}{killed} = 1;
        $user->{conn}->done("Killed ($$reason)");
    }

    # remote user, use ->quit().
    else {
        $user->quit("Killed ($$reason)");
    }

    # TODO: send KILL message to the user
    # charybdis/3c7d6fcce7a021ea7c4948a37a32aeca072e5b10/modules/core/m_kill.c#L237

    notice(user_killed => $user->notice_info, $source->full, $$reason);
    return 1;
}

# handle a ident or cloak change.
#
# sends notifications to local users,
# but any user (local or nonlocal) can be passed.
#
sub get_mask_changed {
    my ($user, $new_ident, $new_host, $set_by) = @_;
    my $old_ident = $user->{ident};
    my $old_host  = $user->{cloak};

    # nothing has changed.
    return if $old_host eq $new_host && $old_ident eq $new_ident;;

    # set the stuff.
    $user->{ident} = $new_ident;
    $user->{cloak} = $new_host;

    # tell the user his host has changed.
    # only do so if welcoming is done because otherwise it's postponed.
    if ($new_host ne $old_host && $user->is_local && $user->{init_complete}) {

        # new host might have a set by
        if ($new_host ne $user->{host}) {
            $user->numeric(
                length $set_by ? 'RPL_HOSTHIDDEN_SVS' : 'RPL_HOSTHIDDEN',
                $new_host,
                $set_by
            );
        }

        # reset to real host
        else {
            $user->numeric(RPL_HOSTHIDDEN_RST => $new_host);
        }
    }

    # send CHGHOST to those who support it.
    my %sent_chghost = %{ $user->send_to_channels(
        "CHGHOST $new_ident $new_host",
        cap     => 'chghost',
        no_self => 1
    ) };

    # don't tell the user that he has quit.
    $sent_chghost{$user}++;

    # for clients not supporting CHGHOST, we have to emulate a reconnect.
    foreach my $channel ($user->channels) {

        # this was explicitly disabled.
        last if !conf('users', 'chghost_quit');

        # determine status mode letters, if any.
        my @levels = $channel->user_get_levels($user); # already sorted
        my $letters = join '',
            map { $ircd::channel_mode_prefixes{$_}[0] } @levels;
        $letters .= join(' ', '', ($user->{nick}) x length $letters);

        # send commands to users we didn't already do above.
        my %sent_quit; # only send QUIT once, but send JOIN/MODE for each chan
        foreach my $usr ($channel->users) {

            # not local user or already sent CHGHOST
            next if !$usr->is_local;
            next if $sent_chghost{$usr};

            # QUIT and JOIN.
            #
            # consider: things like extended-join, away-notify are not dealt
            # with here. we're pretty much assuming that if a client has those
            # capabilities, it should also have chghost...
            #
            $usr->sendfrom($user->full, "QUIT :Changing host")
                unless $sent_quit{$usr};
            $usr->sendfrom($user->full, "JOIN $$channel{name}");

            # MODE for statuses.
            $usr->sendfrom($me->full, "MODE $$channel{name} +$letters")
                if length $letters;

            $sent_quit{$usr}++;
        }
    }

    notice(user_mask_change => $user->{nick},
        $old_ident, $old_host, $new_ident, $new_host);
    return 1;
}

# locally handle a user save.
# despite the name, this works for remote users.
sub save_locally {
    my $user = shift;
    my $uid  = $user->{uid};
    my $old_nick = $user->{nick};

    # notify the user, tell his buddies, and change his nick.
    $user->numeric(RPL_SAVENICK => $uid) if $user->is_local;
    $user->send_to_channels("NICK $uid");
    $user->change_nick($uid, 100);

    notice(user_saved => $user->notice_info, $old_nick);
    return 1;
}

# handles and sets an AWAY locally for both local and remote users.
#
# to unset, $reason should be undef or ''
#
# returns
#   nothing (failed),
#   1 (set away successfully),
#   2 (unset away successfully)
#
sub do_away {
    my ($user, $reason) = @_;

    # setting
    if (length $reason) {

        # truncate it to our local limit.
        my $reason = cut_to_limit('away', $reason);

        # set away, tell the user if he's local.
        $user->set_away($reason);
        $user->numeric('RPL_NOWAWAY') if $user->is_local;

        # let people with away-notify know he's away.
        $user->send_to_channels("AWAY :$reason",
            cap     => 'away-notify',
            no_self => 1
        );

        return 1; # means set
    }

    # unsetting
    return unless length $user->{away};

    # unset away, tell the user if he's local.
    $user->unset_away;
    $user->numeric('RPL_UNAWAY') if $user->is_local;

    # let people with away-notify know he's back.
    $user->send_to_channels('AWAY',
        cap     => 'away-notify',
        no_self => 1
    );

    return 2; # means unset
}

# handles a JOIN 0 or like locally for both local and remote users.
sub do_part_all {
    my $user = shift;
    my @channels = $user->channels;
    $_->do_part($user, undef, 1) foreach @channels;
    notice(user_part_all =>
        $user->notice_info, join(' ', map $_->{name}, @channels));
    return 1;
}

# handles an account login locally for both local and remote users.
sub do_login {
    my ($user, $act_name, $no_num) = @_;
    $user->{account} = { name => $act_name };

    # tell this user
    $user->numeric(RPL_LOGGEDIN => $user->full, $act_name, $act_name)
        if $user->is_local && !$no_num;

    # tell users with account-notify
    $user->send_to_channels("ACCOUNT $act_name",
        cap     => 'account-notify',
        no_self => 1
    );

    notice(user_logged_in => $user->notice_info, $act_name);
    return 1;
}

# handles an account logout locally for both local and remote users.
sub do_logout {
    my ($user, $no_num) = @_;
    my $old = delete $user->{account} or return;

    # tell this user
    $user->numeric(RPL_LOGGEDOUT => $user->full)
        if $user->is_local && !$no_num;

    # tell users with account-notify
    $user->send_to_channels('ACCOUNT *',
        cap     => 'account-notify',
        no_self => 1
    );

    notice(user_logged_out => $user->notice_info, $old->{name});
    return 1;
}

# handle a mode string, send to the local user, send to other servers.
sub do_mode_string { _do_mode_string(undef, undef, @_) }

# same as do_mode_string() except it does not send to other servers.
sub do_mode_string_local { _do_mode_string(1, undef, @_) }

# same as do_mode_string() except it works on remote users.
sub do_mode_string_unsafe { _do_mode_string(undef, 1, @_) }

# $user->send_to_channels($message, %opts)
#
# send to all members of channels in common with a user.
# the source user does not need to be local.
#
# the source user will receive the message as well if he's local,
# regardless of whether he has joined any channels.
#
# returns the hashref of users affected.
#
sub send_to_channels {
    my ($user, $message, %opts) = @_;
    return sendfrom_to_many_with_opts(
        $user->full,
        $message,
        \%opts,
        $user, map { $_->users } $user->channels
    );
}

##########################
### LOCAL-ONLY METHODS ###
################################################################################

# handle incoming data.
sub handle                  { _handle_with_opts(undef, @_[0,1]) }
sub handle_with_opts        { _handle_with_opts(undef, @_)      }

# send data to a local user.
sub send {
    &_safe or return;
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

# handle an invite for a local user.
# $channel might be an object or a channel name.
sub loc_get_invited_by {
    my ($user, $i_user, $ch_name) = @_;
    return unless $user->is_local;

    # the channel exists.
    my $channel = $ch_name if ref $ch_name;
    $channel  ||= $pool->lookup_channel($ch_name);
    if ($channel) {
        $ch_name = $channel->name;

        # user is already in channel.
        return if $channel->has_user($user);

    }

    $user->{invite_pending}{ irc_lc($ch_name) } = 1;
    $user->sendfrom($i_user->full, "INVITE $$user{nick} $ch_name");
}

# CAP shortcuts.
sub has_cap    { &_safe or return; shift->conn->has_cap(@_)    }
sub add_cap    { &_safe or return; shift->conn->add_cap(@_)    }
sub remove_cap { &_safe or return; shift->conn->remove_cap(@_) }

sub conn       { shift->{conn} }

############################
### PROCEDURAL FUNCTIONS ###
################################################################################

# user::sendfrom_to_many($from, $message, @users)
#
# send to a number of users but only once per user.
# returns the hashref of users affected.
#
sub sendfrom_to_many {
    my ($from, $message, @users) = @_;
    return sendfrom_to_many_with_opts(
        $from,
        $message,
        undef,
        @users
    );
}

# user::sendfrom_to_many($from, $message, \%opts, @users)
#
# Extended version of sendfrom_to_many() with additional options:
#
#       ignore          skip a specific user that may be in @users
#       no_self         skip the source user if he's in @users
#       cap             skip users without the specified capability
#       alternative     if 'cap' is provided, this is an alternative message
#
sub sendfrom_to_many_with_opts {
    my ($from, $message, $opts, @users) = @_;
    my %opts = %{ $opts && ref $opts eq 'HASH' ? $opts : {} };

    # consider each provided user
    my %sent_to;
    foreach my $user (@users) {
        my $this_message = $message;

        # not a local user or already sent to
        next if !$user->is_local;
        next if $sent_to{$user};

        # told to ignore this person or not to send to self
        next if defined $opts{ignore} && $user == $opts{ignore};
        next if $opts{no_self} && $user->full eq $from;

        # lacks the required cap. if there's an alternative, use that.
        # otherwise, skip over this person.
        if (defined $opts{cap} && !$user->has_cap($opts{cap})) {
            next unless defined $opts{alternative};
            $this_message = $opts{alternative};
        }

        $user->sendfrom($from, $this_message);
        $sent_to{$user}++;
    }

    return \%sent_to;
}

#########################
### INTERNAL USE ONLY ###
################################################################################

# check for local user
sub _safe {
    my $user = $_[0];
    if (!$user->is_local) {
        my $sub = (caller 1)[3];
        L("Attempted to call ->${sub}() on nonlocal user");
        return;
    }
    return unless $user->conn;
    return @_;
}

# send welcomes
sub _new_connection {
    &_safe or return;
    my $user = shift;
    $user->fire_event('welcoming');

    # set modes.
    # note: we don't use do_mode_string() because we wait until afterward to send MODE.
    $user->handle_mode_string(conf qw/users automodes/);
    $user->set_mode('ssl') if $user->conn->{listener}{ssl};
    $user->fire_event('initially_set_modes');

    # tell other servers
    $pool->fire_command_all(new_user => $user);
    $user->fire_event('initially_propagated');

    # send numerics.
    my $network = conf('server', 'network') // conf('network', 'name');
    $user->numeric(RPL_WELCOME  => $network, $user->{nick}, $user->{ident}, $user->{host});
    $user->numeric(RPL_YOURHOST => $me->{name}, v('TNAME').q(-).v('VERSION'));
    $user->numeric(RPL_CREATED  => irc_time(v('START')));
    $user->numeric(RPL_MYINFO   =>
        $me->{name},
        v('SNAME').q(-).v('NAME').q(-).v('VERSION'),
        $pool->user_mode_string,
        $pool->channel_mode_string
    );
    $user->numeric('RPL_ISUPPORT');
    $user->numeric(RPL_YOURID => $user->{uid})
        if conf('users', 'notify_uid');


    # LUSERS and MOTD
    $user->handle('LUSERS');
    $user->handle('MOTD');

    # send mode string
    $user->sendfrom($user->{nick}, "MODE $$user{nick} :".$user->mode_string);
    $user->numeric(RPL_HOSTHIDDEN => $user->{cloak})
        if $user->{cloak} ne $user->{host};

    return $user->{init_complete} = 1;
}

sub _handle_with_opts {
    my ($allow_nonlocal, $user, $line, %opts) = @_;

    # nonlocal user on ->handle() or some other safe method.
    return if !$allow_nonlocal && !$user->is_local;

    my $msg = blessed $line ? $line : message->new(data => $line);

    # fire commands with options.
    my @events = $user->_events_for_message($msg);
    my $fire = $user->prepare(@events)->fire('safe', data => \%opts);

    # 'safe' with exception.
    if (my $e = $fire->exception) {
        my $stopper = $fire->stopper;
        my $cmd = $msg->command;
        notice(exception => "Error in ->handle($cmd) from $stopper: $e");
        return;
    }

    return $msg;
}

# returns the events for an incoming message.
sub _events_for_message {
    my ($user, $msg) = @_;
    my $cmd = $msg->command;
    return (
        [ $user,  message       => $msg ],
        [ $user, "message_$cmd" => $msg ]
    );
}

# handle mode string, notify user if local, tell other servers.
#
# $no_prop = do not propagate the mode change
# $unsafe  = propagate even if the user is remote
#
sub _do_mode_string {
    my ($no_prop, $unsafe, $user, $modestr, $force) = @_;

    # handle it, regardless if local or remote.
    my $result = $user->handle_mode_string($modestr, $force) or return;

    return if !$user->is_local && !$unsafe;                 # remote not allowed
    return if $user->is_local  && !$user->{init_complete};  # local user not done registering

    # tell the user himself..
    $user->sendfrom($user->{nick}, "MODE $$user{nick} :$result")
        if $user->is_local && length $result > 1;

    # tell other servers.
    $pool->fire_command_all(umode => $user, $result)
        unless $no_prop;

}

$mod
