# Copyright (c) 2015, mitchell cooper
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

our ($api, $mod, $pool, $me, $conf);

our %user_commands = (
    CONFSET => {
        code    => \&cmd_confset,
        desc    => 'set a configuration value',
        params  => '-oper(confset) *           *        :rest'
                  #                server_mask location value
    },
    CONFDEL => {
        code    => \&cmd_confdel,
        desc    => 'delete a configuration value',
        params  => '-oper(confdel) *           *'
                  #                server_mask location
    },
    CONFGET => {
        code    => \&cmd_confget,
        desc    => 'get a configuration value',
        params  => '-oper(confget) *(opt)      *'
                  #                server_mask location
    }
);

sub init {
    $mod->register_global_command($_) || return foreach qw(confset confget);
    return 1;
}

sub forwarder {
    my ($command, $user, $server_mask_maybe, $gflag, @cmd_args) = @_;
    
    # if no dot in server, it's not a server.
    # it's the first argument. use the local server.
    # this might cause problems for CONFSET because of :rest
    my @servers;
    if (index($server_mask_maybe, '.') != -1) {
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
        $serv->{location}->fire_command_data(
            $command => $user, "$command $$serv{name} @cmd_args"
        );
        
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
    
    # get
    my $pretty    = pretty_location(@location);
    my $value_str = encode_value(conf(@location)) // "\2undef\2";
    
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
    my $value  = parse_value($value_str);
    if (defined $value && $value eq '_BAD_INPUT_') {
        $user->server_notice(
            confset => 'Invalid value; must be encoded in Evented::Database format'
        );
        return;
    }
    
    # store
    my $pretty = pretty_location(@location);
    $value_str = encode_value($value) // "\2undef\2";
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
    return unless defined $block_name;
    return defined $key ?
        ([ $block_type, $block_name ], $key)
    : ($block_type, $block_name);
}

sub pretty_location {
    my ($a, $b) = @_;
    return ref $a eq 'ARRAY' ? "[ $$a[0]: $$a[1] ] $b" : "[ $a ] $b";
}

sub parse_value {
    my $str = shift;
    return undef if $str eq 'undef' || $str eq 'off';
    return 1 if $str eq 'on';
    return eval { $Evented::Database::json->decode($str) } // '_BAD_INPUT_';
}

sub encode_value {
    my $value = shift;
    return undef if !defined $value;
    return eval { Evented::Database::edb_encode($value) };
}

$mod

