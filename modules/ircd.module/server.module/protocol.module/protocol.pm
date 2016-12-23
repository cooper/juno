# Copyright (c) 2016, Mitchell Cooper
#
# @name:            'ircd::server::protocol'
# @package:         'server::protocol'
# @description:     'common code for server to server protocols'
# @version:         ircd->VERSION
# @no_bless:        1
# @preserve_sym:    1

# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package server::protocol;

use warnings;
use strict;
use 5.010;

use Scalar::Util qw(blessed);
use utils qw(import ref_to_list notice gnotice conf);

our ($api, $mod, $pool, $me, $conf);
our %ircd_support;

#################################
### PROTOCOL-GENERIC HANDLERS ###
#################################

# handle_nick_collision()
#
# positive return means return the main NICK/UID/etc. handler.
# this works for NEW users only. do not use this for nick changes, etc.
#
sub handle_nick_collision {
    my ($server, $old, $new, $use_save) = @_;
    my ($kill_old, $kill_new);

    # the new user steals the nick.
    if ($old->{nick_time} > $new->{nick_time}) {
        $kill_old++;
    }

    # the existing user keeps the nick.
    elsif ($old->{nick_time} < $new->{nick_time}) {
        $kill_new++;
    }

    # they both lose the nick.
    else {
        $kill_old++;
        $kill_new++;
    }

    # ok, now we know who stays and who goes.
    # gotta decide whether to use SAVE or KILL.

    # if we can't use save, kill the appropriate users.
    if (!$use_save) {

        # if we can't save the new user, kill him.
        if ($kill_new) {
            $pool->fire_command_all(kill => $me, $new, 'Nick collision');
        }

        # if we can't save the old user, kill him.
        if ($kill_old) {
            $old->get_killed_by($me, 'Nick collision');
            $pool->fire_command_all(kill => $me, $old, 'Nick collision');
        }

        return 1; # true value = return the handler
    }

    # At this point, we can SAVE the user(s).
    # Note that SAVE is always sent with the existing nickTS.
    # if the provided TS is not the current nickTS, SAVE is ignored.
    # Upon handling a valid SAVE, however, the nickTS becomes 100.


    # Send out a SAVE for the existing user
    # and broadcast a local nick change to his UID.
    if ($kill_old) {
        $pool->fire_command_all(save_user => $me, $old, $old->{nick_time});
        $old->save_locally;
    }

    # Send out a SAVE for the new user
    # and change his nick to his TS6 UID locally.
    #
    # we ONLY send this to the server which caused the collision.
    # all other servers will be notified when the user introduction is sent.
    #
    if ($kill_new) {
        $server->fire_command(save_user => $me, $new, $new->{nick_time});
        my $old_nick      = $new->{nick};
        $new->{nick}      = $new->{uid};
        $new->{nick_time} = 100;
        notice(user_saved => $new->notice_info, $old_nick);
    }

    return; # false value = continue the handler
}

# handle_svsnick()
#
# if a nick change force is valid, change the nick and propagate NICK.
# also deals with killing existing users/connections.
#
sub handle_svsnick {
    my ($msg, $source_serv, $user, $new_nick, $new_nick_ts, $old_nick_ts) = @_;

    # ignore the message if the old nickTS is incorrect.
    if ($user->{nick_time} != $old_nick_ts) {
        return;
    }

    # check if the nick is in use.
    my $existing = $pool->nick_in_use($new_nick);

    # the nickname is already in use by an unregistered connection.
    if ($existing && $existing->isa('connection')) {
        $existing->done('Overriden');
    }

    # the nickname is in use by a user.
    elsif ($existing && $existing != $user) {
        my $reason = 'Nickname regained by services';
        $existing->get_killed_by($source_serv, $reason);
        $pool->fire_command_all(kill => $source_serv, $existing, $reason);
    }

    # change the nickname.
    $user->send_to_channels("NICK $new_nick")
        unless $user->{nick} eq $new_nick;
    $user->change_nick($new_nick, $new_nick_ts);

    #=== Forward ===#
    #
    # RSFNC has a single-server target, so the nick change must be
    # propagated as a NICK message.
    #
    $msg->forward_plus_one(nick_change => $user);

    return 1;
}

