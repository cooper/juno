# Copyright (c) 2009-16, Mitchell Cooper
#
# @name:            "ircd::channel"
# @package:         "channel"
# @description:     "represents an IRC channel"
# @version:         ircd->VERSION
# @no_bless:        1
# @preserve_sym:    1
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package channel;

use warnings;
use strict;
use 5.010;
use parent 'Evented::Object';

use modes;
use utils qw(conf v notice match ref_to_list cut_to_length irc_lc);
use List::Util qw(first max);
use Scalar::Util qw(blessed looks_like_number);

our ($api, $mod, $pool, $me);

our $LEVEL_SPEAK_MOD    = -2;   # level needed to speak when moderated or banned
our $LEVEL_SIMPLE_MODES = -1;   # level needed to set simple modes

#   === Channel mode types ===
#
#   type            n   description                                 e.g.
#   ----            -   -----------                                 ----
#
#   normal          0   never has a parameter                       +m
#
#   parameter       1   requires parameter when set and unset       n/a
#
#   parameter_set   2   requires parameter only when set            +l
#
#   list            3   list-type mode                              +b
#
#   status          4   status-type mode                            +o
#
#   key             5   like type 1 but visible only to members     +k
#                       and consumes parameter when unsetting
#                       only if present (keys are very particular!)
#

# create a channel.
sub new {
    my ($class, %opts) = @_;
    return bless {
        users => [],
        modes => {},
        %opts
    }, $class;
}

# channel mode is set.
sub is_mode {
    my ($channel, $name) = @_;
    return $channel->{modes}{$name};
}

# current parameter for a set mode, if any.
sub mode_parameter {
    my ($channel, $name) = @_;
    return $channel->{modes}{$name}{parameter};
}

# low-level mode set.
# takes an optional parameter.
# $channel->set_mode('moderated');
sub set_mode {
    my ($channel, $name, $parameter) = @_;
    $channel->{modes}{$name} = {
        parameter => $parameter,
        time      => time
        # list for list modes and status
    };
    L("$$channel{name} +$name");
    return 1
}

# low-level mode unset.
sub unset_mode {
    my ($channel, $name) = @_;
    return unless $channel->is_mode($name);
    delete $channel->{modes}{$name};
    L("$$channel{name} -$name");
    return 1;
}

# list has something.
sub list_has {
    my ($channel, $name, $what) = @_;
    return unless $channel->{modes}{$name};
    return 1 if defined first { $_ eq $what } $channel->list_elements($name);
}

# something matches in an expression list.
# returns the match if there is one.
sub list_matches {
    my ($channel, $name, $what) = @_;
    return unless $channel->{modes}{$name};
    return first { match($what, $_) } $channel->list_elements($name);
}

# returns an array of list elements.
sub list_elements {
    my ($channel, $name, $all) = @_;
    return unless $channel->{modes}{$name};
    my @list = ref_to_list($channel->{modes}{$name}{list});
    if ($all)  { return @list }
    return map { $_->[0]      } @list;
}

# adds something to a list mode.
sub add_to_list {
    my ($channel, $name, $parameter, %opts) = @_;

    # first item. wow.
    $channel->{modes}{$name} = {
        time => time,
        list => []
    } unless $channel->{modes}{$name};

    # no duplicates plz.
    return if $channel->list_has($name, $parameter);

    # add it.
    L("$$channel{name}: adding $parameter to $name list");
    my $array = [$parameter, \%opts];
    push @{ $channel->{modes}{$name}{list} }, $array;

    return 1;
}

# removes something from a list.
sub remove_from_list {
    my ($channel, $name, $what) = @_;
    return unless $channel->list_has($name, $what);

    my @new = grep {
        $_->[0] ne $what
    } ref_to_list($channel->{modes}{$name}{list});
    $channel->{modes}{$name}{list} = \@new;

    L("$$channel{name}: removing $what from $name list");
    return 1;
}

# user joins channel
sub add {
    my ($channel, $user) = @_;
    return if $channel->has_user($user);

    # add the user to the channel.
    push @{ $channel->{users} }, $user;

    # note: as of 5.91, after-join (user_joined) event is fired in
    # mine.pm:           for locals
    # core_scommands.pm: for nonlocals.

    notice(channel_join => $user->notice_info, $channel->name)
        unless $user->{location}{is_burst};
    return $channel->{time};
}

