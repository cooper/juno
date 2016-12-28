# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-MacBook-Pro.local
# Sat Feb 14 17:58:20 EST 2015
# Ban.pm
#
# @name:            'Ban'
# @package:         'M::Ban'
# @description:     'provides an interface for user and server banning'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
# @depends.modules: ['Base::UserCommands', 'Base::OperNotices']
#
package M::Ban;

use warnings;
use strict;
use 5.010;

use IO::Async::Timer::Absolute;
use Scalar::Util qw(weaken);
use utils qw(notice string_to_seconds pretty_time pretty_duration);

our ($api, $mod, $pool, $conf, $me);
my $loop;
my $debug;

our (
    $table,         # Evented::Database bans table
    %ban_types,     # registered ban types
    %ban_actions,   # registered ban actions
    %ban_timers,    # expiration timers
    %ban_enforces,  # bans with enforcement active
    %ban_table      # ban objects stored in memory
);

# Evented::Database bans table format
my %unordered_format = our @format = (
    id          => 'TEXT',
    type        => 'TEXT',
    match       => 'TEXT COLLATE NOCASE',
    duration    => 'INTEGER',
    added       => 'INTEGER',
    modified    => 'INTEGER',
    expires     => 'INTEGER',
    lifetime    => 'INTEGER',
    aserver     => 'TEXT',
    auser       => 'TEXT',
    reason      => 'TEXT'
);

sub init {

    # create or update the table.
    $table = $conf->table('bans')                           or return;
    $table->create_or_alter(@format);

    # load ban object and find loop.
    $mod->load_submodule('Info')                            or return;
    $loop = $ircd::loop                                     or return;

    # ban API.
    $mod->register_module_method('register_ban_type')       or return;
    $mod->register_module_method('register_ban_action')     or return;
    $mod->register_module_method('get_ban_action')          or return;
    $api->on('module.unload' => \&unload_module, 'void.ban.types');

    # add protocol submodules.
    $mod->add_companion_submodule('JELP::Base', 'JELP');
    $mod->add_companion_submodule('TS6::Base',  'TS6');

    # this module provides the 'kill' action.
    register_ban_action($mod, undef,
        name      => 'kill',
        user_code => \&ban_action_kill,
        conn_code => \&ban_action_kill
    );

    # add hooks for enforcing bans
    add_enforcement_events();

    # initial activation
    # note that this likely does nothing during boot, but it will be called
    # again for each ban type as they are registered.
    $_->activate for all_bans();

    return 1;
}

###############
### BAN API ###
################################################################################

# register_ban_type()
#
# name          name of the ban type
#
# hname         human-readable name of the ban type
#
# command       user command for add/deleting bans
#
# reason        default ban reason
#
# match_code    code that takes a string input as an argument and returns a string
#               for storage in the ban table or undef if the input was invalid
#
# add_cmd       (optional) name of user command to add a ban of this type
#
# del_cmd       (optional) name of user command to delete a ban of this type
#
# user_code     (optional) code which determines whether a user matches a ban.
#               if not specified, this ban type does not apply to users.
#               it must return a ban action identifier.
#
# conn_code     (optional) code which determines whether a conn matches a ban.
#               if not specified, this ban type does not apply to connections.
#               it must return a ban action identifier.
#
# disable_code  (optional) code which is called when a ban is diabled. this is
#               useful if the ban type requires manual enforcement deactivation.
#
sub register_ban_type {
    my ($mod_, $event, %opts) = @_;
    my $type_name = lc $opts{name} or return;

    # register add command.
    my $command1 = $opts{add_cmd};
    if (length $command1) {
        $command1 = uc $command1;
        $mod_->register_user_command_new(
            name        => $command1,
            code        => sub { handle_add_command($type_name, $command1, @_) },
            description => "add to $type_name ban list",
            parameters  => "-oper($type_name) *        *     :rest(opt)"
                                            # duration match :reason
        );
    }

    # register delete command.
    my $command2 = $opts{del_cmd};
    if (length $command2) {
        $command2 = uc $command2;
        $mod_->register_user_command_new(
            name        => $command2,
            code        => sub { handle_del_command($type_name, $command2, @_) },
            description => "delete from $type_name ban list",
            parameters  => "-oper($type_name) *" # ban ID | match
        );
    }

    # oper notices.
    $mod_->register_oper_notice(
        name   => $type_name,
        format => '%s for %s added by %s, will expire %s (%s) [%s]'
    );
    $mod_->register_oper_notice(
        name   => "${type_name}_delete",
        format => '%s for %s deleted by %s [%s]'
    );
    $mod_->register_oper_notice(
        name   => "${type_name}_expire",
        format => '%s for %s expired after %s [%s]'
    );

    # store this type.
    $ban_types{$type_name} = {
        %opts,
        name => $type_name
    };

    L("$type_name registered");
    $mod_->list_store_add(ban_types => $type_name);

    # initial activation
    $_->activate for all_bans(type => $type_name);

    return 1;
}

