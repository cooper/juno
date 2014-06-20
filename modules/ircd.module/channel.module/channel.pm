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

our ($api, $mod, $pool, $me);

sub new {
    my ($class, %opts) = @_;
    return bless {
        users => [],
        modes => {},
        %opts
    }, $class;
}

# named mode stuff

sub is_mode {
    my ($channel, $name) = @_;
    return exists $channel->{modes}{$name}
}

sub unset_mode {
    my ($channel, $name) = @_;

    # is the channel set to this mode?
    if (!$channel->is_mode($name)) {
        L("attempted to unset mode $name on that is not set on $$channel{name}; ignoring.")
    }

    # it is, so remove it
    delete $channel->{modes}{$name};
    L("$$channel{name} -$name");
    return 1
}

# set channel modes
# takes an optional parameter
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

# list has something
sub list_has {
    my ($channel, $name, $what) = @_;
    return unless exists $channel->{modes}{$name};
    foreach my $thing ($channel->list_elements($name)) {
        return 1 if $thing eq $what
    }
    return
}

# something matches in an expression list
# returns the match if there is one.
sub list_matches {
    my ($channel, $name, $what) = @_;
    return unless exists $channel->{modes}{$name};
    foreach my $mask ($channel->list_elements($name)) {
        my $realmask = $mask;
        $realmask = (split ':', $mask, 2)[1] if $mask =~ m/^(.+?):(.+)!(.+)\@(.+)/;
        return $mask if match($what, $realmask);
    }
    return;
}

# returns an array of list elements
sub list_elements {
    my ($channel, $name, $all) = @_;
    return unless exists $channel->{modes}{$name};
    my @list = @{ $channel->{modes}{$name}{list} };
    if ($all)  { return @list }
    return map { $_->[0]      } @list;
}

# adds something to a list mode (such as ban)
sub add_to_list {
    my ($channel, $name, $parameter, %opts) = @_;
    $channel->{modes}{$name} = {
        time => time,
        list => []
    } unless exists $channel->{modes}{$name};

    # no duplicates plz
    if ($channel->list_has($name, $parameter)) {
        return;
    }

    L("$$channel{name}: adding $parameter to $name list");
    my $array = [$parameter, \%opts];
    push @{ $channel->{modes}{$name}{list} }, $array;
    
    return 1;
}

# removes something from a list
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

    # fire before join event.
    # FIXME: um I think this event should be removed.
    # any checks should be done in server and user handlers...
    # and I don't think anything uses this.
    my $e = $channel->fire_event(user_will_join => $user);
    
    # a handler suggested that the join should not occur.
    return if $e->{join_fail};
    
    # the channel TS will change
    # if the join time is older than the channel time
    if ($time < $channel->{time}) {
        $channel->set_time($time);
    }
    
    # add the user to the channel
    push @{ $channel->{users} }, $user;
    
    # note: as of 5.91, after-join (user_joined) event is fired in
    # mine.pm:           for locals
    # core_scommands.pm: for nonlocals.
 
    notice(user_join => $user->notice_info, $channel->name);
    return $channel->{time};
}

