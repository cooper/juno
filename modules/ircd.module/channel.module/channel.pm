# Copyright (c) 2009-14, Mitchell Cooper
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
use feature 'switch';
use parent 'Evented::Object';

use utils qw(conf v notice match);
use List::Util qw(first max);

our ($api, $mod, $pool, $me);

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
    my @list = @{ $channel->{modes}{$name}{list} || [] };
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

    my @new = grep { $_->[0] ne $what } @{ $channel->{modes}{$name}{list} };
    $channel->{modes}{$name}{list} = \@new;
    
    L("$$channel{name}: removing $what from $name list");
    return 1;
}

# user joins channel
sub cjoin {
    my ($channel, $user, $time) = @_;
    return if $channel->has_user($user);
    
    # the channel TS will change
    # if the join time is older than the channel time.
    if ($time < $channel->{time}) {
        $channel->set_time($time);
    }
    
    # add the user to the channel.
    push @{ $channel->{users} }, $user;
    
    # note: as of 5.91, after-join (user_joined) event is fired in
    # mine.pm:           for locals
    # core_scommands.pm: for nonlocals.
 
    notice(user_join => $user->notice_info, $channel->name);
    return $channel->{time};
}

# remove a user.
# this could be due to any of part, quit, kick, server quit, etc.
sub remove {
    my ($channel, $user) = @_;

    # remove the user from status lists
    foreach my $name (keys %{ $channel->{modes} }) {
        $channel->remove_from_list($name, $user) if $me->cmode_type($name) == 4;
    }

    # remove the user.
    my @new = grep { $_ != $user } $channel->users;
    $channel->{users} = \@new;
    
    # delete the channel if this is the last user
    if (!scalar $channel->users) {
        $pool->delete_channel($channel);
        $channel->delete_all_events();
    }
    
    return 1;
}

# alias remove_user.
sub remove_user;
*remove_user = *remove;

# user is on channel.
sub has_user {
    my ($channel, $user) = @_;
    return first { $_ == $user } $channel->users;
}

# low-level channel time set.
sub set_time {
    my ($channel, $time) = @_;
    if ($time > $channel->{time}) {
        L("warning: setting time to a lower time from $$channel{time} to $time");
    }
    $channel->{time} = $time;
}

# ->handle_mode_string()
#
# handles a mode string at a low level.
# returns the mode string or '+' if no changes were made.
#
# NOTE: this is a lower-level function that only sets the modes.
# you probably want to use ->do_mode_string(), which sends to users and servers.
#
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
#
sub handle_mode_string {
    my ($channel, $server, $source, $modestr, $force, $over_protocol) = @_;
    L("set $modestr on $$channel{name} from $$server{name}");

    # split into +modes, arguments.
    my ($plus, $minus);
    my ($parameters, $state, $str, @m) = ([], 1, '', split /\s+/, $modestr);
    foreach my $letter (split //, shift @m) {

        # state change.
        if ($letter eq '+' || $letter eq '-') {
            $state = $letter eq '+';
            next;
        }
        
        # unknown mode?
        my $name = $server->cmode_name($letter);
        my $type = $server->cmode_type($name);
        if (!defined $name) {
            L("unknown mode $letter!");
            next;
        }
        
        # these are returned by ->cmode_takes_parameter: NOT mode types
        #     1 = always takes param
        #     2 = takes param, but valid if there isn't,
        #         such as list modes like +b for viewing
        #
        my ($takes, $parameter);
        if ($takes = $server->cmode_takes_parameter($name, $state)) {
            $parameter = shift @m;
            next if !defined $parameter && $takes == 1;
        }

        # if over_protocol is specified but not a code reference, fall back
        # to JELP UID lookup function for compatibility.
        if ($over_protocol && ref $over_protocol ne 'CODE') {
            $over_protocol = sub { $pool->lookup_user(@_) };
        }

        # don't allow this mode to be changed if the test fails
        # *unless* force is provided.
        my $params_before = scalar @$parameters;
        my ($win, $moderef) = $pool->fire_channel_mode($channel, $name, {
            channel => $channel,        # the channel
            server  => $server,         # the server perspective
            source  => $source,         # the source of the mode change (user or server)
            state   => $state,          # setting or unsetting
            setting => $state,          # to satisfy matthew
            param   => $parameter,      # the parameter for this particular mode
            params  => $parameters,     # the parameters for the resulting mode string
            force   => $force,          # true if permissions should be ignored
            proto   => $over_protocol,  # true if IDs used rather than nicks/names
            
            # source can set simple modes.
            has_basic_status => $force || $source->isa('server') ? 1
                                : $channel->user_has_basic_status($source),
                                
            # a function to look up a user by nickname or UID.
            user_lookup => $over_protocol || sub { $pool->lookup_user_nick(@_) }
                           
        });

        # block says to send ERR_CHANOPRIVSNEEDED.
        if ($moderef->{send_no_privs} && $source->isa('user') && $source->is_local) {
            $source->numeric(ERR_CHANOPRIVSNEEDED => $channel->name);
        }

        # block returned false; cancel.
        next if !$win;
        
        # if it requires a parameter but the param count before handling
        # the mode is the same as after, something didn't work.
        # for example, a mode handler might not be present if a module isn't loaded.
        # just ignore this mode.
        push @$parameters, $moderef->{param} if defined $moderef->{param};
        next if scalar @$parameters <= $params_before && $takes;

        # Safe point: from here we can assume that the mode will be set or unset.

        # it is a normal mode. set it.
        if ($type == 0) {
            my $do = $state ? 'set_mode' : 'unset_mode';
            $channel->$do($name);
        }
        
        # it is a mode with a parameter. set it.
        # does not include lists, status modes, key mode.
        elsif ($type == 1 || $type == 2) {
            $channel->set_mode($name, $parameter) if  $state;
            $channel->unset_mode($name)           if !$state;
        }
        
        # sign change.
        if ($state && !$plus) {
            ($plus, $minus) = (1, 0);
            $str .= '+';
        }
        elsif (!$state && !$minus) {
            ($plus, $minus) = (0, 1);
            $str .= '-';
        }
        
        $str .= $letter;
    }

    # make it change array refs to separate params for servers.
    # [USER RESPONSE, SERVER RESPONSE]
    my @user_params;
    my @server_params;
    foreach my $param (@$parameters) {
        if (ref $param eq 'ARRAY') {
            push @user_params,   $param->[0];
            push @server_params, $param->[1];
        }

        # not an array ref.
        else {
            push @user_params,   $param;
            push @server_params, $param;
        }
        
    }

    my $user_string   = join ' ', $str, @user_params;
    my $server_string = join ' ', $str, @server_params;

    L("end of mode handle");
    return ($user_string, $server_string);
}