# registers a ban action.
sub register_ban_action {
    my ($mod_, $event, %opts) = @_;

    # check for required info
    my $action = lc $opts{name} or return;

    # store this action.
    $ban_actions{$action} = {
        %opts,
        name => $action
    };

    L("'$action' registered");
    $mod_->list_store_add(ban_actions => $action);
    return $ban_actions{$action}{name};
}

# fetches a ban action identifier. this is used as a return type
# for enforcement functions.
sub get_ban_action {
    my ($mod_, $event, $action_name) = @_;
    return $action_name if ref $action_name;
    my $action = $ban_actions{ lc $action_name } or return;
    return $action;
}

########################
### High-level stuff ###
################################################################################

# @bans = all_bans()
#
# consider: could make this a bit more efficient with ->select_hash() and
# ->construct() instead of using ban_by_id() which queries the db for each one
#
sub all_bans {
    my @ban_ids = $table->rows(@_)->select('id');
    return map ban_by_id($_), @ban_ids;
}

# @bans = enforceable_bans()
# returns bans with enforcement enabled.
sub enforceable_bans {
    return grep $_, values %ban_enforces;
}

# $ban = create_or_update_ban(%opts)
sub create_or_update_ban {
    my %opts = @_;
    return if $opts{match} eq '*';

    # find or create ban.
    my $ban = ban_by_id($opts{id});
    if (!$ban) {
        $ban = M::Ban::Info->construct(%opts);
        return if !$ban;
    }

    # for existing bans, do not accept this unless the modification time
    # is newer than what we already know.
    else {
        my $deleted = $ban->has_expired && $ban->expires == $ban->modified;
        return if !$deleted && $ban->modified <= ($opts{modified} || 'inf');
    }

    # update ban info. this also validates.
    $ban->update(%opts) or return;

    # store in the ban table.
    _store_ban($ban);

    # activate the ban.
    $ban->activate;

    return $ban;
}

# $ban = ban_by_id($id)
sub ban_by_id {
    my $id = shift;

    # find it in the symbol table
    my $ban = $ban_table{$id};

    # find it in the database.
    $ban ||= M::Ban::Info->construct_by_id($id);
    $ban or return;

    _store_ban($ban);
    return $ban;
}

# $ban = ban_by_user_input($type_name, $match)
sub ban_by_user_input {
    my ($type_name, $match) = @_;
    return $ban_table{$match} || $ban_table{ "$type_name/$match" };
}

# store ban in ban table
sub _store_ban {
    my $ban = shift;
    $ban_table{ $ban->id } = $ban;
    $ban_table{ $ban->type.'/'.$ban->match } = $ban;
}

# remove ban from ban table
sub _destroy_ban {
    my $ban = shift;
    delete $ban_table{ $ban->id };
    delete $ban_table{ $ban->type.'/'.$ban->match };
}

#####################
### USER COMMANDS ###
################################################################################

# BANS user command.
our %user_commands = (BANS => {
    code   => \&ucmd_bans,
    desc   => 'list global bans',
    params => '-oper(list_bans) *(opt) *(opt)'
});