# remove a user.
# this could be due to any of part, quit, kick, server quit, etc.
sub remove {
    my ($channel, $user) = @_;

    # remove the user from status lists
    foreach my $name (keys %{ $channel->{modes} }) {
        $channel->remove_from_list($name, $user)
            if $me->cmode_type($name) == MODE_STATUS;
    }

    # remove the user.
    my @new = grep { $_ != $user } $channel->users;
    $channel->{users} = \@new;

    # delete the channel if this is the last user.
    $channel->destroy_maybe();

    return 1;
}

# user is on channel.
sub has_user {
    my ($channel, $user) = @_;
    return first { $_ == $user } $channel->users;
}

# low-level channel time set.
sub set_time {
    my ($channel, $time) = @_;
    L("warning: setting time to a lower time from $$channel{time} to $time")
        if $time > $channel->{time};
    $channel->{time} = $time;
}

# ->handle_modes()
#
# handles named modes at a low level.
#
# you may want to use ->do_modes() or ->do_mode_string() instead,
# as these are high-level methods which also notify local clients and uplinks.
#
# See issues #77 and #101 for background information.
#
sub handle_modes {
    my ($channel, $source, $modes, $force, $unloaded) = @_;
    my ($param_length, $ban_length);
    my $changes = modes->new;

    # apply each mode.
    MODE: foreach ($modes->stated) {
        my ($state, $name, $param) = @$_;

        # find the mode type.
        my $type = $me->cmode_type($name);
        if ($type == MODE_UNKNOWN) {
            L("Mode '$name' is not known to this server; skipped");
            next MODE;
        }

        # if the mode requires a parameter but one was not provided,
        # we have no choice but to skip this.
        #
        # these are returned by ->cmode_takes_parameter: NOT mode types
        #     1 = always takes param
        #     2 = takes param, but valid if there isn't,
        #         such as list modes like +b for viewing
        #
        my $takes = $me->cmode_takes_parameter($name, $state) || 0;
        if (!defined $param && $takes == 1) {
            L("Mode '$name' is missing a parameter; skipped");
            next MODE;
        }

        # parameters have to have length and can't start with colons.
        if (defined $param && (!length $param || substr($param, 0, 1) eq ':')) {
            L("Mode '$name' has malformed parameter '$param'; skipped");
            next MODE;
        }

        # status mode parameters must be user objects at this point.
        if ($type == MODE_STATUS and !blessed $param || !$param->isa('user')) {
            $source->numeric(ERR_NOSUCHNICK => $param)
                if $source->isa('user') && $source->is_local;
            next MODE;
        }

        # truncate the parameter, if necessary.
        #
        # consider: truncating bans might be a bad idea; it could have weird
        # results if the ban length limit is inconsistent across servers...
        # charybdis seems to send ERR_INVALIDBAN instead.
        #
        if (defined $param) {
            $param_length ||= conf('channels', 'max_param_length');
            $ban_length   ||= conf('channels', 'max_ban_length');
            $param = cut_to_length(
                $type == MODE_LIST ? $ban_length : $param_length,
                $param
            );
        }

        # don't allow this mode to be changed if the test fails
        # *unless* force is provided.
        my $fire_method = $unloaded ?
            'fire_unloaded_channel_mode' : 'fire_channel_mode';
        my ($win, $mode) = $pool->$fire_method($channel, $name, {
            channel => $channel,        # the channel
            server  => $me,             # the server perspective
            source  => $source,         # the source of the mode change
            state   => $state,          # setting or unsetting
            name    => $name,           # the mode name
            param   => $param,          # the parameter for this particular mode
            force   => $force,          # true if permissions should be ignored
            # source can set simple modes.
            has_basic_status => $force || $source->isa('server') ? 1
                                : $channel->user_has_basic_status($source)
        });

        # Determining whether to send ERR_CHANOPRIVSNEEDED
        #
        # Source is a local user?
        #   No..................................... DO NOT SEND
        #   Yes. Mode block set send_no_privs?
        #       Yes................................ SEND
        #       No. Mode block returned true?
        #           Yes............................ DO NOT SEND
        #           No. User has +h or higher?
        #               Yes........................ DO NOT SEND
        #               No. Mode block set hide_no_privs?
        #                   Yes.................... DO NOT SEND
        #                   No..................... SEND
        #
        if ($source->isa('user') && $source->is_local) {
            my $no_status = !$win && !$mode->{has_basic_status}
                && !$mode->{hide_no_privs};
            my $yes = $mode->{send_no_privs} || $no_status;
            $source->numeric(ERR_CHANOPRIVSNEEDED => $channel->name) if $yes;
        }

        # block returned false; cancel the change.
        next MODE if !$win;

        # if this mode requires a parameter but none is present at this point,
        # this means a mode block set the {param} to undef. we cannot continue.
        #
        # this also catches banlike modes when viewing the list.
        # they require a parameter when setting or unsetting, so even though
        # $win is true when viewing the list, this will prevent the mode from
        # appearing in the resultant.
        #
        $param = $mode->{param};
        next MODE if !defined $param && $takes;

        # SAFE POINT:
        # from here we can assume that the mode will be set or unset.
        # it has passed all the tests and will certainly be applied.

        # it is a "normal" type mode.
        if ($type == MODE_NORMAL) {
            my $do = $state ? 'set_mode' : 'unset_mode';
            $channel->$do($name);
        }

        # it is a mode with a simple parameter.
        # does not include lists, status modes, or key.
        elsif ($type == MODE_PARAM || $type == MODE_PSET) {
            $channel->set_mode($name, $param)   if  $state;
            $channel->unset_mode($name)         if !$state;
        }

        # add it to the list of changes.
        $changes->push_stated_mode($state, $name => $param);

    }

    return $changes;
}