# returns a +modes string.
sub mode_string        { _mode_string(0, @_) }
sub mode_string_hidden { _mode_string(1, @_) }
sub _mode_string       {
    my ($show_hidden, $channel, $server) = @_;
    my (@modes, @params);
    my @set_modes = sort keys %{ $channel->{modes} };
    
    # "normal types" generally means the ones that show in MODES.
    # does not include lists, status, etc.
    my %normal_types = (
        0 => 1,                 # normal modes always incluided
        1 => 1,                 # parameter always included
        2 => 1,                 # parameter_set always included
        5 => $show_hidden       # key only if included showing hidden
    );
    
    # add all the modes for each of these types.
    foreach my $name (@set_modes) {
        next unless $normal_types{ $server->cmode_type($name) };

        push @modes, $server->cmode_letter($name);
        my $param = $channel->mode_parameter($name);
        push @params, $param if defined $param;
    }

    return '+'.join(' ', join('', @modes), @params);
}


my %zero_or_one = map { $_ => 1 } (0, 1, 2);    # zero or one parameters
my %exactly_one = map { $_ => 1 } (1, 2, 5);    # exactly one parameter

# includes ALL modes
#
# returns a string for users and a string for servers
# $no_status = all but status modes
#
sub mode_string_all {
    my ($channel, $server, $no_status) = @_;
    my (@modes, @user_params, @server_params);
    my @set_modes = sort keys %{ $channel->{modes} };


    foreach my $name (@set_modes) {
        my $letter = $server->cmode_letter($name);
        my $type   = $server->cmode_type($name);
        
        # if it takes 0 or 1 parameters, add 1 mode letter.
        push @modes, $letter if $zero_or_one{$type};
        
        # exactly one parameter; add it.
        if ($exactly_one{$type}) {
            push @user_params,   $channel->{modes}{$name}{parameter};
            push @server_params, $channel->{modes}{$name}{parameter};
        }
        
        # list modes. add each item.
        elsif ($type == 3) {
            foreach my $thing ($channel->list_elements($name)) {
                push @modes,         $letter;
                push @user_params,   $thing;
                push @server_params, $thing;
            }
        }
        
        # status modes. add each nick/uid.
        elsif ($type == 4 && !$no_status) {
            foreach my $user ($channel->list_elements($name)) {
                push @modes,         $letter;
                push @user_params,   $user->{nick};
                push @server_params, $user->{uid};
            }
        }
        
    }
    
    # make +modes params strings.
    my $user_string   = '+'.join(' ', join('', @modes), @user_params);
    my $server_string = '+'.join(' ', join('', @modes), @server_params);

    # returns both a user string and a server string.
    return ($user_string, $server_string);
}