###############################
### PRIVMSG/NOTICE HANDLING ###
###############################

# handle_privmsgnotice()
# Generic PRIVSG/NOTICE handler.
# See issue #10 for complex PRIVMSG info.
#
# Required:
#
#   channel_lookup      channel lookup function.
#
#   user_lookup         UID lookup function.
#
# Optional:
#
#   smask_prefix        prefix for messaging all users on server names matching
#                       a mask (usually '$$' or '$').
#
#   opmod_prefix        prefix for messaging ops in an op moderated channel.
#
#   supports_atserv     if true, the protocol supports the user@server target.
#                       this is not handled here, except that the message may
#                       be routed to a server with an exact name match.
#
#   opers_prefix        prefix for sending a message to all online opers.
#                       this only works with supports_atserv.
#
#   chan_prefixes       a list of prefixes which might prepend channel targets.
#                       only members with this status or higher will be targets.
#
#   chan_lvl_lookup     code which takes a prefix (something from chan_prefixes)
#                       and returns a juno status level. required with
#                       chan_prefixes.
#
sub handle_privmsgnotice {
    my ($server, $msg, $source, $command, $target, $message, %opts) = @_;
    my $prefix;

    # Complex PRIVMSG
    #   a message to all users on server names matching a mask
    #   ('$$' followed by mask)
    #   propagation: broadcast
    if (length($prefix = $opts{serv_mask_prefix})) {
        my $pfx = \substr(my $t_name = $target, 0, length $prefix);
        if ($$pfx eq $prefix) {
            $$pfx = '';
            return _privmsgnotice_smask(@_[0..3], $t_name, $message, %opts);
        }
    }

    # - Complex PRIVMSG
    #   '=' followed by a channel name, to send to chanops only, for cmode +z.
    #   capab:          CHW and EOPMOD
    #   propagation:    all servers with -D chanops
    if (length($prefix = $opts{opmod_prefix})) {
        my $pfx = \substr(my $t_name = $target, 0, length $prefix);
        if ($$pfx eq $prefix) {
            $$pfx = '';
            my $channel = $opts{channel_lookup}($t_name) or return;
            return _privmsgnotice_opmod(@_[0..3], $channel, $message, %opts);
        }
    }

    # - Complex PRIVMSG
    #   a status character ('@'/'+') followed by a channel name, to send to users
    #   with that status or higher only.
    #   capab:          CHW
    #   propagation:    all servers with -D users with appropriate status
    # Note: Check this after all other prefixes but before user@server.
    foreach $prefix (ref_to_list($opts{chan_prefixes})) {
        my $pfx = \substr(my $t_name = $target, 0, length $prefix);
        next if $$pfx ne $prefix;
        $$pfx = '';
        my $channel = $opts{channel_lookup}($t_name) or return;

        # find the level
        my $level = $opts{chan_lvl_lookup}($prefix);
        defined $level or return;

        return _privmsgnotice_status(@_[0..3], $channel, $message, $level, %opts);
    }

    # - Complex PRIVMSG
    #   a user@server message, to send to users on a specific server. The exact
    #   meaning of the part before the '@' is not prescribed, except that "opers"
    #   allows IRC operators to send to all IRC operators on the server in an
    #   unspecified format.
    #   propagation:    one-to-one
    if ($opts{supports_atserv} && $target =~ m/^(.+)\@(.+)$/) {
        my ($nick, $serv_str) = ($1, $2);
        return _privmsgnotice_atserver(
            @_[0..3],
            $nick, $serv_str, $message, %opts
        );
    }

    # is it a user?
    my $tuser = $opts{user_lookup}($target);
    if ($tuser) {

        # if it's mine, send it.
        if ($tuser->is_local) {
            $tuser->sendfrom($source->full, "$command $$tuser{nick} :$message");
            return 1;
        }

        # === Forward ===
        #
        # the user does not belong to us;
        # pass this on to its physical location.
        #
        $msg->forward_to($tuser, privmsgnotice =>
            $command, $source,
            $tuser,   $message
        );

        return 1;
    }

    # must be a channel.
    my $channel = $opts{channel_lookup}($target);
    if ($channel) {

        # === Forward ===
        #
        #  ->do_privmsgnotice() deals with routing
        #
        $channel->do_privmsgnotice($command, $source, $message, force => 1);

        return 1;
    }

    # at this point, we don't know what to do
    notice(server_protocol_warning =>
        $server->notice_info,
        "sent unknown target '$target' for $command; ignored"
    );

    return;
}