# ->handle_mode_string()
#
# handles a mode string at a low level.
#
# this is a low-level function that only sets the modes.
# you probably want to use ->do_mode_string(), which sends to users and servers.
#
sub handle_mode_string {
    my ($channel, $server, $source, $mode_str, $force, $over_protocol) = @_;

    # extract the modes.
    my $changes = modes->new_from_string($server, $mode_str, $over_protocol);

    # handle the modes.
    return $channel->handle_modes($source, $changes, $force);

}

# return a moderef for all modes.
sub all_modes {
    my $channel = shift;
    return $channel->modes_with('inf');
}

# return a moderef from the provided mode names.
sub modes_with  { _modes_with($me, @_) }
sub _modes_with {
    my ($server, $channel, @mode_names) = @_;
    my @all_modes = keys %{ $channel->{modes} };
    my $modes = modes->new;

    # replace numbers with mode names.
    @mode_names = map {
        my $matcher = modes::_get_matcher($_);
        grep $matcher->($_), @all_modes;
    } @mode_names;

    # add each mode by name.
    foreach my $name (@mode_names) {
        my $type = $me->cmode_type($name);
        my $ref  = $channel->{modes}{$name} or next;
        next if $type == MODE_UNKNOWN;

        # list/status modes. add each string or user object.
        if ($ref->{list}) {
            $modes->push_mode($name => $_)
                for $channel->list_elements($name);
            next;
        }

        # otherwise it has either zero or one parameters.
        # either the value of the parameter or undef will be pushed.
        $modes->push_mode($name => $ref->{parameter});

    }

    return $modes;
}

# return a mode string in the perspective of $server with the
# provided mode names.
sub mode_string_with {
    my ($channel, $server, @mode_names) = @_;
    my $modes = _modes_with($server, $channel, @mode_names);

    # ($over_protocol, $organize, $skip_checks)
    my $user_string   = $modes->to_string($server, 0, 1, 1);
    my $server_string = $modes->to_string($server, 1, 1, 1);

    return ($user_string, $server_string);
}

# returns a +modes string.
sub mode_string {
    my ($channel, $server) = @_;
    # acceptable types are 0 (normal), 1 (parameter), 2 (parameter_set),
    # and possibly 5 (hidden), if showing hidden.
    return $channel->mode_string_with($server, 0, 1, 2);
}

# includes ALL modes, even +k
#
# returns a string for users and a string for servers
# $no_status = all but status modes
#
# returns both a user string and a server string.
#
sub mode_string_all {
    my ($channel, $server, $no_status) = @_;
    return $channel->mode_string_with($server, $no_status ? -inf : 'inf');
}

# returns true only if the passed user is in
# the passed status list.
sub user_is {
    my ($channel, $user, $what) = @_;
    $what = _get_status_mode($channel, $what);
    return 1 if $channel->list_has($what, $user);
    return;
}

# check if a user has at least a certain level
sub user_is_at_least {
    my ($channel, $user, $level) = @_;
    $level = _get_level($channel, $level);
    return $channel->user_get_highest_level($user) >= $level;
}

# returns true value only if the passed user has status
# greater than voice (halfop, op, admin, owner)
sub user_has_basic_status {
    my ($channel, $user) = @_;
    return $channel->user_get_highest_level($user) >= $LEVEL_SIMPLE_MODES;
}

# get the highest level of a user
# returns -inf if they have no status
# [letter, symbol, name]
sub user_get_highest_level {
    my ($channel, $user) = @_;
    return -inf if !$channel->has_user($user);
    return ($channel->user_get_levels($user))[0] // -inf;
}

