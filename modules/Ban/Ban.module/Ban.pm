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
our ($table, %ban_types, %timers);

my %unordered_format = my @format = (
    id          => 'TEXT',
    type        => 'TEXT',
    match       => 'TEXT COLLATE NOCASE',
    duration    => 'INTEGER',
    added       => 'INTEGER',
    modified    => 'INTEGER',
    expires     => 'INTEGER',
    aserver     => 'TEXT',
    auser       => 'TEXT',
    reason      => 'TEXT'
);

# specification
# -----
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
# expires       UTC timestamp when ban will expire
#               or 0 if the ban is permanent
#
# auser         mask of user who added the ban
#               e.g. someone!someone[@]somewhere
#
# aserver       name of server where ban was added
#               e.g. s1.example.com
#
# reason        user-set reason for ban
#
# _just_set_by  UID of user who set a ban. used for propagation.
#
# deleted       passed to expire_ban() when the ban was deleted, to
#               prevent expiration oper notices from being sent out
#
sub init {
    $table = $conf->table('bans') or return;

    # create or update the table.
    $table->create_or_alter(@format);

    # ban API.
    $mod->register_module_method('register_ban_type') or return;
    $api->on('module.unload' => \&unload_module, with_eo => 1) or return;

    # add protocol submodules.
    $mod->add_companion_submodule('JELP::Base', 'JELP');
    $mod->add_companion_submodule('TS6::Base',  'TS6');

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
    return sprintf '%.1fs';
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
# reason        default ban reason
#
# note: $mod_ refers to the module calling the method
# TODO: when Ban module is unloaded, delete everything registered by other modules
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
        format => 'Ban for %s added by %s, will expire %s (%s) [%s]'
    );
    $mod_->register_oper_notice(
        name   => "${type_name}_delete",
        format => 'Ban for %s deleted by %s [%s]'
    );
    $mod_->register_oper_notice(
        name   => "${type_name}_expire",
        format => 'Ban for %s expired after %s [%s]'
    );

    # store this type.
    $ban_types{$type_name} = {
        %opts,
        name => $type_name
    };

    L("$type_name registered");
    $mod_->list_store_add(ban_types => $type_name);
}

########################
### High-level stuff ###
################################################################################

sub validate_ban {
    my %ban = @_;

    # check for required keys
    defined $ban{$_} or return for qw(id type match duration);

    # inject missing keys
    my %inject = (
        added        => time,
        modified     => time,
        expires      => $ban{duration} ? time + $ban{duration} : 0
    );
    $ban{$_} //= $inject{$_} for keys %inject;

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
    my %ban = validate_ban(@_);
    if (!%ban) {
        L("validate_ban() failed!");
        return;
    }
    add_or_update_ban(%ban);
    enforce_ban(%ban);
    activate_ban(%ban);
    return %ban;
}

# notify opers of a new ban
sub notify_new_ban {
    my ($source, %ban) = @_;
    my @user = $source if $source->isa('user') && $source->is_local;
    notice(@user, $ban{type} =>
        $ban{match}, $source->notice_info,
        $ban{expires}  ? localtime $ban{expires}  : 'never',
        $ban{duration} ? "$ban{duration}s"        : 'permanent',
        length $ban{reason} ? $ban{reason}        : 'no reason'
    );
}

# notify opers of a deleted ban
sub notify_delete_ban {
    my ($source, %ban) = @_;
    my @user = $source if $source->isa('user') && $source->is_local;
    notice(@user, "$ban{type}_delete" =>
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
        $user->server_notice($command => 'Invalid ban format');
        return;
    }

    # check if the ban exists already
    if (ban_by_type_match($type, $match)) {
        $user->server_notice($command => "Ban for $match exists already");
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
        $user->server_notice($command => 'Invalid ban');
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
        $user->server_notice($command => 'No ban matches');
        return;
    }

    # delete it
    $ban{_just_set_by} = $user->id;
    delete_ban_by_id($ban{id});
    expire_ban(%ban, deleted => 1);
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

    # it's permanent
    return if !$ban{expires};

    # it has already expired
    if ($ban{expires} <= time) {
        expire_ban(%ban);
        return;
    }

    # create a timer
    my $timer = $timers{ $ban{id} } ||= IO::Async::Timer::Absolute->new(
        time      => $ban{expires},
        on_expire => sub { expire_ban(%ban) }
    );

    # start timer
    if (!$timer->is_running) {
        $timer->start;
        $::loop->add($timer);
    }

}

# deactivate a ban timer
# this is also called when a ban is deleted
# but with deleted => 1
sub expire_ban {
    my %ban = @_;

    # dispose of the timer
    if (my $timer = $timers{ $ban{id} }) {
        $timer->stop;
        $timer->remove_from_parent;
        delete $timers{ $ban{id} };
    }

    # remove from database
    delete_ban_by_id($ban{id});

    notice("$ban{type}_expire" =>
        $ban{match},
        $d->(time - $ban{added}),
        length $ban{reason} ? $ban{reason} : 'no reason'
    ) unless $ban{deleted};
}

###################
### ENFORCEMENT ###
################################################################################

sub add_enforcement_events {

    # new connection, host resolved, ident found
    my $enforce_on_conn = sub { enforce_all_on_conn(shift) };
    $pool->on("connection.$_" => $enforce_on_conn,
        name    => 'ban.enforce.conn',
        with_eo => 1
    ) for qw(new found_hostname found_ident);

    # new local user
    # this is done before sending welcomes or propagating the user
    $pool->on('connection.user_ready' => sub {
        my ($event, $user) = @_;
        enforce_all_on_user($user);
    }, name => 'ban.enforce.user');

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
    my $type = $ban_types{ $ban{type} } or return;

    my @a;
    push @a, enforce_ban_on_users(%ban) if $type->{user_code};
    push @a, enforce_ban_on_conns(%ban) if $type->{conn_code};

    return @a;
}

# enforce a ban on all connections
sub enforce_ban_on_conns {
    my %ban = @_;
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
    my $type = $ban_types{ $ban->{type} } or return;
    return unless $type->{conn_code}->($conn, $ban);

    # like "Banned" or "Banned: because"
    my $reason = $type->{reason};
    $reason .= ": $$ban{reason}" if length $ban->{reason};

    $conn->done($reason);
    return 1;
}

# enforce a ban on all local users
sub enforce_ban_on_users {
    my %ban = @_;
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
    my $type = $ban_types{ $ban->{type} } or return;
    return unless $type->{user_code}->($user, $ban);

    # like "Banned" or "Banned: because"
    my $reason = $type->{reason};
    $reason .= ": $$ban{reason}" if length $ban->{reason};

    return unless $user->conn;
    $user->conn->done($reason);
    return 1;
}

################
### DISPOSAL ###
################################################################################

sub delete_ban_type {
    my $type_name = lc shift;
    my $type = $ban_types{$type_name} or return;
    L("$type_name unloaded");
}

sub unload_module {
    my $mod_ = shift;
    delete_ban_type($_) foreach $mod_->list_store_items('ban_types');
}

$mod