# BANS command
sub ucmd_bans {
    my ($user, $event, $only_show, $flags) = @_;

    # e.g. /bans -a
    if (!length $flags && length $only_show && !index($only_show, '-')) {
        $flags = $only_show;
        undef $only_show;
    }

    # get optional flags
    # a = show all, even expired
    my %opts = map { $_ => 1 } split //, $flags if length $flags;

    # pick and sort bans
    my @bans = sort { $a->added <=> $b->added } grep {
        my $type_ok   = length $only_show ? lc $_->type eq $only_show : 1;
        my $expire_ok = $opts{a} || !$_->has_expired;
        $type_ok && $expire_ok
    } all_bans();

    # no bans match
    if (!@bans) {
        $user->server_notice(bans => 'No matching bans');
        return;
    }

    # list all bans
    my $n = scalar @bans;
    $only_show = length $only_show ? uc $only_show : 'ban';
    $user->server_notice(bans => "Listing all ${only_show}s");
    foreach my $ban (@bans) {

        my $type = uc $ban->type;
        my @lines = "\2$type\2 $$ban{match} ($$ban{id})";

push @lines, '      Reason: '.$ban->reason          if length $ban->reason;
push @lines, '       Added: '.$ban->hr_added        if $ban->added;
push @lines, '     by user: '.$ban->auser           if length $ban->auser;
push @lines, '   on server: '.$ban->aserver         if length $ban->aserver;
push @lines, '    Duration: '.ucfirst($ban->hr_duration);
                                      if (!$ban->has_expired && $ban->expires) {
push @lines, '   Remaining: '.$ban->hr_remaining;
push @lines, '     Expires: '.$ban->hr_expires;    } elsif ($ban->has_expired) {
push @lines, '     EXPIRED: '.$ban->hr_expires;
push @lines, '  Deletes in: '.$ban->hr_remaining_lifetime;
push @lines, '     on date: '.$ban->hr_lifetime;                               }

        $user->server_notice("- $_") for '', @lines;
    }

    $user->server_notice('- ');
    $user->server_notice(bans => "End of $only_show list ($n total)");

    return 1;
}

# if $duration is 0, the ban is permanent
sub handle_add_command {
    my ($type_name, $command, $user, $event, $duration, $match, $reason) = @_;
    my $type = $ban_types{$type_name} or return;
    my $what = ucfirst($type->{hname} || 'ban');

    # check that the duration is numeric
    my $seconds = string_to_seconds($duration);
    if (!defined $seconds) {
        $user->server_notice($command => 'Invalid duration format');
        return;
    }

    # check if matcher is valid
    $match = $type->{match_code}->($match);
    if (!defined $match) {
        $user->server_notice($command => "Invalid $what format");
        return;
    }

    # check if the ban exists already
    if (my $exists = ban_by_user_input($type_name, $match)) {

        # if it is expired, we will overwrite it.
        if (!$exists->has_expired) {
            $user->server_notice($command => "$what for $match exists already");
            return;
        }
    }

    # TODO: check if it matches too many people

    # register: validate, update, enforce, activate
    my $ban = create_my_ban(
        type          => $type_name,
        match         => $match,
        reason        => $reason,
        duration      => $seconds,
        auser         => $user->fullreal,
        recent_source => $user
    ) or return;

    # returned nothing
    if (!$ban) {
        $what = $type->{hname} || 'ban';
        $user->server_notice($command => "Invalid $what");
        return;
    }

    $ban->notify_new($user);
    return 1;
}

# register a ban right now from this server
sub create_my_ban {
    my %opts = @_;
    $opts{id} //= get_next_id();
    my $source = delete $opts{recent_source};

    # validate, update, enforce, activate
    my $ban = create_or_update_ban(
        aserver => $me->name,
        %opts
    ) or return;

    # say where it came from
    $ban->set_recent_source($source) if $source;

    # forward it
    $pool->fire_command_all(baninfo => $ban);

    return $ban;
}

# $match can be a mask or a ban ID
sub handle_del_command {
    my ($type_name, $command, $user, $event, $match) = @_;
    my $type = $ban_types{$type_name} or return;
    my $what = $type->{hname} || 'ban';

    # find the ban by ID or matcher
    my $ban = ban_by_user_input($type_name, $match);
    if (!$ban) {
        $user->server_notice($command => "No $what matches");
        return;
    }

    # the ban is already expired but has still has lifetime.
    # this has either already expired or already been deleted.
    if ($ban->has_expired && !$ban->has_expired_lifetime) {
        $user->server_notice($command => "$what has already been deleted");
        return;
    }

    # disable it
    $ban->disable;
    $ban->set_recent_source($user);
    $pool->fire_command_all(bandel => $ban);

    $ban->notify_delete($user);
    return 1;
}

#############################
### BAN OBJECT MANAGEMENT ###
################################################################################