# - Complex PRIVMSG
#   a message to all users on server names matching a mask ('$$' followed by mask)
#   propagation: broadcast
#   Only allowed to IRC operators.
#
sub _privmsgnotice_smask {
    my ($server, $msg, $source, $command, $mask, $message, %opts) = @_;

    # it cannot be a server source.
    if ($source->isa('server')) {
        notice(server_protocol_warning =>
            $source->notice_info,
            "cannot be sent $command because '\$\$' targets are ".
            "not permitted with a server source"
        );
        return;
    }

    # consider each server that matches
    my %done;
    foreach my $serv ($pool->lookup_server_mask($mask)) {
        my $location = $serv->{location} || $serv; # for $me, location = nil

        # already did or the server is connected via the source server
        next if $done{$location};
        next if $location == $server;

        # if the server is me, send to all my users
        if ($serv == $me) {
            $_->sendfrom($source->full, "$command $$_{nick} :$message")
                foreach $pool->local_users;
            $done{$me} = 1;
            next;
        }

        # otherwise, forward it
        $msg->forward_to($serv, privmsgnotice =>
            $command, $source,
            undef,    $message,
            serv_mask => $mask
        );

        $done{$location} = 1;
    }

    return 1;
}

# - Complex PRIVMSG
#   '=' followed by a channel name, to send to chanops only, for cmode +z.
#   capab:          CHW and EOPMOD
#   propagation:    all servers with -D chanops
#
sub _privmsgnotice_opmod {
    my ($server, $msg, $source, $command, $channel, $message, %opts) = @_;

    #=== Forward ===#
    #
    # Forwarding for opmod is handled by ->do_privmsgnotice()!
    #
    $channel->do_privmsgnotice(
        $command, $source, $message,
        force => 1,
        op_moderated => 1
    );

    return 1;
}

# - Complex PRIVMSG
#   a user@server message, to send to users on a specific server. The exact
#   meaning of the part before the '@' is not prescribed, except that "opers"
#   allows IRC operators to send to all IRC operators on the server in an
#   unspecified format.
#   propagation:    one-to-one
#
sub _privmsgnotice_atserver {
    my ($server, $msg, $source, $command,
    $nick, $serv_str, $message, %opts) = @_;

    # if the server is not exactly equal to this one, forward it.
    my $serv = $opts{atserv_lookup}($serv_str) or return;
    if ($serv != $me) {

        # === Forward ===
        $msg->forward_to($serv, privmsgnotice =>
            $command, $source,
            undef,    $message,
            atserv_nick => $nick,
            atserv_serv => $serv
        );

        return 1;
    }

    # Safe point - this server is the target.

    # if the target is opers@me, send a notice to online opers.
    my $prefix;
    if (length($prefix = $opts{opers_prefix}) && $nick eq $prefix) {

        # we should check even if remote users are oper for this
        return if $source->isa('user') && !$source->is_mode('ircop');

        notice(oper_message => $source->notice_info, $message);
        return 1;
    }

    return;
}

# - Complex PRIVMSG
#   a status character ('@'/'+') followed by a channel name, to send to users
#   with that status or higher only.
#   capab:          CHW
#   propagation:    all servers with -D users with appropriate status
#
sub _privmsgnotice_status {
    my ($server, $msg, $source, $command,
    $channel, $message, $level, %opts) = @_;

    #=== Forward ===#
    $channel->do_privmsgnotice(
        $command, $source, $message,
        force => 1,
        min_level => $level
    );

    return 1;
}

##################################
### PROTOCOL-GENERIC UTILITIES ###
##################################

