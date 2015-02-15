# Copyright (c) 2015, mitchell cooper
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
# @depends.modules: ['JELP::Base', 'Base::UserCommands']
#
package M::Ban;

use warnings;
use strict;
use 5.010;

use Scalar::Util 'looks_like_number';

our ($api, $mod, $pool, $conf, $me);
our ($table, %ban_types);
my %jelp_commands;

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

sub init {
    $table = $conf->table('bans') or return;
    
    # create or update the table.
    my @format = (
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
    $table->create_or_alter(@format);
    
    # ban API.
    $mod->register_module_method('register_ban_type') or return;
    $api->on('module.unload' => \&unload_module, with_eo => 1) or return;
    
    # IRCd event for burst.
    $pool->on('server.send_jelp_burst' => \&burst_bans,
        name    => 'jelp.banburst',
        after   => 'jelp.mainburst',
        with_eo => 1
    );
    
    # outgoing commands.
    $mod->register_outgoing_command(
        name => $_->[0],
        code => $_->[1]
    ) foreach (
        [ ban     => \&ocmd_ban     ],
        [ banidk  => \&ocmd_banidk  ],
        [ baninfo => \&ocmd_baninfo ]
    );
    
    # incoming commands.
    $mod->register_jelp_command(
        name       => $_,
        parameters => $jelp_commands{$_}{params},
        code       => $jelp_commands{$_}{code},
        forward    => $jelp_commands{$_}{forward}
    ) || return foreach keys %jelp_commands;
    
    add_enforcement_events();
    # TODO: activate bans from database
    # TODO: timers
    
    return 1;
}

################
### DATABASE ###
################

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

# insert or update a ban
sub add_or_update_ban {
    my %ban = @_;
    $table->row(id => $ban{id})->insert_or_update(%ban);
}

# delete a ban
sub delete_ban_by_id {
    my $id = shift;
    $table->row(id => $id)->delete;
}

###############
### BAN API ###
###############

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
# note: $mod refers to the module calling the method
#
sub register_ban_type {
    my ($_mod, $event, %opts) = @_;
    my $type_name = lc $opts{name} or return;
    
    # register add command.
    my $command1 = $opts{add_cmd};
    if (length $command1) {
        $command1 = uc $command1;
        $_mod->register_user_command_new(
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
        $_mod->register_user_command_new(
            name        => $command2,
            code        => sub { handle_del_command($type_name, $command2, @_) },
            description => "delete from $type_name ban list",
            parameters  => "-oper($type_name) *" # ban ID | match
        );
    }
    
    # store this type.
    $ban_types{$type_name} = {
        %opts,
        name => $type_name
    };
    
    L("$type_name registered");
    $_mod->list_store_add(ban_types => $type_name);
}

# register a ban right now from this server
sub register_ban {
    my ($type_name, %opts) = @_;

    $opts{id} //= get_next_id();
    my %ban = (
        type        => $type_name,
        id          => $opts{id},
        added       => time,
        modified    => time,
        expires     => $opts{duration} ? time + $opts{duration} : 0,
        aserver     => $me->name,
        %opts
    );
    
    add_or_update_ban(%ban);
    enforce_ban(%ban);
    return %ban;
}

##############
### EVENTS ###
##############

# if $duration is 0, the ban is permanent
sub handle_add_command {
    my ($type_name, $command, $user, $event, $duration, $match, $reason) = @_;
    my $type = $ban_types{$type_name} or return;
    $reason //= '';
    
    # check that the duration is numeric
    my $seconds = utils::string_to_seconds($duration);
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
    if (ban_by_match($match)) {
        $user->server_notice($command => "Ban for $match exists already");
        return;
    }
    
    # TODO: check if it matches too many people
    
    # register the ban
    my %ban = register_ban($type_name,
        match       => $match,
        reason      => $reason,
        duration    => $seconds,
        auser       => $user->full
    );
    
    # TODO: notice
    my $when  = $ban{expires}  ? localtime $ban{expires}  : 'never';
    my $after = $ban{duration} ? "$ban{duration}s" : 'permanent';
    $user->server_notice($command => "Ban for $match added, will expire $when ($after)");
    
    return 1;
}

# $match can be a mask or a ban ID
sub handle_del_command {
    my ($type_name, $command, $user, $event, $match) = @_;
    my $type = $ban_types{$type_name} or return;
    
    # find the ban
    my %ban = ban_by_id($match);
    if (!%ban) { %ban = ban_by_match($match) }
    if (!%ban) {
        $user->server_notice($command => 'No ban matches');
        return;
    }
    
    # delete it
    delete_ban_by_id($ban{id});
    $user->server_notice($command => "Ban for $ban{match} deleted");
    
    # TODO: notice
    return 1;
}

sub unload_module {
    my $_mod = shift;
    delete_ban_type($_) foreach $_mod->list_store_items('ban_types');
}

sub delete_ban_type {
    my $type_name = lc shift;
    my $type = $ban_types{$type_name} or return;
    L("$type_name unloaded");
}

# BANS user command.
our %user_commands = (BANS => {
    code   => \&ucmd_bans,
    desc   => 'list user or server bans',
    params => '-oper(listbans)'
});

sub ucmd_bans {
    my $user = shift;
    my @bans = get_all_bans();
    foreach my $ban (sort { $a->{added} <=> $b->{added} } @bans) {
        my $when = scalar localtime $ban->{expires};
        $user->server_notice("- $$ban{id} | $$ban{match} | $when");
    }
}

###################
### ENFORCEMENT ###
###################

sub add_enforcement_events {
    
    # user connected
    $pool->on('connection.user_ready' => sub {
        my ($event, $user) = @_;
        enforce_all_on_user($user);
    }, 'ban.enforce.user');
    
}

# Enforce all bans on a single entity
# -----

sub enforce_all_on_user {
    my $user = shift;
    foreach my $ban (get_all_bans()) {
        my $type = $ban_types{ $ban->{type} };
        next unless $type->{class} eq 'user';
        return 1 if enforce_ban_on_user($ban, $user);
    }
    return;
}

# Enforce a single ban on all entities
# -----

sub enforce_ban {
    my %ban = @_;
    my $type = $ban_types{ $ban{type} } or return;
    
    # user ban
    if ($type->{class} eq 'user') { return enforce_ban_on_users(%ban) }
    
    return;
}

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

sub enforce_ban_on_user {
    my ($ban, $user) = @_;
    my $type = $ban_types{ $ban->{type} } or return;
    return unless $type->{user_code}->($user, $ban);
    
    # like "Banned" or "Banned: because"
    my $reason = $type->{reason};
    $reason .= ": $$ban{reason}" if length $ban->{reason};
    
    $user->conn->done($reason);
    return 1;
}

###################
### PROPAGATION ###
###################

%jelp_commands = (
);

sub burst_bans {
    my ($server, $fire, $time) = @_;
    if (!$server->{bans_negotiated}) {
        my @ban_refs = $table->rows->select_hash;
        $server->fire_command(ban => @ban_refs);
        $server->{bans_negotiated} = 1;
    }
}

# Outgoing
# -----

# BAN: burst bans
sub ocmd_ban {
    
}

# BANINFO: share ban data
sub ocmd_baninfo {
    
}

# BANIDK: request ban data
sub ocmd_banidk {
    
}

# Incoming
# -----

# BAN: burst bans
sub scmd_ban {
    
}

# BANINFO: share ban data
sub scmd_baninfo {
    
}

# BANIDK: request ban data
sub scmd_banidk {
    
}

$mod