# same mode_string except for status modes only.
sub mode_string_status {
    my ($channel, $server) = @_;
    my (@modes, @user_params, @server_params);
    my @set_modes = sort keys %{ $channel->{modes} };

    foreach my $name (@set_modes) {
        my $letter = $server->cmode_letter($name);
        next unless $server->cmode_type($name) == 4;

        foreach my $user ($channel->list_elements($name)) {
            push @modes,         $letter;
            push @user_params,   $user->{nick};
            push @server_params, $user->{uid};
        }
    }

    # make +modes params strings.
    my $user_string   = '+'.join(' ', join('', @modes), @user_params);
    my $server_string = '+'.join(' ', join('', @modes), @server_params);

    # returns both a user string and a server string.
    return ($user_string, $server_string);
}

# returns true only if the passed user is in
# the passed status list.
sub user_is {
    my ($channel, $user, $what) = @_;
    return 1 if $channel->list_has($what, $user);
    return
}

# returns true value only if the passed user has status
# greater than voice (halfop, op, admin, owner)
sub user_has_basic_status {
    my ($channel, $user) = @_;
    return $channel->user_get_highest_level($user) >= 0;
}

# get the highest level of a user
# [letter, symbol, name]
sub user_get_highest_level {
    my ($channel, $user) = @_;
    return ($channel->user_get_levels($user))[0] // -inf;
}

# get all the levels of a user
sub user_get_levels {
    my ($channel, $user) = @_;
    my @levels;
    foreach my $level (sort { $b <=> $a } keys %ircd::channel_mode_prefixes) {
        my ($letter, $symbol, $name) = @{ $ircd::channel_mode_prefixes{$level} };
        push @levels, $level if $channel->list_has($name, $user);
    }
    return @levels;
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

sub id    { shift->{name}       }
sub name  { shift->{name}       }
sub users { @{ shift->{users} } }

############
### MINE ###
############

# handle a join for a local user.
sub localjoin {
    my ($channel, $user, $time) = @_;
    
    # do actual join, then tell the members.
    $channel->cjoin($user, $time);
    $channel->sendfrom_all($user->full, "JOIN $$channel{name}");

    # send topic and names.
    $user->handle("TOPIC $$channel{name}") if $channel->topic;
    names($channel, $user);
    
    $channel->fire_event(user_joined => $user);    
    return $channel->{time};
}

# send NAMES. FIXME: why is this here?
sub names {
    my ($channel, $user, $no_endof) = @_;
    my @str;
    my $curr = 0;
    foreach my $usr ($channel->users) {

        # if this user is invisible, do not show him unless the querier is in a common
        # channel or has the see_invisible flag.
        if ($usr->is_mode('invisible')) {
            next if !$channel->has_user($user) && !$user->has_flag('see_invisible');
        }

        # add him.
        my $prefixes = $user->has_cap('multi-prefix') ? 'prefixes' : 'prefix';
        $str[$curr] .= $channel->$prefixes($usr).$usr->{nick}.q( );
        $curr++ if length $str[$curr] > 500;
        
    }
    $user->numeric(RPL_NAMEREPLY  => '=', $channel->name, $_) foreach @str;
    $user->numeric(RPL_ENDOFNAMES =>      $channel->name    ) unless $no_endof;
}

# send mode information.
sub modes {
    my ($channel, $user) = @_;
    my $modestr = $channel->mode_string($user->{server});
    $user->numeric(RPL_CHANNELMODEIS =>  $channel->name, $modestr);
    $user->numeric(RPL_CREATIONTIME  =>  $channel->name, $channel->{time});
}

# send a message to all the local members.
sub send_all {
    my ($channel, $what, $ignore) = @_;
    foreach my $user ($channel->users) {
        next unless $user->is_local;
        next if defined $ignore && $ignore == $user;
        $user->send($what);
    }
    return 1;
}

# send to members with a source.
sub sendfrom_all {
    my ($channel, $who, $what, $ignore) = @_;
    return send_all($channel, ":$who $what", $ignore);
}

# send a notice to all the local members.
sub notice_all {
    my ($channel, $what, $ignore) = @_;
    foreach my $user ($channel->users) {
        next unless $user->is_local;
        next if defined $ignore && $ignore == $user;
        $user->sendfrom($me->name, "NOTICE $$channel{name} :*** $what");
    }
    return 1;
}

# take the lower time of a channel and unset higher time stuff.
sub take_lower_time {
    my ($channel, $time, $ignore_modes) = @_;
    return $channel->{time} if $time >= $channel->{time};

    L("locally resetting $$channel{name} time to $time");
    my $amount = $channel->{time} - $time;
    $channel->set_time($time);

    # unset topic.
    if ($channel->topic) {
        $channel->sendfrom_all($me->{name}, "TOPIC $$channel{name} :");
        delete $channel->{topic};
    }

    # unset all channel modes.
    # hackery: use the server mode string to reset all modes.
    # note: we can't use do_mode_string() because it would send to other servers.
    # note: we don't do this for CUM cmd ($ignore_modes = 1) because it handles
    #       modes in a prettier manner.
    if (!$ignore_modes) {
        my ($u_str, $s_str)  = $channel->mode_string_all($me);
        substr($u_str, 0, 1) = substr($s_str, 0, 1) = '-';
        $channel->sendfrom_all($me->{name}, "MODE $$channel{name} $u_str");
        $channel->handle_mode_string($me, $me, $s_str, 1, 1);
    }
    
    notice_all($channel, "New channel time: ".scalar(localtime $time)." (set back $amount seconds)");
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
        my ($letter, $symbol, $name) = @{ $ircd::channel_mode_prefixes{$level} };
        $prefixes .= $symbol if $channel->list_has($name, $user);
    }
    return $prefixes;
}

