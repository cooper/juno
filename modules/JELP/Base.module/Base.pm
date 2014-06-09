# Copyright (c) 2010-14, Mitchell Cooper
#
# @name:            "JELP::Base"
# @package:         "M::JELP::Base"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::JELP::Base;

use warnings;
use strict;
use 5.010;

use utils qw(col);

our ($api, $mod, $pool);

sub init {
    
    # register methods.
    $mod->register_module_method('register_server_command'  ) or return;
    $mod->register_module_method('register_outgoing_command') or return;
    
    # module unload event.
    $api->on('module.unload' => \&unload_module, with_evented_obj => 1) or return;
    
    return 1;
}

sub register_server_command {
    my ($mod, $event, %opts) = @_;

    # make sure all required options are present
    foreach my $what (qw|name code|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        L("server command $opts{name} does not have '$what' option");
        return
    }

    # make sure CODE is supplied
    if (ref $opts{code} ne 'CODE') {
        L("server command $opts{name} didn't supply CODE");
        return
    }

    my $CODE    = $opts{code};
    my $command = $opts{name};
    
    # parameters:
    #     channel channel name lookup
    #     source  global ID lookup
    #     server  SID lookup
    #     user    UID lookup
    #     :rest   the rest of the message with colon removed
    #     @rest   the rest of the message as a space-separated list
    #     any     plain old string
    #     ts      timestamp

    $CODE = sub {
        my ($server, $data, @args) = @_;
        my ($i, @final_parameters) = -1;

        # if it is not an array reference, it's a whitespace-separated string.
        if (ref $opts{parameters} ne 'ARRAY') {
            $opts{parameters} = [ split /\s+/, $opts{parameters} ];
        }

        # check argument count
        if (scalar @args < scalar @{ $opts{parameters} }) {
            L("Protocol error: $$server{name}: $command not enough arguments for command");
            $server->{conn}->done('Protocol error');
            return
        }

        foreach (@{ $opts{parameters} }) { $i++;

            # global lookup
            when ('source') {
                my $source = utils::global_lookup(my $id = col($args[$i]));
                if (!$source) {
                    L("Protocol error: $$server{name}: $command could not get source: $id");
                    $server->{conn}->done('Protocol error');
                    return;
                }
                push @final_parameters, $source
            }

            # server lookup
            when ('server') {
                my $serv = $pool->lookup_server(my $id = col($args[$i]));
                if (!$serv) {
                    L("Protocol error: $$server{name}: $command could not get server: $id");
                    $server->{conn}->done('Protocol error');
                    return
                }
                push @final_parameters, $serv
            }

            # user lookup
            when ('user') {
                my $user = $pool->lookup_user(my $id = col($args[$i]));
                if (!$user) {
                    L("Protocol error: $$server{name}: $command could not get user: $id");
                    $server->{conn}->done('Protocol error');
                    return
                }
                push @final_parameters, $user
            }

            # channel lookup
            when ('channel') {
                my $channel = $pool->lookup_channel(my $chname = col($args[$i]));
                if (!$channel) {
                    L("Protocol error: $$server{name}: $command could not get channel: $chname");
                    $server->{conn}->done('Protocol error');
                    return
                }
                push @final_parameters, $channel
            }

            # the rest of a message
            when (':rest') {
                my $str = (split /\s+/, $data, ($i + 1))[$i];
                push @final_parameters, col($str)
            }

            # the rest of the message as separate parameters
            when (['...', '@rest']) {
                push @final_parameters, @args[$i..$#args]
            }

            # any string
            when (['a', 'any', 'ts']) {
                push @final_parameters, $args[$i]
            }

            # ignore a parameter
            when ('dummy') { }

        }

        $opts{code}($server, $data, @final_parameters);

    } if $opts{parameters};

    # register to juno: updated 12/11/2012
    # ($source, $command, $callback, $forward)
    $opts{name} = uc $opts{name};
    $pool->register_server_handler(
        $mod->name,
        $opts{name},
        $CODE,
        $opts{forward}
    ) or return;
    
    L("JELP command handler $opts{name} registered");
    $mod->list_store_add('server_commands', $opts{name});
    return 1;
}

sub register_outgoing_command {
    my ($mod, $event, %opts) = @_;

    # make sure all required options are present
    foreach my $what (qw|name code|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        L("outgoing command $opts{name} does not have '$what' option");
        return
    }

    # register to juno
    $opts{name} = uc $opts{name};
    $pool->register_outgoing_handler(
        $mod->name,
        $opts{name},
        $opts{code}
    ) or return;

    L("JELP outgoing command $opts{name} registered");
    $mod->list_store_add('outgoing_commands', $opts{name});
    return 1;
}

sub unload_module {
    my ($mod, $event) = @_;
    $pool->delete_server_handler($_)   foreach $mod->list_store_items('server_commands');
    $pool->delete_outgoing_handler($_) foreach $mod->list_store_items('outgoing_commands');
    return 1;
}

$mod
