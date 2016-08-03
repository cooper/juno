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
use utils qw(import notice string_to_seconds pretty_time pretty_duration);

our ($api, $mod, $pool, $conf, $me);

our (
    $table,         # Evented::Database bans table
    %ban_types,     # registered ban types
    %ban_actions,   # registered ban actions
    %ban_timers,    # expiration timers
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
    $mod->load_submodule('Info')                            or return;

    # create or update the table.
    $table = $conf->table('bans')                           or return;
    $table->create_or_alter(@format);

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
        name => $action,
        id   => $action  # for now
    };

    L("'$action' registered");
    $mod_->list_store_add(ban_actions => $action);
    return $ban_actions{$action}{id};
}

# fetches a ban action identifier. this is used as a return type
# for enforcement functions.
sub get_ban_action {
    my ($mod_, $event, $action) = @_;
    return $ban_actions{ lc $action }{id};
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
    my @ban_ids = $table->rows->select('id');
    return map ban_by_id($_), @ban_ids;
}

# $ban = create_or_update_ban(%opts)
sub create_or_update_ban {
    my %opts = @_;

    # find or create ban.
    my $ban = ban_by_id($opts{id});
    if (!$ban) {
        $ban = M::Ban::Info->construct(%opts);
        return if !$ban;
    }

    # update ban info. this also validates.
    $ban->update(%opts) or return;

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

    $ban_table{$id} = $ban;
    return $ban;
}



#####################
### USER COMMANDS ###
################################################################################

# BANS user command.
our %user_commands = (BANS => {
    code   => \&ucmd_bans,
    desc   => 'list user or server bans',
    params => '-oper(list_bans)'
});

# TODO: make it possible to list only dlines, only klines, etc.
# then, make each type register an additional command which does that
sub ucmd_bans {
    my $user = shift;
    my @bans = get_all_bans();

    # no bans
    if (!@bans) {
        $user->server_notice(bans => 'No bans are set');
        return;
    }

    # list all bans
    $user->server_notice(bans => 'Listing all bans');
    foreach my $ban (sort { $a->{added} <=> $b->{added} } @bans) {
        my %ban = %$ban; my $type = uc $ban{type};
        my @lines = "\2$type\2 $ban{match} ($ban{id})";
        push @lines, '      Reason: '.$ban{reason}                  if length $ban{reason};
        push @lines, '       Added: '.pretty_time($ban->{added})    if $ban{added};
        push @lines, '     by user: '.$ban{auser}                   if length $ban{auser};
        push @lines, '   on server: '.$ban{aserver}                 if length $ban{aserver};
        push @lines, '    Duration: '.pretty_duration($ban{duration}) if  $ban{duration};
        push @lines, '    Duration: Permanent'                      if !$ban{duration};
        push @lines, '   Remaining: '.pretty_duration($ban->{expires} - time)  if $ban{expires};
        push @lines, '     Expires: '.pretty_time($ban->{expires})  if $ban{expires};
        $user->server_notice("- $_") for '', @lines;
    }
    $user->server_notice('- ');
    $user->server_notice(bans => 'End of ban list');

    return 1;
}

# if $duration is 0, the ban is permanent
sub handle_add_command {
    my ($type_name, $command, $user, $event, $duration, $match, $reason) = @_;
    my $type = $ban_types{$type_name} or return;
    my $what = ucfirst($type->{hname} || 'ban');
    $reason //= '';

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
    if (ban_by_type_match($type, $match)) {
        $user->server_notice($command => "$what for $match exists already");
        return;
    }

    # TODO: check if it matches too many people

    # register: validate, update, enforce, activate
    my %ban = create_my_ban($type_name,
        match        => $match,
        reason       => $reason,
        duration     => $seconds,
        auser        => $user->fullreal,
        _just_set_by => $user->id
    );

    # returned nothing
    if (!%ban) {
        $what = $type->{hname} || 'ban';
        $user->server_notice($command => "Invalid $what");
        return;
    }

    notify_new_ban($user, %ban);
    return 1;
}

# register a ban right now from this server
sub create_my_ban {
    my ($type_name, %opts) = @_;
    $opts{id} //= get_next_id();

    # validate, update, enforce, activate
    my %ban = add_update_enforce_activate_ban(
        type    => $type_name,
        aserver => $me->name,
        %opts
    ) or return;

    # forward it
    $pool->fire_command_all(baninfo => \%ban);

    return %ban;
}

# $match can be a mask or a ban ID
sub handle_del_command {
    my ($type_name, $command, $user, $event, $match) = @_;
    my $type = $ban_types{$type_name} or return;

    # find the ban
    my %ban = ban_by_id($match);
    if (!%ban) { %ban = ban_by_type_match($type, $match) }
    if (!%ban) {
        my $what = $type->{hname} || 'ban';
        $user->server_notice($command => "No $what matches");
        return;
    }

    # remove it
    $ban{_just_set_by} = $user->id;
    delete_deactivate_ban_by_id($ban{id});
    $pool->fire_command_all(bandel => \%ban);

    notify_delete_ban($user, %ban);
    return 1;
}

##############
### TIMERS ###
################################################################################