# get all the levels of a user
sub user_get_levels {
    my ($channel, $user) = @_;
    return if !$channel->has_user($user);
    my @levels;
    foreach my $level (sort { $b <=> $a } keys %ircd::channel_mode_prefixes) {
        my ($letter, $symbol, $name) =
            ref_to_list($ircd::channel_mode_prefixes{$level});
        push @levels, $level if $channel->list_has($name, $user);
    }
    return @levels;
}

# possibly convert a mode name to a level
sub _get_level {
    my ($channel, $level) = @_;
    return unless defined $level;

    # if it's not an num, convert mode name to level.
    if (!looks_like_number($level)) {
        my $found;
        foreach my $lvl (keys %ircd::channel_mode_prefixes) {
            my $name = $ircd::channel_mode_prefixes{$lvl}[2];
            next if $level ne $name;
            $level = $lvl;
            $found++;
            last;
        }
        return unless $found;
    }

    return $level;
}

# possibily convert a level to a mode name
sub _get_status_mode {
    my ($channel, $what) = @_;
    return unless defined $what;

    # if it's an num, check if they have that level specifically.
    if (looks_like_number($what)) {
        $what = $ircd::channel_mode_prefixes{$what}[2]; # name
    }

    return $what;
}

# fetch the topic or return undef if none.
sub topic {
    my $channel = shift;
    return $channel->{topic} if
      defined $channel->{topic}{topic} &&
      length $channel->{topic}{topic};
    delete $channel->{topic};
    return;
}

# destroy the channel maybe
sub destroy_maybe {
    my $channel = shift;

    # there are still users in here!
    return if $channel->users;

    # an event said not to destroy the channel.
    return if $channel->fire('can_destroy')->stopper;

    # delete the channel from the pool, purge events
    $pool->delete_channel($channel);
    $channel->delete_all_events();

    return 1;
}

# return users that satisfy a code
sub users_satisfying {
    my ($channel, $code) = @_;
    ref $code eq 'CODE' or return;
    return grep $code->($_), $channel->users;
}

# return users with a certain level or higher
sub users_with_at_least {
    my ($channel, $level) = @_;
    $level = _get_level($channel, $level);
    return $channel->users_satisfying(sub {
        $channel->user_get_highest_level(shift) >= $level;
    });
}

# returns users which belong to this server
sub all_local_users {
    my $channel = shift;
    return $channel->users_satisfying(sub { shift->is_local });
}

# returns real users which belong to this server
sub real_local_users {
    my $channel = shift;
    return $channel->users_satisfying(sub { shift->is_local && !$_->{fake} });
}

sub id    { shift->{name}       }
sub name  { shift->{name}       }
sub users { @{ shift->{users} } }

############
### MINE ###
############

# send NAMES.
sub send_names {
    my ($channel, $user, $no_endof) = @_;
    $user->is_local or return;

    my $in_channel = $channel->has_user($user);
    my $prefixes   = $user->has_cap('multi-prefix') ? 'prefixes' : 'prefix';

    my @str;
    my $curr = 0;
    foreach my $a_user ($channel->users) {

        # some extension said not to show this user.
        # the first user is the one being considered;
        # the second is the one which initiated the NAMES.
        next if $channel->fire(show_in_names => $a_user, $user)->stopper;

        # if this user is invisible, do not show him unless the querier is in a
        # common channel or has the see_invisible flag.
        if ($a_user->is_mode('invisible')) {
            next if !$in_channel && !$user->has_flag('see_invisible');
        }

        # add him.
        $str[$curr] .= $channel->$prefixes($a_user).$a_user->{nick}.q( );

        # if the current string is over 500 chars, start a new one.
        $curr++ if length $str[$curr] > 500;

    }

    # fire an event which allows modules to change the character.
    my $c = '=';
    $channel->fire(names_character => \$c);

    # send out the NAMREPLYs, if any. if no users matched, none will be sent.
    # then, send out ENDOFNAMES unless told not to by the caller.
    $user->numeric(RPL_NAMREPLY   => $c, $channel->name, $_) foreach @str;
    $user->numeric(RPL_ENDOFNAMES =>     $channel->name    ) unless $no_endof;

}

# send mode information.
sub send_modes {
    my ($channel, $user) = @_;

    # create a mode string with all modes except status and list modes.
    # remove parameters if the user is not in the channel.
    my $mode_str = $channel->all_modes
        ->remove(MODE_LIST, MODE_STATUS)->to_string($me);
    $mode_str = (split ' ', $mode_str, 2)[0]
        unless $channel->has_user($user);

    $user->numeric(RPL_CHANNELMODEIS =>  $channel->name, $mode_str);
    $user->numeric(RPL_CREATIONTIME  =>  $channel->name, $channel->{time});
}

