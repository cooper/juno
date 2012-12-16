# Copyright (c) 2012, Mitchell Cooper
package API::Base::UserCommands;

use warnings;
use strict;
use v5.10;

use utils 'log2';

use Scalar::Util 'looks_like_number';

sub register_user_command {
    my ($mod, %opts) = @_;

    # make sure all required options are present
    foreach my $what (qw|name description code|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        log2("user command $opts{name} does not have '$what' option.");
        return
    }
    
    $mod->{user_commands} ||= [];
    my $CODE       = $opts{code};
    my $parameters = 0;
    
    # parameters:
    #     channel channel name lookup
    #     source  global name (checks for nicks, channel names, server names) lookup
    #     server  server name lookup
    #     user    nickname lookup
    #     :rest   the rest of the message with colon removed
    #     @rest   the rest of the message as a space-separated list
    #     any     plain old string
    #     ts      timestamp

    $CODE = sub {
        my ($user, $data, @args) = @_;
        my ($i, @final_parameters) = -1;

        # check argument count.
        if (scalar @args < scalar @{$opts{parameters}}) {
            $user->numeric(ERR_NEEDMOREPARAMS => $opts{name});
            return;
        }

        foreach (@{$opts{parameters}}) { $i++;

            # global lookup
            when ('source') {
                my $source =
                     server::lookup_by_name($args[$i])  ||
                    channel::lookup_by_name($args[$i])  ||
                       user::lookup_by_nick($args[$i]);
                return unless $source;
                push @final_parameters, $source;
            }

            # server lookup
            when ('server') {
                my $server = server::lookup_by_name(col($args[$i]));
                return unless $server;
                push @final_parameters, $server;
            }

            # user lookup
            when ('user') {
                my $nickname = split ',', col($args[$i]);
                my $usr = user::lookup_by_nick($nickname);

                # not found, send no such nick.
                if (!$usr) {
                    $user->numeric(ERR_NOSUCHNICK => $nickname);
                    return;
                }

                push @final_parameters, $usr;
            }

            # channel lookup
            when ('channel') {
                my $chaname = split ',', col($args[$i]);
                my $channel = channel::lookup_by_name($chaname);
                
                # not found, send no such channel.
                if (!$channel) {
                    $user->numeric(ERR_NOSUCHCHANNEL => $chaname);
                    return;
                }
                
                push @final_parameters, $channel;
            }

            # the rest of a message
            when (':rest') {
                my $str = (split /\s+/, $data, ($i + 1))[$i];
                push @final_parameters, col($str);
            }

            # the rest of the message as separate parameters
            when (['...', '@rest']) {
                push @final_parameters, @args[$i..$#args];
            }

            # any string
            when (['a', 'any', 'ts']) {
                push @final_parameters, $args[$i];
            }

            # ignore a parameter
            when ('dummy') { }

        }

        $opts{code}($user, $data, @final_parameters);

    } if $opts{parameters} && ref $opts{parameters} eq 'ARRAY';

    # if parameters is provided and still exists, that means it was not an ARRAY reference.
    # if it looks like a number, it is a number of parameters to allow.
    if ($CODE == $opts{code} && looks_like_number($opts{parameters})) {
        $parameters = $opts{parameters};
    }

    # register to juno
    user::mine::register_handler(
        $mod->{name},
        $opts{name},
        $parameters,
        $CODE,
        $opts{description}
    ) or return;

    push @{$mod->{user_commands}}, $opts{name};
    return 1
}

sub unload {
    my ($class, $mod) = @_;
    log2("unloading user commands registered by $$mod{name}");
    user::mine::delete_handler($_) foreach @{$mod->{user_commands}};
    log2("done unloading commands");
    return 1
}

1
