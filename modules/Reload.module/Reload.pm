# Copyright (c) 2012-14, Mitchell Cooper
#
# @name:            "Reload"
# @package:         "M::Reload"
# @description:     "reload the entire IRCd in one command"
#
# @depends.modules: ['Base::UserCommands', 'Base::OperNotices', 'JELP::Base']
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Reload;

use warnings;
use strict;

use utils qw(notice gnotice);

our ($api, $mod, $me, $pool);

# RELOAD command.
our %user_commands = (RELOAD => {
    code   => \&cmd_reload,
    desc   => 'reload the entire IRCd',
    params => '-oper(reload) @rest(opt)'
});

sub init {

    # allow RELOAD to work remotely.
    $mod->register_global_command(name => 'reload');

    # notices.
    $mod->register_oper_notice(
        name   => 'reload',
        format => '%s %s by %s (%s@%s)'
    ) or return;

    return 1;
}

sub cmd_reload {
    my ($user, $event, @rest) = @_;
    my ($verbose, $debug_verbose);

    # the second arg might be verbosity flags
    if (length $rest[1]) {
        $verbose++                      if $rest[1] =~ m/v/;
        $verbose++, $debug_verbose++    if $rest[1] =~ m/d/;
    }

    # server parameter?
    if (my $server_mask_maybe = shift @rest) {
        my @servers = $pool->lookup_server_mask($server_mask_maybe);

        # no priv.
        if (!$user->has_flag('greload')) {
            $user->numeric(ERR_NOPRIVILEGES => 'greload');
            return;
        }

        # no matches.
        if (!@servers) {
            $user->numeric(ERR_NOSUCHSERVER => $server_mask_maybe);
            return;
        }

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
            $location->fire_command(ircd_reload => $user, @$their_servers);
            $loc_done{$location}++;
        }

        # if $me is not in %done, we're not reloading locally.
        return 1 if !$done{$me};

    }

    my $old_v = $ircd::VERSION;
    my $prefix = $user->is_local ? '' : "[$$me{name}] ";

    # log to user if debug.
    my $cb;
    $cb = $::api->on(log => sub { $user->server_notice("$prefix- $_[1]") },
        name      => 'cmd.reload',
        permanent => 1 # we will remove it manually afterward
    ) if $debug_verbose;

    # redefine Evented::Object before anything else.
    $ircd::disable_warnings++;
    {
        no warnings 'redefine';
        do $_ foreach grep { /^Evented\/Object/ } keys %INC;
    }
    $ircd::disable_warnings--;

    # determine modules loaded beforehand.
    my @mods_loaded = @{ $api->{loaded} };
    my $num = scalar @mods_loaded;

    # put bases last.
    my $ircd = $api->get_module('ircd');
    my (@not_bases, @bases);
    foreach my $module (@mods_loaded) {

        # ignore ircd, unloaded modules, and submodules.
        next if $module == $ircd;
        next if $module->{UNLOADED};
        next if $module->{parent};

        my $is_base = $module->name =~ m/Base/;
        push @not_bases, $module if !$is_base;
        push @bases,     $module if  $is_base;
    }

    # reload ircd first, non-bases, then bases.
    #
    # 1. ircd       --  do the actual server upgrade
    # 2. non-bases  --  reload normal modules, allowing bases to react
    # 3. bases      --  reload bases, now that module.* events have been fired
    #
    $api->reload_module($ircd, @not_bases, @bases);
    my $new_v = ircd->VERSION;


    # module summary.
    $user->server_notice("$prefix- Module summary") if $verbose;
    my $reloaded = 0;
    foreach my $old_m (@mods_loaded) {
        my $new_m = $api->get_module($old_m->name);

        # not loaded.
        if (!$new_m) {
            $user->server_notice(
                "$prefix    - NOT LOADED: $$old_m{name}{full}"
            );
            next;
        }

        # version change.
        if ($new_m->{version} > $old_m->{version}) {
            $user->server_notice(
                "$prefix    - Upgraded: $$new_m{name}{full} ".
                "($$old_m{version} -> $$new_m{version})"
            ) if $verbose;
            next;
        }

        $reloaded++;
    }

    # find new modules.
    NEW: foreach my $new_m (@{ $api->{loaded} }) {
        foreach my $old_m (@mods_loaded) {
            next NEW if $old_m->name eq $new_m->name;
        }
        $user->server_notice(
            "$prefix    - Loaded: $$new_m{name}{full}"
        ) if $verbose;
    }

    $user->server_notice(
        "$prefix    - $reloaded modules reloaded and not upgraded"
    ) if $verbose;

    # difference in version.
    my $info;
    if ($new_v != $old_v) {
        my $amnt = sprintf('%.f', abs($new_v - $::VERSION) * 100);
        $info = "upgraded from $old_v to $new_v (up $amnt versions since start)";
    }
    else {
        $info = 'reloaded';
    }

    $::api->delete_callback('log', $cb->{name}) if $verbose;
    gnotice($user, reload => $me->name, $info, $user->notice_info);
    return 1;
}

$mod