# activate a ban timer
sub activate_ban {
    my %ban = @_;
    my $type = $ban_types{ $ban{type} } or return;

    # Custom activation
    # -----------------
    $type->{activate_code}(\%ban) if $type->{activate_code};

    # Expiration
    # -----------------

    # it's permanent
    my $lifetime = $ban{lifetime} || $ban{expires};
    return if !$lifetime;

    # it has already expired
    if ($lifetime <= time) {
        expire_ban(%ban);
        return;
    }

    # it has expired, but we're keeping it a while
    elsif ($ban{expires} <= time) {
        $ban{inactive} = 1;
    }

    # create a timer
    my $timer = $timers{ $ban{id} } ||= IO::Async::Timer::Absolute->new(
        time      => $lifetime,
        on_expire => sub { expire_ban(%ban) }
    );

    # start timer
    if (!$timer->is_running) {
        $timer->start;
        $::loop->add($timer);
    }

    return %ban;
}

# deactivate a ban timer
sub deactivate_ban {
    my %ban = @_;

    # dispose of the timer
    if (my $timer = $timers{ $ban{id} }) {
        $timer->stop;
        $timer->remove_from_parent;
        delete $timers{ $ban{id} };
    }

    return %ban;
}

# deactivate and remove ban from database
sub expire_ban {
    my %ban = @_;
    my $type = $ban_types{ $ban{type} } or return;

    # Custom activation
    # -----------------
    $type->{disable_code}(\%ban) if $type->{disable_code};

    # deactive the timer
    deactivate_ban(%ban);

    # remove from database
    delete_ban_by_id($ban{id});

    notice("$ban{type}_expire" =>
        ucfirst($type->{hname} || 'ban'),
        $ban{match},
        pretty_duration(time - $ban{added}),
        length $ban{reason} ? $ban{reason} : 'no reason'
    ) if !$ban{inactive};
}

###################
### ENFORCEMENT ###
################################################################################

sub add_enforcement_events {

    # new connection, host resolved, ident found
    my $enforce_on_conn = sub { enforce_all_on_conn(shift) };
    $pool->on("connection.$_" => $enforce_on_conn, 'ban.enforce.conn')
        for qw(new found_hostname found_ident);

    # new local user
    # this is done before sending welcomes or propagating the user
    $pool->on('connection.user_ready' => sub {
        my ($conn, $event, $user) = @_;
        enforce_all_on_user($user);
    }, 'ban.enforce.user');

}

# Enforce all bans on a single entity
# -----

# enforce ball bans on a user
sub enforce_all_on_user {
    my $user = shift;
    foreach my $ban (get_all_bans()) {
        my $type = $ban_types{ $ban->{type} };
        next unless $type->{user_code};
        return 1 if enforce_ban_on_user($ban, $user);
    }
    return;
}

# enforce all bans on a connection
sub enforce_all_on_conn {
    my $conn = shift;
    foreach my $ban (get_all_bans()) {
        my $type = $ban_types{ $ban->{type} };
        next unless $type->{conn_code};
        return 1 if enforce_ban_on_conn($ban, $conn);
    }
    return;
}

# Enforce a single ban on all entities
# -----

sub enforce_ban {
    my %ban = @_;
    return if $ban{inactive};
    my $type = $ban_types{ $ban{type} } or return;

    my @a;
    push @a, enforce_ban_on_users(%ban) if $type->{user_code};
    push @a, enforce_ban_on_conns(%ban) if $type->{conn_code};

    return @a;
}

# enforce a ban on all connections
sub enforce_ban_on_conns {
    my %ban = @_;
    return if $ban{inactive};
    my $type = $ban_types{ $ban{type} } or return;
    my @affected;

    foreach my $conn ($pool->connections) {
        my $affected = enforce_ban_on_conn(\%ban, $conn);
        push @affected, $conn if $affected;
    }

    return @affected;
}

# enforce a ban on a single connection
sub enforce_ban_on_conn {
    my ($ban, $conn) = @_;
    return if $ban->{inactive};

    # check that the connection matches
    my $type = $ban_types{ $ban->{type} } or return;
    my $action = $type->{conn_code}->($conn, $ban);

    # find the action code
    return if !$action;
    my $enforce = $ban_actions{$action}{conn_code} or return;

    # do the action
    return $enforce->($conn, $ban, $type);
}

# enforce a ban on all local users
sub enforce_ban_on_users {
    my %ban = @_;
    return if $ban{inactive};
    my $type = $ban_types{ $ban{type} } or return;
    my @affected;

    foreach my $user ($pool->local_users) {
        my $affected = enforce_ban_on_user(\%ban, $user);
        push @affected, $user if $affected;
    }

    return @affected;
}

# enforce a ban on a single user
sub enforce_ban_on_user {
    my ($ban, $user) = @_;
    return if $ban->{inactive};

    # check that the user matches
    my $type = $ban_types{ $ban->{type} } or return;
    my $action = $type->{user_code}->($user, $ban);

    # find the action code
    return if !$action;
    my $enforce = $ban_actions{$action}{user_code} or return;

    # do the action
    return $enforce->($user, $ban, $type);
}

############################
### Built-in ban actions ###
################################################################################

sub ban_action_kill {
    my ($conn_user, $ban, $type) = @_;

    # find the connection
    $conn_user = $conn_user->conn if $conn_user->can('conn');
    $conn_user or return;

    # like "Banned" or "Banned: because"
    my $reason = $type->{reason};
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

$mod
