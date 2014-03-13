# Copyright (c) 2012, Mitchell Cooper
package API::Base::ServerCommands;

use warnings;
use strict;
use feature 'switch';

use utils qw(log2 col);

our $VERSION = $ircd::VERSION;

sub register_server_command {
    my ($mod, %opts) = @_;

    # make sure all required options are present
    foreach my $what (qw|name code|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        log2("server command $opts{name} does not have '$what' option.");
        return
    }

    # make sure CODE is supplied
    if (ref $opts{code} ne 'CODE') {
        log2("server command $opts{name} didn't supply CODE.");
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
            log2("not enough arguments for $opts{name}");
            $server->{conn}->done('Protocol error.');
            return
        }

        foreach (@{ $opts{parameters} }) { $i++;

            # global lookup
            when ('source') {
                my $source = utils::global_lookup(my $id = col($args[$i]));
                if (!$source) {
                    log2("$command could not get source: $id");
                    $server->{conn}->done('Protocol error.');
                    return;
                }
                push @final_parameters, $source
            }

            # server lookup
            when ('server') {
                my $serv = $main::pool->lookup_server(my $id = col($args[$i]));
                if (!$serv) {
                    log2("$command could not get server: $id");
                    $serv->{conn}->done('Protocol error.');
                    return
                }
                push @final_parameters, $serv
            }

            # user lookup
            when ('user') {
                my $user = $main::pool->lookup_user(my $id = col($args[$i]));
                if (!$user) {
                    log2("$command could not get user: $id");
                    $server->{conn}->done('Protocol error.');
                    return
                }
                push @final_parameters, $user
            }

            # channel lookup
            when ('channel') {
                my $channel = $main::pool->lookup_channel(my $chname = col($args[$i]));
                if (!$channel) {
                    log2("$command could not get channel: $chname");
                    $server->{conn}->done('Protocol error.');
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
    $main::pool->register_server_handler(
        $mod->{name},
        $opts{name},
        $CODE,
        $opts{forward}
    ) or return;
    
    $mod->{user_commands} ||= [];
    push @{ $mod->{server_commands} }, $opts{name};
    return 1
}

sub _unload {
    my ($class, $mod) = @_;
    log2("unloading server commands registered by $$mod{name}");
    $main::pool->delete_server_handler($_) foreach @{ $mod->{server_commands} };
    log2("done unloading commands");
    return 1
}

1