# checks if a server can be created.
sub check_new_server {
    my (
        $sid,       # SID of new server
        $name,      # name of new server
        $origin     # name of the server introducing this one
    ) = @_;

    # TODO: check for bogus server name
    # TODO: eventually check SSL, port, IP here.

    # SID taken?
    if (my $other = $pool->lookup_server($sid)) {
        #* *** Notice: Server identifier taken: mad.is.annoying attempted to
        # introduce 902 as SID 0, which is already taken by
        notice(server_identifier_taken => $origin, $name, $sid, $other->{name});
        return 'SID already exists';
    }

    # server name taken?
    if ($pool->lookup_server_name($name)) {
        notice(server_reintroduced => $origin, $name);
        return 'Server exists';
    }

    return;
}

# forward_global_command(\@servers_matching, command => @args)
#
# returns: hashref of servers matching (direct or not)
#          hashref of servers send to  (direct locations)
#
our $INJECT_SERVERS = \0;
sub forward_global_command {
    my @servers = ref_to_list(shift);
    my @command_stuff = @_;

    # wow there are matches.
    my (%done, %send_to, @send_locations);
    foreach my $serv (@servers) {

        # already did this one!
        next if $done{$serv};
        $done{$serv} = 1;

        # if it's $me, skip.
        # if there is no connection (whether direct or not),
        # uh, I don't know what to do at this point!
        next if $serv->is_local;
        next unless $serv->{location};

        # add to the list of servers to send to this location.
        push @send_locations, $serv->{location};
        push @{ $send_to{ $serv->{location} } ||= [] }, $serv;

    }

    # for each location, send the RELOAD command with the matching servers.
    my %loc_done;
    foreach my $location (@send_locations) {
        next if $loc_done{$location};
        my $their_servers = $send_to{$location} or next;

        # determine the arguments. inject matching servers.
        my @args;
        foreach my $arg (@command_stuff) {
            if (ref $arg && $arg == $INJECT_SERVERS) {
                push @args, ref_to_list($their_servers);
                next;
            }
            push @args, $arg;
        }

        # fire the command.
        $location->fire_command(@args);
        $loc_done{$location}++;

    }

    return wantarray ? (\%done, \%loc_done) : \%done;
}

sub cmode_change_start {
    my $server = shift;

    # find the currently enabled user modes.
    # weed out the ones that have no mode blocks registered.
    my %enabled = %{ $server->{cmodes} };
    for (keys %enabled) {
        next if $pool->{channel_modes}{$_};
        delete $enabled{$_};
    }

    return \%enabled;
}

# this should be called with hash references of before and after some
# event which may have added or removed channel modes. some protocols such as
# JELP may need to notify other servers of changes to mode mapping tables.
#
# these hash references are in the form { mode_name => { letter => type => }}
#
sub cmode_change_end {
    my ($server, $previously_enabled) = @_;

    # find the currently enabled user modes.
    # weed out the ones that have no mode blocks registered.
    my %enabled = %{ $server->{cmodes} };
    for (keys %enabled) {
        next if $pool->{channel_modes}{$_};
        delete $enabled{$_};
    }

    # figure out which were added and which were removed.
    my (@added, @removed);

    foreach my $mode_name (keys %enabled) {

        # we have addressed this, so remove it from the old list
        my $old = delete $previously_enabled->{$mode_name};
        my $new = $enabled{$mode_name};

        # if it existed, check if it has changed
        next if $old &&
            $old->{letter} eq $new->{letter} &&
            $old->{type}   == $new->{type};

        # it has changed or did not exist, so add it
        push @added, [ $mode_name, $new->{letter}, $new->{type} ];
    }

    # anything that's left in the old list at this point was removed.
    my @removed = keys %$previously_enabled;

    return if !@added && !@removed;
    $pool->fire_command_all(add_cmodes => $server, \@added, \@removed);
    $pool->fire(cmodes_changed => \@added, \@removed);
}

sub umode_change_start {
    my $server = shift;

    # find the currently enabled user modes.
    # weed out the ones that have no mode blocks registered.
    my %enabled = %{ $server->{umodes} };
    for (keys %enabled) {
        next if $pool->{user_modes}{$_};
        delete $enabled{$_};
    }

    return \%enabled;
}