# send a message to all the local members.
sub send_all {
    my ($channel, $what, $ignore) = @_;

    # $ignore can be either a user object or a codref
    # which returns true when the user should be ignored
    if ($ignore && !ref $ignore) {
        my $ignore_user = $ignore;
        $ignore = sub { shift() == $ignore_user };
    }

    foreach my $user ($channel->users) {

        # not local or ignored
        next unless $user->is_local;
        next if $ignore && $ignore->($user);

        $user->send($what);
    }
    return 1;
}

# send to members with a source.
sub sendfrom_all {
    my ($channel, $who, $what, $ignore) = @_;
    return send_all($channel, ":$who $what", $ignore);
}

# send to members with a capability.
# $alternative = send this if the user doesn't have the cap
sub sendfrom_all_cap {
    my ($channel, $who, $what, $alternative, $ignore, $cap) = @_;
    foreach my $user ($channel->users) {

        # not local or ignored
        next unless $user->is_local;
        next if $ignore && $ignore == $user;

        # sorry, don't have it
        if (!$user->has_cap($cap)) {
            $user->sendfrom($who, $alternative) if length $alternative;
            next;
        }

        $user->sendfrom($who, $what);
    }
    return 1;
}

# send a notice from the server to all members.
sub notice_all {
    my ($channel, $what, $ignore, $local, $no_stars) = @_;
    $what = "*** $what" unless $no_stars;
    my %opts = (dont_forward => $local, force => 1);
    $channel->do_privmsgnotice(NOTICE => $me, $what, %opts);
    return 1;
}

# take the lower time of a channel and unset higher time stuff.
sub take_lower_time {
    my ($channel, $time, $ignore_modes) = @_;

    # the current time is older; keep it.
    return $channel->{time} if $time >= $channel->{time};

    # the new time is older; reset.
    L("locally resetting $$channel{name} time to $time");
    $channel->set_time($time);

    # unset all channel modes.
    unless ($ignore_modes) {
        # ($source, $modes, $force, $organize)
        $channel->do_modes_local($me, $channel->all_modes->invert, 1, 1);
    }

    # tell local users.
    # ($notice, $ignore, $local)
    $channel->notice_all("New channel time: ".scalar(localtime $time), 0, 1);
    return $channel->{time};
}

# returns the highest prefix a user has.
sub prefix {
    my ($channel, $user) = @_;
    my $level = $channel->user_get_highest_level($user);
    if (defined $level && $ircd::channel_mode_prefixes{$level}) {
        return $ircd::channel_mode_prefixes{$level}[1];
    }
    return q..;
}

# returns list of all prefixes a user has, greatest to smallest.
sub prefixes {
    my ($channel, $user) = @_;
    my $prefixes = '';
    foreach my $level (sort { $b <=> $a } keys %ircd::channel_mode_prefixes) {
        my ($letter, $symbol, $name) =
            ref_to_list($ircd::channel_mode_prefixes{$level});
        $prefixes .= $symbol if $channel->list_has($name, $user);
    }
    return $prefixes;
}

# true if the user has an invite outstanding
sub user_has_invite {
    my ($channel, $user) = @_;
    return 1 if $channel->{invite_pending}{ $user->id };
    return;
}

# clear the outstanding invite for a user
sub user_clear_invite {
    my ($channel, $user) = @_;
    delete $channel->{invite_pending}{ $user->id };
    delete $user->{invite_pending}{ irc_lc($channel->name) };
}

# handle named modes, tell our local users, and tell other servers.
sub do_modes { _do_modes(undef, @_) }

# same as ->do_modes() except it never sends to other servers.
sub do_modes_local { _do_modes(1, @_) }