# same as do_mode_string() except it never sends to other servers.
sub do_mode_string_local { _do_mode_string(1, @_) }

# handle a mode string, tell our local users, and tell other servers.
sub  do_mode_string { _do_mode_string(undef, @_) }
sub _do_mode_string {
    my ($local_only, $channel, $perspective, $source, $modestr, $force, $protocol) = @_;

    # handle the mode.
    my ($user_result, $server_result) = $channel->handle_mode_string(
        $perspective, $source, $modestr, $force, $protocol
    );
    return unless $user_result;

    # tell the channel's users.
    my $local_ustr =
        $perspective == $me ? $user_result :
        $perspective->convert_cmode_string($me, $user_result);
    $channel->sendfrom_all($source->full, "MODE $$channel{name} $local_ustr");
    
    # stop here if it's not a local user or this server.
    return if $local_only || !$source->is_local;
    
    # the source is our user or this server, so tell other servers.
    # ($source, $channel, $time, $perspective, $server_modestr)
    $pool->fire_command_all(cmode =>
        $source, $channel, $channel->{time},
        $perspective, $server_result
    );
    
}

# handle a privmsg. send it to our local users and other servers.
# FIXME: this is just really bad.
# it is necessary though to distinguish real PRIVMSGs from ones initiated by other
# commands and whatnot; for example ECHO uses this directly.
sub handle_privmsgnotice {
    my ($channel, $command, $source, $message, $dont_forward, $force) = @_;
    my $user   = $source->isa('user')   ? $source : undef;
    my $server = $source->isa('server') ? $source : undef;
    $command   = uc $command;
    
    # it's a user.
    if ($user && !$force) {
        my $lccommand = lc $command;
        
        # can_message, can_notice, can_privmsg.
        return if $user->fire_events_together(
            [  can_message     => $channel, $message, $lccommand ],
            [ "can_$lccommand" => $channel, $message           ]
        )->stopper;
        
    }

    # tell local users.
    $channel->sendfrom_all($source->full, "$command $$channel{name} :$message", $source);

    # then tell other servers.
    my %sent;
    foreach my $usr ($channel->users) {
        last if $dont_forward;
        
        # local users already know.
        next if $usr->is_local;
        
        # the source user is reached through this user's server,
        # or the source is the server we know the user from.
        next if $user   && $usr->{location} == $user->{location};
        next if $server && $usr->{location}{sid} == $server->{sid};
        
        # already sent to this server.
        next if $sent{ $usr->{location} };
        
        $usr->{location}->fire_command(privmsgnotice => $command, $source, $channel, $message);
        $sent{ $usr->{location} } = 1;

    }
    
    # fire event.
    $channel->fire_event($command => $source, $message);

    return 1;
}

# handle a part. send it to local users.
sub handle_part {
    my ($channel, $user, $reason) = @_;
    
    # remove the user and tell the local channel users
    my $ureason = defined $reason ? " :$reason" : '';
    $channel->sendfrom_all($user->full, "PART $$channel{name}$ureason");
    $channel->remove($user);
    notice(user_part => $user->notice_info, $channel->name, $reason // 'no reason');

    return 1;
}

$mod