sub _activate_ban_timer {
    my $ban = shift;
    my $expire_time;

    # do nothing if the ban is permanent.
    my $expires  = $ban->expires;
    my $lifetime = $ban->lifetime || $expires;
    return if !$expires;

    # if the ban has not expired, add a timer to expire it.
    if ($expires && !$ban->has_expired) {
        $expire_time = $expires;
    }

    # if the ban has expired but its lifetime has not, add a timer to delete it.
    elsif ($lifetime && !$ban->has_expired_lifetime) {
        $expire_time = $lifetime;
    }

    # if both have expired, delete the ban.
    else {
        _expire_ban($ban);
        return; # indicates that it was immediately expired
    }

    # add the timer otherwise.
    my $id = $ban->id;
    my $timer = $ban_timers{$id} = IO::Async::Timer::Absolute->new(
        time      => $expire_time,
        on_expire => sub {
            my $ban = ban_by_id($id) or return;
            _expire_ban($ban);
        }
    );
    $timer->start;
    $loop->add($timer);

    return 1; # indicates that a timer was activated
}

sub _deactivate_ban_timer {
    my $ban = shift;

    # find the timer.
    my $timer = delete $ban_timers{ $ban->id } or return;

    # stop it and remove it from the loop.
    $timer->stop;
    $timer->remove_from_parent;

    return 1;
}

# called when the ban should be expired but not deleted.
sub _expire_ban {
    my $ban = shift;

    # delete the ban.
    if ($ban->has_expired_lifetime) {
        $ban->destroy;
    }

    # disable the ban.
    # this also will activate the timer for deletion.
    else {
        $ban->disable;
    }

    # notify if it expired but not if it was only deleted
    notice("$$ban{type}_expire" =>
        ucfirst($ban->type('hname') || 'ban'),
        $ban->match,
        pretty_duration(time - $ban->added),
        $ban->hr_reason
    ) if ($ban->lifetime == $ban->expires) || !$ban->has_expired_lifetime;

    return 1;
}

# enable enforcement
# internal use only - called from Info
sub _activate_ban_enforcement {
    my $ban = shift;
    # $ban->activate_enforcement calls ->enforce to enforce the ban immediately,
    # so we don't have to
    weaken($ban_enforces{ $ban->id } = $ban);
}

# disable enforcement
# internal use only - called from Info
sub _deactivate_ban_enforcement {
    my $ban = shift;
    delete $ban_enforces{ $ban->id };
}

###################
### ENFORCEMENT ###
################################################################################

sub add_enforcement_events {

    # new connection, host resolved, or ident found
    my $enforce_on_conn = sub {
        my $conn = shift;
        foreach my $ban (enforceable_bans()) {
            $ban->type('conn_code') or next;
            return 1 if $ban->enforce_on_conn($conn);
        }
        return;
    };
    $pool->on("connection.$_" => $enforce_on_conn, "ban.enforce.conn.$_")
        for qw(new found_hostname found_ident);

    # new local user
    # this is done before sending welcomes or propagating the user
    $pool->on('connection.user_ready' => sub {
        my (undef, undef, $user) = @_;
        foreach my $ban (enforceable_bans()) {
            $ban->type('user_code') or next;
            return 1 if $ban->enforce_on_user($user);
        }
        return;
    }, 'ban.enforce.user');

}

############################
### Built-in ban actions ###
################################################################################

# ban actions must return true if they were effective

# ban action to kill a user or connection
sub ban_action_kill {
    my ($conn_user, $ban) = @_;

    # find the connection
    $conn_user = $conn_user->conn if $conn_user->can('conn');
    $conn_user or return;

    # like "Banned" or "Banned: because"
    my $reason = $ban->type('reason');
    $reason .= ": $$ban{reason}" if length $ban->{reason};

    # terminate it
    $conn_user->done($reason);
    return 1;
}

################
### DISPOSAL ###
################################################################################

sub delete_ban_type {
    my $type_name = lc shift;
    my $type = delete $ban_types{$type_name} or return;
    L("$type_name unloaded");
}

sub delete_ban_action {
    my $action = lc shift;
    delete $ban_actions{$action} or return;
    L("$action unloaded");
}

sub unload_module {
    my $mod_ = shift;
    delete_ban_type($_)   foreach $mod_->list_store_items('ban_types');
    delete_ban_action($_) foreach $mod_->list_store_items('ban_actions');
}

# return the next available ban ID
sub get_next_id {
    my $id = $table->meta('last_id');
    $table->set_meta(last_id => ++$id);
    return "$$me{sid}.$id";
}

# debug
sub D {
    return if !$debug;
    L(@_);
}

$mod