# ->do_modes() and ->do_modes_local()
#
# See issue #101 for the planning of these methods.
#
#   $source             the source of the mode change
#   $modes              named modes in an arrayref as described in issue #101
#   $force              whether to ignore permissions
#   $organize           whether to alphabetize and put positive changes first
#   $unloaded           true if the modes were recently unloaded
#
sub _do_modes {
    my $local = shift;
    my ($channel, $source, $modes, $force, $organize, $unloaded) = @_;
    $modes->count or return;

    # handle the mode.
    my $changes = $channel->handle_modes($source, $modes, $force, $unloaded);

    # if nothing changed, stop here.
    $changes && $changes->count or return;

    # tell the channel's users. this might be sent as multiple messages.
    #
    # ($over_protocol, $organize, $skip_checks)
    # $over_protocol is false here because we want nicks rather than UIDs.
    #
    foreach ($changes->to_strings($me, 0, $organize, 1)) {
        next unless length;
        $channel->sendfrom_all($source->full, "MODE $$channel{name} $_");
    }

    # stop here if it's not a local user or this server.
    return $changes if $local || !$source->is_local;

    # the source is our user or this server, so tell other servers.
    #
    # ($over_protocol, $organize, $skip_checks)
    # $over_protocol is true here because we want UIDs rather than nicks.
    # currently each protocol implementation has to split it when necessary.
    #
    # cmode => ($source, $channel, $time, $perspective, $mode_str)
    #
    my $mode_str = $changes->to_string($me, 1, $organize, 1);
    $pool->fire_command_all(cmode =>
        $source, $channel, $channel->{time},
        $me, $mode_str
    ) if length $mode_str;

    return $changes;
}

# handle a mode string, tell our local users, and tell other servers.
sub do_mode_string { _do_mode_string(undef, @_) }

# same as ->do_mode_string() except it never sends to other servers.
sub do_mode_string_local { _do_mode_string(1, @_) }

sub _do_mode_string {
    my ($local, $channel, $server, $source,
        $mode_str, $force, $over_protocol) = @_;

    # extract the modes.
    my $changes = modes->new_from_string($server, $mode_str, $over_protocol);

    # do the modes.
    return _do_modes($local,
        $channel, $source, $changes, $force, $over_protocol);
}

# ->do_privmsgnotice()
#
# Handles a PRIVMSG or NOTICE. Notifies local users and uplinks when necessary.
#
# $command  one of 'privmsg' or 'notice'.
#
# $source   user or server object which is the source of the method.
#
# $message  the message text as it was received.
#
# %opts     a hash of options:
#
#       force           if specified, the can_privmsg, can_notice, and
#                       can_message events will not be fired. this means that
#                       any modules that prevent the message from being sent OR
#                       that modify the message will NOT have an effect on this
#                       message. used when receiving remote messages.
#
#       dont_forward    if specified, the message will NOT be forwarded to other
#                       servers by this method. this is used in protocol modules
#                       in conjunction with $msg->forward*() methods.
#
#       users           if specified, this list of users will be used as the
#                       destinations. they can be local, remote, or a mixture of
#                       both. when omitted, all non-deaf users of the channel
#                       will receive the message. any deaf user, whether local
#                       or remote and whether in @users or not, will NEVER
#                       receive a message.
#
#       op_moderated    if true, this message was blocked but will be
#                       sent to ops in a +z channel.
#
#       serv_mask       if provided, the message is to be sent to all
#                               users which belong to servers matching the mask.
#
#       atserv_nick     if provided, this is the nickname for a target@server
#                       message. if it is present, atserv_serv must also exist.
#
#       atserv_serv     if provided, this is the server OBJECT for a
#                       target@server message. if it is present, atserv_nick
#                       must also exist.
#
#       min_level       a status level which this message is directed to. the
#                       message will be sent to users with the prefix; e.g.
#                       @#channel or +#channel.
#
sub do_privmsgnotice {
    my ($channel, $command, $source, $message, %opts) = @_;
    my ($source_user, $source_serv) = ($source->user, $source->server);
    undef $source_serv if $source_user;
    $command   = uc $command;
    my $lc_cmd = lc $command;

    # find the destinations
    my @users;
    if ($opts{users}) {                             # explicitly specified
        @users = ref_to_list($opts{users});
    }
    elsif ($opts{op_moderated}) {                   # op moderated = all ops
        @users = $channel->users_with_at_least(0);
    }
    elsif (defined $opts{min_level}) {              # @#channel or similar
        @users = $channel->users_with_at_least($opts{min_level});
    }
    else {                                          # fall back to all users
        @users = $channel->users;
    }

    # nowhere to send it!
    return if !@users;

    # it's a user. fire the can_* events.
    if ($source_user && !$opts{force}) {

        # the can_* events may modify the message, so we pass a
        # scalar reference to it.

        # can_message, can_notice, can_privmsg,
        # can_message_channel, can_notice_channel, can_privmsg_channel
        my @args = ($channel, \$message, $lc_cmd);
        my $can_fire = $source_user->fire_events_together(
            [  can_message            => @args ],
            [  can_message_channel    => @args ],
            [ "can_${lc_cmd}"         => @args ],
            [ "can_${lc_cmd}_channel" => @args ]
        );

        # the can_* events may stop the event, preventing the message from
        # being sent to users or servers.
        if ($can_fire->stopper) {

            # if the message was blocked, fire cant_* events.
            my @args = ($channel, $message, $can_fire, $lc_cmd);
            my $cant_fire = $source_user->fire_events_together(
                [  cant_message            => @args ],
                [  cant_message_channel    => @args ],
                [ "cant_${lc_cmd}"         => @args ],
                [ "cant_${lc_cmd}_channel" => @args ]
            );

            # the cant_* events may be stopped. if this happens, the error
            # messages as to why the message was blocked will NOT be sent.
            my @error_reply = ref_to_list($can_fire->{error_reply});
            if (!$cant_fire->stopper && @error_reply) {
                $source_user->numeric(@error_reply);
            }

            # the can_* event was stopped, so don't continue.
            return;
        }
    }

    # send to @#channel if necessary
    my $local_prefix = "$command $$channel{name} :";
    if (defined $opts{min_level}) {
        my $prefix = $ircd::channel_mode_prefixes{ $opts{min_level} } or return;
        $prefix = $prefix->[1]; # [ letter, prefix, ... ]
        $local_prefix = "$command $prefix$$channel{name} :";
    }

    # tell channel members.
    my %sent;
    USER: foreach my $user (@users) {

        # this is the source!
        next USER if $source_user && $source_user == $user;

        # not telling remotes.
        next USER if !$user->is_local && $opts{dont_forward};

        # deaf users don't care.
        # if a server has all-deaf users, it will never receive the message.
        next USER if $user->is_mode('deaf');

        # the user is local.
        if ($user->is_local) {

            # the can_receive_* events may modify the message as it appears to
            # the target user, so we pass a scalar reference to a copy of it.
            my $my_message = $message;

            # fire can_receive_* events.
            my @args = ($user, \$my_message, $lc_cmd);
            my $recv_fire = $user->fire_events_together(
                [  can_receive_message            => @args ],
                [  can_receive_message_channel    => @args ],
                [ "can_receive_${lc_cmd}"         => @args ],
                [ "can_receive_${lc_cmd}_channel" => @args ]
            );

            # the can_receive_* events may stop the event, preventing the user
            # from ever seeing the message.
            $user->sendfrom($source->full, $local_prefix.$my_message)
                unless $recv_fire->stopper;

            next USER;
        }

        # Safe point - the user is remote.
        my $location = $user->{location};

        # the source user is reached through this user's server,
        # or the source is the server we know the user from.
        next USER if $source_user && $location == $source_user->{location};
        next USER if $source_serv && $location->{sid} == $source_serv->{sid};

        # already sent to this server.
        next USER if $sent{$location};

        $location->fire_command(privmsgnotice =>
            $command, $source, $channel, $message, %opts
        );
        $sent{$location}++;
    }

    # fire privmsg or notice event.
    $channel->fire($lc_cmd => $source, $message);

    return 1;
}

