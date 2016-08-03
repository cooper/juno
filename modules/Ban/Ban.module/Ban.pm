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
use utils qw(import notice string_to_seconds);

our ($api, $mod, $pool, $conf, $me);
our ($table, %ban_types, %timers, %ban_actions);

my %unordered_format = my @format = (
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

# specification
# -----
#
#   RECORDED IN DATABASE
#
# id            ban identifier
#
#               IDs are unique globally, not just per server or per ban type
#               in the format of <server ID>.<local ID>
#               where <server ID> is the SID of the server on which the ban was created
#               and <local ID> is a numeric ID of the ban which is specific to that server
#               e.g. 0.1
#
# type          string representing type of ban
#               e.g. kline, dline, ...
#
# match         mask or string to match
#               string representing what to match
#               e.g. *@example.com, 127.0.0.*, ...
#
# duration      duration of ban in seconds
#               or 0 if the ban is permanent
#               e.g. 300 (5 minutes)
#
# added         UTC timestamp when the ban was added
#
# modified      UTC timestamp when the ban was last modified
#
# expires       UTC timestamp when ban will expire and no longer be in effect
#               or 0 if the ban is permanent
#
# lifetime      UTC timestamp when ban should be removed from the database
#               or nothing/0 if it is the same as 'expires'
#
# auser         mask of user who added the ban
#               e.g. someone!someone[@]somewhere
#
# aserver       name of server where ban was added
#               e.g. s1.example.com
#
# reason        user-set reason for ban
#
#   NOT RECORDED IN DATABASE
#
# inactive      set by activate_ban() so that we know not to enforce an
#               expired ban
#
# _just_set_by  SID/UID of who set a ban. used for propagation
#
sub init {
    $table = $conf->table('bans') or return;

    # create or update the table.
    $table->create_or_alter(@format);

    # ban API.
    $mod->register_module_method('register_ban_type')   or return;
    $mod->register_module_method('register_ban_action') or return;
    $mod->register_module_method('get_ban_action')      or return;
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

    # initial activation
    add_enforcement_events();
    activate_ban(%$_) foreach get_all_bans();

    return 1;
}

# time prettifiers
my $t = sub { scalar localtime shift };
my $d = sub {
    my $secs = shift;
    if ($secs >= 365*24*60*60) { return sprintf '%.1fy', $secs/(365*24*60*60) }
    elsif ($secs >= 24*60*60)  { return sprintf '%.1fd', $secs/(24*60*60) }
    elsif ($secs >= 60*60)     { return sprintf '%.1fh', $secs/(60*60) }
    elsif ($secs >= 60)        { return sprintf '%.1fm', $secs/(60) }
    return sprintf '%.1fs', $secs;
};

###############
### BAN API ###
################################################################################

# register_ban_type()
#
# name          name of the ban type
#
# command       user command for add/deleting bans
#
# match_code    code that takes a string input as an argument and returns a string
#               for storage in the ban table or undef if the input was invalid
#
# user_code     (optional) code which determines whether a user matches a ban.
#               if not specified, this ban type does not apply to users.
#               it must return a ban action identifier.
#
# conn_code     (optional) code which determines whether a conn matches a ban.
#               if not specified, this ban type does not apply to connections.
#               it must return a ban action identifier.
#
# reason        default ban reason
#
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

sub validate_ban {
    my %ban = @_;

    # check for required keys
    defined $ban{$_} or return for qw(id type match duration);

    # inject missing keys
    $ban{added}     ||= time;
    $ban{modified}  ||= $ban{added};
    $ban{expires}   ||= $ban{duration} ? time + $ban{duration} : 0;
    $ban{lifetime}  ||= $ban{expires};

    return %ban;
}

# register a ban right now from this server
sub register_ban {
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

sub add_update_enforce_activate_ban {

    # validate it
    my %ban = validate_ban(@_);
    if (!%ban) {
        L("validate_ban() failed!");
        return;
    }

    # ignore bans with older modification times
    my %existing = ban_by_id($ban{id});
    if ($existing{modified} && $existing{modified} > $ban{modified}) {
        L("ignoring older ban on $ban{match}");
        return;
    }

    # add, update, enforce, and activate it
    add_or_update_ban(%ban);
    enforce_ban(%ban);
    activate_ban(%ban);

    return %ban;
}

# despire the name, this does NOT delete the ban from the database.
# it deactivates it and changes the expire time so that it will not be enforced.
sub delete_deactivate_ban_by_id {
    my $id = shift;
    my %ban = ban_by_id($id) or return;

    # update the expire time
    if ($ban{modified} < time) {
        $ban{modified} = time;
    }
    else {
        $ban{modified}++;
    }
    $ban{expires} = $ban{modified};

    # reactivate the ban timer
    %ban = deactivate_ban(%ban);
    %ban = activate_ban(%ban);

    # update the ban in the db
    add_or_update_ban(%ban);

    return %ban;
}

# notify opers of a new ban
sub notify_new_ban {
    my ($source, %ban) = @_;
    my @user = $source if $source->isa('user') && $source->is_local;
    notice(@user, $ban{type} =>
        ucfirst($ban_types{ $ban{type} }{hname} || 'ban'),
        $ban{match},
        $source->notice_info,
        $ban{expires}  ? $t->($ban{expires})        : 'never',
        $ban{duration} ? 'in '.$d->($ban{duration}) : 'permanent',
        length $ban{reason} ? $ban{reason}          : 'no reason'
    );
}

# notify opers of a deleted ban
sub notify_delete_ban {
    my ($source, %ban) = @_;
    my @user = $source if $source->isa('user') && $source->is_local;
    notice(@user, "$ban{type}_delete" =>
        ucfirst($ban_types{ $ban{type} }{hname} || 'ban'),
        $ban{match},
        $source->notice_info,
        length $ban{reason} ? $ban{reason} : 'no reason'
    );
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
        push @lines, '       Added: '.$t->($ban->{added})           if $ban{added};
        push @lines, '     by user: '.$ban{auser}                   if length $ban{auser};
        push @lines, '   on server: '.$ban{aserver}                 if length $ban{aserver};
        push @lines, '    Duration: '.$d->($ban{duration})          if  $ban{duration};
        push @lines, '    Duration: Permanent'                      if !$ban{duration};
        push @lines, '   Remaining: '.$d->($ban->{expires} - time)  if $ban{expires};
        push @lines, '     Expires: '.$t->($ban->{expires})         if $ban{expires};
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
    my %ban = register_ban($type_name,
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

################
### DATABASE ###    Low-level bandb functions
################################################################################

# return the next available ban ID
sub get_next_id {
    my $id = $table->meta('last_id');
    $table->set_meta(last_id => ++$id);
    return "$$me{sid}.$id";
}

# returns all bans as a list of hashrefs.
sub get_all_bans {
    $table->rows->select_hash;
}

# look up a ban by an ID
sub ban_by_id {
    my %ban = $table->row(id => shift)->select_hash;
    return %ban;
}

# look up a ban by a matcher
sub ban_by_match {
    my %ban = $table->row(match => shift)->select_hash;
    return %ban;
}

# look up a ban by a matcher and type
sub ban_by_type_match {
    my %ban = $table->row(type => shift, match => shift)->select_hash;
    return %ban;
}

# insert or update a ban
sub add_or_update_ban {
    my %ban = @_;
    delete @ban{ grep !$unordered_format{$_}, keys %ban };
    $table->row(id => $ban{id})->insert_or_update(%ban);
}

# delete a ban
sub delete_ban_by_id {
    my $id = shift;
    $table->row(id => $id)->delete;
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
    $type->{expire_code}(\%ban) if $type->{expire_code};

    # deactive the timer
    deactivate_ban(%ban);

    # remove from database
    delete_ban_by_id($ban{id});

    notice("$ban{type}_expire" =>
        ucfirst($type->{hname} || 'ban'),
        $ban{match},
        $d->(time - $ban{added}),
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

$mod