# remove a user
# note that this is not necessarily a part.
# it could be that a user quit.
sub remove {
    my ($channel, $user) = @_;

    # remove the user from status lists
    foreach my $name (keys %{ $channel->{modes} }) {
        if ($me->cmode_type($name) == 4) {
            $channel->remove_from_list($name, $user);
        }
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

# user is on channel
sub has_user {
    my ($channel, $user) = @_;
    foreach my $usr (@{ $channel->{users} }) {
        return 1 if $usr == $user
    }
    return
}

# set the channel time
sub set_time {
    my ($channel, $time) = @_;
    if ($time > $channel->{time}) {
        L("warning: setting time to a lower time from $$channel{time} to $time");
    }
    $channel->{time} = $time
}

# returns the mode string,
# or '+' if no changes were made.
# NOTE: this is a lower-level function that only sets the modes.
# you probably want to use ->do_mode_string(), which sends to users and servers.
sub handle_mode_string {
    my ($channel, $server, $source, $modestr, $force, $over_protocol) = @_;
    L("set $modestr on $$channel{name} from $$server{name}");

    # array reference passed to mode blocks and used in the return
    my $parameters = [];

    my $state = 1;
    my $str   = '+';
    my @m     = split /\s+/, $modestr;

    letter: foreach my $letter (split //, shift @m) {
        if ($letter eq '+') {
            $str  .= '+' unless $state;
            $state = 1
        }
        elsif ($letter eq '-') {
            $str  .= '-' if $state;
            $state = 0
        }
        else {
            my $name = $server->cmode_name($letter);
            if (!defined $name) {
                L("unknown mode $letter!");
                next
            }
            
            # 1 == always takes param
            # 2 == takes param, but valid if there isn't, such as list modes like +b for viewing
            my ($takes, $parameter);
            if ($takes = $server->cmode_takes_parameter($name, $state)) {
                $parameter = shift @m;
                next letter if !defined $parameter && $takes == 1;
            }

            # don't allow this mode to be changed if the test fails
            # *unless* force is provided.
            my $params_before = scalar @$parameters;
            my ($win, $moderef) = $pool->fire_channel_mode(
                $channel, $server, $source, $state, $name, $parameter,
                $parameters, $force, $over_protocol
            );

            # block says to send ERR_CHANOPRIVSNEEDED
            if ($moderef->{send_no_privs} && $source->isa('user') && $source->is_local) {
                $source->numeric(ERR_CHANOPRIVSNEEDED => $channel->name);
            }

            # blocks failed.
            if (!$force) { next letter unless $win }

            # block says not to set.
            next letter if $moderef->{do_not_set};
            
            # if it requires a parameter but the param count before handling
            # the mode is the same as after, something didn't work.
            # for example, a mode handler might not be present if a module isn't loaded.
            # just ignore this mode.
            if (scalar @$parameters <= $params_before && $takes) {
                next letter;
            }

            # if it is just a normal mode, set it
            if ($server->cmode_type($name) == 0) {
                my $do = $state ? 'set_mode' : 'unset_mode';
                $channel->$do($name);
            }
            $str .= $letter;
            
        }
    }

    # it's easier to do this than it is to keep track of them
    $str =~ s/\+\+/\+/g;
    $str =~ s/\-\+/\+/g;
    $str =~ s/\-\-/\-/g; 
    $str =~ s/\+\-/\-/g;
    $str =~ s/(\-|\+)$//;

    # make it change array refs to separate params for servers
    # [USER RESPONSE, SERVER RESPONSE]
    my @user_params;
    my @server_params;
    foreach my $param (@$parameters) {
        if (ref $param eq 'ARRAY') {
            push @user_params,   $param->[0];
            push @server_params, $param->[1];
        }

        # not an array ref
        else {
            push @user_params,   $param;
            push @server_params, $param;
        }
    }

    my $user_string   = join ' ', $str, @user_params;
    my $server_string = join ' ', $str, @server_params;

    L("end of mode handle");
    return ($user_string, $server_string)
}

# returns a +modes string
#   normal (0)
#   parameter (1)
#   parameter_set (2)
#   list (3)
#   status (4)
sub mode_string {
    my ($channel, $server) = @_;
    my (@modes, @params);
    my @set_modes = sort keys %{ $channel->{modes} };
    my %normal_types = (0 => 1, 1 => 1, 2 => 1);
    foreach my $name (@set_modes) {
        next unless $normal_types{ $server->cmode_type($name) };

        push @modes, $server->cmode_letter($name);
        if (my $param = $channel->{modes}{$name}{parameter}) {
            push @params, $param
        }
    }

    return '+'.join(' ', join('', @modes), @params)
}

# includes ALL modes
# returns a string for users and a string for servers
# $no_status = all but status modes
sub mode_string_all {
    my ($channel, $server, $no_status) = @_;
    my (@modes, @user_params, @server_params);
    my @set_modes = sort keys %{ $channel->{modes} };

    foreach my $name (@set_modes) {
        my $letter = $server->cmode_letter($name);
        given ($server->cmode_type($name)) {

            # modes with 0 or 1 parameters
            when ([0, 1, 2]) {
                push @modes, $letter;
                continue
            }

            # modes with ONE parameter
            when ([1, 2]) {
                push @user_params,   $channel->{modes}{$name}{parameter};
                push @server_params, $channel->{modes}{$name}{parameter}
            }

            # lists
            when (3) {
                foreach my $thing ($channel->list_elements($name)) {
                    push @modes,         $letter;
                    push @user_params,   $thing;
                    push @server_params, $thing
                }
            }

            # lists of users
            when (4) {
                next if $no_status;
                foreach my $user ($channel->list_elements($name)) {
                    push @modes,         $letter;
                    push @user_params,   $user->{nick};
                    push @server_params, $user->{uid}
                }
            }

            # idk
            default  { next }
        }
    }

    # make +modes params strings
    my $user_string   = '+'.join(' ', join('', @modes), @user_params);
    my $server_string = '+'.join(' ', join('', @modes), @server_params);

    # returns both a user string and a server string
    return ($user_string, $server_string)
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

    # make +modes params strings
    my $user_string   = '+'.join(' ', join('', @modes), @user_params);
    my $server_string = '+'.join(' ', join('', @modes), @server_params);

    # returns both a user string and a server string
    return ($user_string, $server_string)
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
    my $biggest = -'inf';
    foreach my $level (keys %ircd::channel_mode_prefixes) {
        my ($letter, $symbol, $name) = @{ $ircd::channel_mode_prefixes{$level} };
        $biggest = $level if $level > $biggest && $channel->list_has($name, $user);
    }
    return $biggest;
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

# omg hax
# it has the same name as the one in channel.pm.
# the only difference is that this one sends
# the mode changes around
sub localjoin {
    my ($channel, $user, $time, $force) = @_;
    if ($channel->has_user($user)) {
        return unless $force;
    }
    else {
        $channel->cjoin($user, $time);
    }

    # for each user in the channel
    foreach my $usr ($channel->users) {
        next unless $usr->is_local;
        $usr->sendfrom($user->full, "JOIN $$channel{name}")
    }

    $user->handle("TOPIC $$channel{name}") if $channel->topic;
    names($channel, $user);
    
    # fire after join event.
    $channel->fire_event(user_joined => $user);
    
    return $channel->{time};
}

# send NAMES
# this is here instead of user::handlers because it is convenient to send on channel join
sub names {
    my ($channel, $user, $no_endof) = @_;
    my @str;
    my $curr = 0;
    foreach my $usr ($channel->users) {

        # if this user is invisible, do not show him unless the querier is in a common
        # channel or has the see_invisible flag.
        if ($usr->is_mode('invisible')) {
            next if !$channel->has_user($user) && !$user->has_flag('see_invisible')
        }

        my $prefixes = $user->has_cap('multi-prefix') ? 'prefixes' : 'prefix';
        $str[$curr] .= $channel->$prefixes($usr).$usr->{nick}.q( );
        $curr++ if length $str[$curr] > 500
    }
    $user->numeric('RPL_NAMEREPLY', '=', $channel->name, $_) foreach @str;
    $user->numeric('RPL_ENDOFNAMES', $channel->name) unless $no_endof;
}

sub modes {
    my ($channel, $user) = @_;
    $user->numeric('RPL_CHANNELMODEIS', $channel->name, $channel->mode_string($user->{server}));
    $user->numeric('RPL_CREATIONTIME',  $channel->name, $channel->{time});
}

sub send_all {
    my ($channel, $what, $ignore) = @_;
    foreach my $user ($channel->users) {
        next unless $user->is_local;
        next if defined $ignore && $ignore == $user;
        $user->send($what);
    }
    return 1
}

sub sendfrom_all {
    my ($channel, $who, $what, $ignore) = @_;
    return send_all($channel, ":$who $what", $ignore);
}

# send a notice to every user
sub notice_all {
    my ($channel, $what, $ignore) = @_;
    foreach my $user ($channel->users) {
        next unless $user->is_local;
        next if defined $ignore && $ignore == $user;
        $user->send(":$$me{name} NOTICE $$channel{name} :*** $what");
    }
    return 1
}

# take the lower time of a channel and unset higher time stuff
sub take_lower_time {
    my ($channel, $time, $ignore_modes) = @_;
    return $channel->{time} if $time >= $channel->{time}; # never take a time that isn't lower

    L("locally resetting $$channel{name} time to $time");
    my $amount = $channel->{time} - $time;
    $channel->set_time($time);

    # unset topic.
    if ($channel->topic) {
        sendfrom_all($channel, $me->{name}, "TOPIC $$channel{name} :");
        delete $channel->{topic};
    }

    # unset all channel modes.
    # hackery: use the server mode string to reset all modes.
    # note: we can't use do_mode_string() because it would send to other servers.
    # note: we don't do this for CUM cmd ($ignore_modes = 1) because it handles
    #       modes in a prettier manner.
    if (!$ignore_modes) {
        my ($u_str, $s_str) = $channel->mode_string_all($me);
        substr($u_str, 0, 1) = substr($s_str, 0, 1) = '-';
        sendfrom_all($channel, $me->{name}, "MODE $$channel{name} $u_str");
        $channel->handle_mode_string($me, $me, $s_str, 1, 1);
    }
    
    notice_all($channel, "New channel time: ".scalar(localtime $time)." (set back \2$amount\2 seconds)");
    return $channel->{time};
}

# returns the highest prefix a user has
sub prefix {
    my ($channel, $user) = @_;
    my $level = $channel->user_get_highest_level($user);
    if (defined $level && $ircd::channel_mode_prefixes{$level}) {
        return $ircd::channel_mode_prefixes{$level}[1]
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
    return unless $source->is_local;
    
    # the source is our user or this server, so tell other servers.
    # ($source, $channel, $time, $perspective, $server_modestr)
    $pool->fire_command_all(cmode =>
        $source, $channel, $channel->{time},
        $perspective->{sid}, $server_result
    ) unless $local_only;
    
}

# handle a privmsg. send it to our local users and other servers.
sub handle_privmsgnotice {
    my ($channel, $command, $source, $message) = @_;
    my $user   = $source->isa('user')   ? $source : undef;
    my $server = $source->isa('server') ? $source : undef;
    
    
    # it's a user.
    if ($user) {
    
        # no external messages?
        if ($channel->is_mode('no_ext') && !$channel->has_user($user)) {
            $user->numeric(ERR_CANNOTSENDTOCHAN => $channel->name, 'No external messages');
            return;
        }

        # moderation and no voice?
        if ($channel->is_mode('moderated')   &&
          !$channel->user_is($user, 'voice') &&
          !$channel->user_has_basic_status($user)) {
            $user->numeric(ERR_CANNOTSENDTOCHAN => $channel->name, 'Channel is moderated');
            return;
        }

    }

    # tell local users.
    $channel->sendfrom_all($source->full, "$command $$channel{name} :$message", $source);

    # then tell local servers.
    my %sent;
    foreach my $usr ($channel->users) {
    
        # local users already know.
        next if $usr->is_local;
        
        # the source user is reached through this user's server,
        # or the source is the server we know the user from.
        next if $user   && $usr->{location} == $user->{location};
        next if $server && $usr->{location}{sid} == $server->{sid};
        
        # already sent to this server.
        next if $sent{ $usr->{location} };
        
        $usr->{location}->fire_command(privmsgnotice => $command, $user, $channel, $message);
        $sent{ $usr->{location} } = 1;

    }
    
    # fire event.
    $channel->fire_event(lc $command => $user, $message);

    return 1;
    
}

$mod