# ->do_join()
# see issue #76 for background information
#
# 1. joins a user to the channel with ->add().
# 2. sends JOIN message to local users in common channels.
# 3. fires the user_joined event.
#
# note that this method is permitted for both local and remote users.
# it DOES NOT send join messages to servers; it is up to the server
# protocol implementation to do so with ->forward().
#
# $allow_already = do not consider whether the user is already in the channel.
# this is useful for local channel creation.
#
sub do_join {
    my ($channel, $user, $allow_already) = @_;
    my $already = $channel->has_user($user);

    # add the user.
    return if $already && !$allow_already;
    $channel->add($user) unless $already;

    # remove pending invites.
    $channel->user_clear_invite($user);

    # for each user in the channel, send a JOIN message.
    my $act_name = $user->{account} ? $user->{account}{name} : '*';
    $channel->sendfrom_all_cap(
        $user->full,
        "JOIN $$channel{name} $act_name :$$user{real}",     # IRCv3.1
        "JOIN $$channel{name}",                             # RFC1459
        undef,
        'extended-join'
    );

    # tell the users who care whether this person is away.
    $channel->sendfrom_all_cap(
        $user->full,
        "AWAY :$$user{away}",   # IRCv3.1
        undef,                  # no alternative
        $user,                  # don't send to the user himself
        'away-notify'
    ) if $user->{away};

    # if local, send topic and names.
    if ($user->is_local) {
        $user->handle("TOPIC $$channel{name}") if $channel->topic;
        $channel->send_names($user);
    }

    # fire after join event.
    $channel->fire(user_joined => $user);

}

