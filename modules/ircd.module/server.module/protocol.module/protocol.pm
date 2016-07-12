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

use utils qw(import ref_to_list notice gnotice);

our ($api, $mod, $pool, $me);

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
    # and broadcast a local nickchange to his UID.
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

$mod
