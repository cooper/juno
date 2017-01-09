# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-MacBook-Pro.local
# Sun Feb 15 23:50:52 EST 2015
# Set.pm
#
# @name:            'Configuration::Set'
# @package:         'M::Configuration::Set'
# @description:     'set and fetch configuration values across servers'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
# @depends.modules: ['JELP::Base', 'Base::UserCommands']
#
package M::Configuration::Set;

use warnings;
use strict;
use 5.010;

use utils qw(conf);
use Evented::Database qw(edb_encode edb_decode);

our ($api, $mod, $pool, $me, $conf);

our %jelp_outgoing_commands = (
    confget => \&out_confget,
    confset => \&out_confset
);

our %user_commands = (
    CONFSET => {
        code    => \&cmd_confset,
        desc    => 'set a configuration value',
        params  => '-oper(confset) *           *        :'
                  #                server_mask location value
    },
    CONFDEL => {
        code    => \&cmd_confdel,
        desc    => 'delete a configuration value',
        params  => '-oper(confset) *           *'
                  #                server_mask location
    },
    CONFGET => {
        code    => \&cmd_confget,
        desc    => 'get a configuration value',
        params  => '-oper(confget) *           *'
                  #                server_mask location
    }
);

my @help_text = (
    'Incorrect value syntax. Please refer to these examples:',
    '| ----------- | ------------ | --------- |',
    '| Number      | String       | Boolean   |',
    '| 3.14        | "some text"  | on/off    |',
    '| ----------- | ------------ | --------- |',
    '| List        | Map          | Null      |',
    '| [ 1, "hi" ] | { "a": "b" } | undef     |',
    '| ----------- | ------------ | --------- |'
);

sub init {
    $mod->register_global_command(name => $_) || return
        foreach qw(confset confget);
    return 1;
}

sub forwarder {
    my ($command, $user, $server_mask_maybe, $gflag, @cmd_args) = @_;

    # if no dot in server, it's not a server.
    # it's the first argument. use the local server.
    # this might cause problems for CONFSET because of :
    my @servers;
    if ($server_mask_maybe =~ m/[\.\*\$]/) {
        @servers = $pool->lookup_server_mask($server_mask_maybe);
    }
    else {
        @servers = $me;
        unshift @cmd_args, $server_mask_maybe;
    }

    # no priv.
    if (!$user->has_flag($gflag)) {
        $user->numeric(ERR_NOPRIVILEGES => $gflag);
        return 1;
    }

    # no matches.
    if (!@servers) {
        $user->numeric(ERR_NOSUCHSERVER => $server_mask_maybe);
        return 1;
    }

    # wow there are matches.
    my %done;
    foreach my $serv (@servers) {

        # already did this one!
        next if $done{$serv};
        $done{$serv} = 1;

        # if it's $me, skip.
        # if there is no connection (whether direct or not),
        # uh, I don't know what to do at this point!
        next if $serv->is_local;
        next unless $serv->{location};

        # pass it on :)
        $serv->{location}->fire_command(lc $command => $user, $serv, @cmd_args);

    }

    # if $me is done, just keep going.
    return !$done{$me};

}

sub cmd_confget {
    my ($user, $event, $server_mask, $location) = @_;

    # if not for me, forward
    forwarder('CONFGET', $user, $server_mask, 'gconfget', $location)
        and return 1;

    # find location
    $location  //= $server_mask;
    my @location = parse_location($location);
    if (!@location) {
        $user->server_notice(confget => "Invalid location '$location'");
        return;
    }
    my $pretty = pretty_location(@location);

    # get the value
    my ($ok, $value_str) = pretty_value($conf->_get(1, @location));
    if (!$ok) {
        chomp $value_str;
        $user->server_notice(confget => $value_str);
        return;
    }

    my $serv_name = $user->is_local ? '' : " <$$me{name}>";
    $user->server_notice(confget => "$pretty = $value_str$serv_name");
}

sub cmd_confset {
    my ($user, $event, $server_mask, $location, $value_str) = @_;

    # if not for me, forward
    forwarder('CONFSET', $user, $server_mask, 'gconfset', $location, ":$value_str")
        and return 1;

    # find location
    $location  //= $server_mask;
    my @location = parse_location($location);
    if (!@location) {
        $user->server_notice(confget => "Invalid location '$location'");
        return;
    }

    # handle input
    my ($ok, $value) = parse_value($value_str);
    if (!$ok) {
        chomp $value;
        $user->server_notice(confset => $_) for (
            $value,
            @help_text
        );
        return;
    }

    # store
    my $pretty = pretty_location(@location);
    $value_str = pretty_value($value);
    $conf->store(@location, $value);

    my $serv_name = $user->is_local ? '' : " <$$me{name}>";
    $user->server_notice(confset => "Set $pretty = $value_str$serv_name");
}

sub cmd_confdel {
    my ($user, $event, $server_mask, $location) = @_;
    cmd_confset($user, $event, $server_mask, $location, 'undef');
}

# block_type/key            -> (block_type, key)
# block_type/block_name/key -> ([block_type, block_name], key)
sub parse_location {
    my ($block_type, $block_name, $key) = split /\//, shift, 3;
    return unless length $block_name;
    return length $key ?
        ([ $block_type, $block_name ], $key)
    : ($block_type, $block_name);
}

sub pretty_location {
    my ($a, $b) = @_;
    return ref $a eq 'ARRAY' ? "[ $$a[0]: $$a[1] ] $b" : "[ $a ] $b";
}

sub parse_value {
    my $str = shift;

    # convert EDB undef/on/off
    return (1, undef) if $str eq 'undef';
    return (1, Evented::Configuration::on)  if $str eq 'on';
    return (1, Evented::Configuration::off) if $str eq 'off';

    my $decoded = edb_decode($str);
    return (!$@, $@ || $decoded);
}

sub pretty_value {
    my $value = edb_encode(shift);
    return (undef, $@) if $@;
    $value = "\2undef\2" if $value eq 'null';
    $value = "\2on\2"    if $value eq 'true';
    $value = "\2off\2"   if $value eq 'false';
    return (1, $value);
}

sub out_confget {
    my ($to_server, $user, $serv, @cmd_args) = @_;
    ":$$user{uid} CONFGET \$$$serv{sid} @cmd_args"
}

sub out_confset {
    my ($to_server, $user, $serv, @cmd_args) = @_;
    ":$$user{uid} CONFSET \$$$serv{sid} @cmd_args"
}

$mod