# ->attempt_local_join()
# see issue #76 for background information
#
# this is essentially a JOIN command handler - it checks that a local user can
# join a channel, deals with channel creation, set automodes, and more.
#
# this method CANNOT be used on remote users. note that this method MAY
# send out join and/or channel burst messages to servers.
#
# $new      = whether it's a new channel; this will deal with automodes
# $key      = provided channel key, if any. does nothing when $force
# $force    = do not check if the user is actually allowed to join
#
sub attempt_local_join {
    my ($channel, $user, $new, $key, $force) = @_;

    # the user is not local or is already on the channel.
    return if !$user->is_local || $channel->has_user($user);

    # if we're not forcing the join, check that the user is permitted to join.
    unless ($force) {

        # fire the event.
        my $can_fire = $user->fire(can_join => $channel, $key);

        # event was stopped; can't join.
        if ($can_fire->stopper) {
            my $cant_fire = $user->fire(cant_join => $channel, $can_fire);

            # if cant_join is canceled, do NOT send out the error reply.
            my @error_reply = ref_to_list($can_fire->{error_reply});
            if (!$cant_fire->stopper && @error_reply) {
                $user->numeric(@error_reply);
            }

            # can_join was stopped; don't continue.
            return;
        }
    }

    # new channel. do automodes and whatnot.
    if ($new) {

        # early join. this allows the automodes to set statuses on the user.
        $channel->add($user);

        # find automodes. replace each instance of +user with the UID.
        my $str = conf('channels', 'automodes') || '';
        $str =~ s/\+user/$$user{uid}/g;

        # we're using ->handle_mode_string() because ->do_mode_string()
        # does only two other things:
        #
        # 1. sends the mode change to other servers
        # (we're doing that below with channel_burst)
        #
        # 2. sends the mode change to other users
        # (at this point, no one is in the new channel yet)
        #
        $channel->handle_mode_string($me, $me, $str, 1, 1);

    }

    # tell other servers
    if ($new) {
        $pool->fire_command_all(channel_burst => $channel, $me, $user);
    }
    else {
        $pool->fire_command_all(join => $user, $channel, $channel->{time});
    }

    # do the actual join. the $new means to allow the ->do_join() even though
    # the user might already be in there from the previous ->add().
    return $channel->do_join($user, $new);

}

# handle a part locally for both local and remote users.
sub do_part {
    my ($channel, $user, $reason, $quiet) = @_;
    return if !$channel->has_user($user);

    # remove the user and tell the local channel users
    my $ureason = length $reason ? " :$reason" : '';
    $channel->sendfrom_all($user->full, "PART $$channel{name}$ureason");
    $channel->remove($user);

    # tell opers unless it's quiet
    notice(channel_part =>
        $user->notice_info, $channel->name, $reason // 'no reason')
        unless $quiet;

    return 1;
}

# handle a kick. send it to local users.
sub user_get_kicked {
    my ($channel, $user, $source, $reason) = @_;

    # fallback reason to source.
    $reason //= $source->name;

    # tell the local users of the channel.
    $channel->sendfrom_all(
        $source->full,
        "KICK $$channel{name} $$user{nick} :$reason"
    );

    notice(channel_kick =>
        $user->notice_info,
        $channel->name,
        $source->notice_info,
        $reason
    );

    return $channel->remove($user);
}

# handles a topic change. ignores newer topics.
# if the topic is an empty string or undef, it is unset.
# notifies users only if the text has actually changed.
#
# $source           source user or server to send TOPIC message from
# $topic            the new topic
# $setby            string for who set the topic
# $time             new topic TS
# $check_text       when true, do not send TOPIC unless text has changed
#
# returns true if the topic changed in any way, whether that be the text,
# setby, or topicTS.
#
sub do_topic {
    my ($channel, $source, $topic, $setby, $time, $check_text) = @_;
    $topic //= '';

    # if we're checking the text, see if it has changed.
    my $existing = $channel->{topic};
    my $text_unchanged;
    $text_unchanged++ if
        $check_text   && $existing  &&
        length $topic && $topic eq $existing->{topic};
    $text_unchanged++ if
        $check_text   && !$existing &&
        !length $topic;

    # determine what has changed.
    if ($text_unchanged) {
        return if
            $setby eq $channel->{topic}{setby} &&
            $time  == $channel->{topic}{time};
    }

    # tell users.
    else {
        $channel->sendfrom_all(
            $source->full,
            "TOPIC $$channel{name} :$topic"
        );
    }

    # no length, so unsetting.
    if (!length $topic) {
        delete $channel->{topic};
        return 1;
    }

    # set a new topic.
    $channel->{topic} = {
        setby  => $setby,
        time   => $time,
        topic  => $topic,
        source => $source->server->id
    };

    return 1;
}

$mod