# this should be called with hash references of before and after some
# event which may have added or removed user modes. some protocols such as
# JELP may need to notify other servers of changes to mode mapping tables.
#
# these hash references are in the form { mode_name => { letter => }}
#
sub umode_change_end {
    my ($server, $previously_enabled) = @_;

    # find the currently enabled user modes.
    # weed out the ones that have no mode blocks registered.
    my %enabled = %{ $server->{umodes} };
    for (keys %enabled) {
        next if $pool->{user_modes}{$_};
        delete $enabled{$_};
    }

    # figure out which were added and which were removed.
    my (@added, @removed);

    foreach my $mode_name (keys %enabled) {

        # we have addressed this, so remove it from the old list
        my $old = delete $previously_enabled->{$mode_name};
        my $new = $enabled{$mode_name};

        # if it existed, check if it has changed
        next if $old &&
            $old->{letter} eq $new->{letter};

        # it has changed or did not exist, so add it
        push @added, [ $mode_name, $new->{letter} ];
    }

    # anything that's left in the old list at this point was removed.
    my @removed = keys %$previously_enabled;

    return if !@added && !@removed;
    $pool->fire_command_all(add_umodes => $server, \@added, \@removed);
    $pool->fire(umodes_changed => \@added, \@removed);
}

sub mode_change_start {
    my $server = shift;
    my $ret1 = umode_change_start($server);
    my $ret2 = cmode_change_start($server);
    return [ $ret1, $ret2 ];
}

sub mode_change_end {
    my ($server, $ret) = @_;
    umode_change_end($server, $ret->[0]);
    cmode_change_end($server, $ret->[1]);
}

####################
### IRCD SUPPORT ###
####################

# fetch a hash of options from an IRCd definition in the configuration.
# see issue #110.
sub ircd_support_hash {
    my ($ircd, $key) = @_;
    $key ||= 'ircd';

    # we have it cached
    if (my $hashref = $ircd_support{$ircd}{$key}) {
        return ref_to_list($hashref);
    }

    # we have not gotten main ircd info yet
    if ($key ne 'ircd' && !$ircd_support{$ircd}{ircd}) {
        ircd_support_hash($ircd);
    }

    # find this ircd's options
    my %our_stuff = $conf->hash_of_block([ $key, $ircd ]);
    if ($key eq 'ircd' && !%our_stuff) {
        L("ircd '$ircd' is unknown; there is no definition!");
        return;
    }

    # this IRCd extends another, so inject those options
    my $extends = $our_stuff{extends} || $ircd_support{$ircd}{ircd}{extends};
    if (length $extends && $extends ne $ircd) {
        my %their_stuff = ircd_support_hash($extends, $key);
        %our_stuff = (%their_stuff, %our_stuff);
    }

    $ircd_support{$ircd}{$key} = \%our_stuff;
    return %our_stuff;
}

# register modes to a server based on the IRCd definition in the configuration.
# see issue #110.
sub ircd_register_modes {
    my ($ircd, $server) = @_;

    # this can be called without an ircd name
    if (blessed $ircd) {
        $server = $ircd;
        $ircd = $server->{ircd_name};
    }

    # user modes.
    my %modes = ircd_support_hash($ircd, 'ircd_umodes');
    $server->add_umode($_, $modes{$_}) foreach keys %modes;

    # channel modes.
    %modes = ircd_support_hash($ircd, 'ircd_cmodes');
    foreach my $name (keys %modes) {
        my ($type, $letter) = ref_to_list($modes{$name});
        $server->add_cmode($name, $letter, $type);
    }

    # status modes.
    %modes = ircd_support_hash($ircd, 'ircd_prefixes');
    foreach my $name (keys %modes) {
        my ($letter, $pfx, $lvl) = @{ $modes{$name} };
        $server->{ircd_prefixes}{$pfx} = [ $letter, $lvl ];
        $server->add_cmode($name, $letter, 4);
    }

    return 1;
}

$mod
