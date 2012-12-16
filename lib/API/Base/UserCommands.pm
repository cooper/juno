# Copyright (c) 2012, Mitchell Cooper
package API::Base::UserCommands;

use warnings;
use strict;
use v5.10;

use utils qw(log2 col trim);

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
    
    # attributes:
    #
    #   opt
    #       indicates an optional parameter
    #       this parameter will not be taken account when counting the number of
    #       parameters (used to determine whether or not enough parameters are given)
    #
    #   inchan
    #       for channels, gives up and sends ERR_NOTONCHANNEL if the user sending the
    #       command is not in the channel. Ex: channel(inchan)     

    # if parameters is present and does not look like a number...
    if ($opts{parameters} && !looks_like_number($opts{parameters})) {

        # if it is not an array reference, it's a whitespace-separated string.
        if (ref $opts{parameters} ne 'ARRAY') {
            $opts{parameters} = [ split /\s/, $opts{parameters} ];
        }

        # parse argument type attributes.
        my $required_parameters;
        my @argttributes; my $i = -1;
        foreach (@{$opts{parameters}}) { $i++;
        
            # type(attribute1,att2:val,att3)
            if (/(.+)\((.+)\)/) {
                $opts{parameters}[$i] = $1;
                my $attributes = {};
                
                # get the values of each attribute.
                foreach (split ',', $2) {
                    my $attr = trim($_);
                    my ($name, $val) = split ':', $attr, 2;
                    $attributes->{$name} = defined $val ? $val : 1;
                }
                
                $argttributes[$i] = $attributes;
            }
            
            # no attribute list, no attributes.
            else {
                $argttributes[$i] = {};
            }
            
            # unless there is an 'opt' (optional) attribute,
            # increase required parameter count.
            unless ($argttributes[$i]{opt}) {
                $required_parameters++;
            }
            
        }

        # create the new handler.
        $CODE = sub {
            my ($user, $data, @args) = @_;
            my ($i, @final_parameters, %param_id) = -1;
            
            # check argument count.
            if (scalar @args < $required_parameters) {
                $user->numeric(ERR_NEEDMOREPARAMS => $args[0]);
                return;
            }

            $i = -1;
            foreach my $t (@{$opts{parameters}}) { $i++;
                my ($type, $id);
                my $arg = $args[$i];
                my @s   = split '.', $arg, 2;
                
                # if @s has two elements, it had an identifier.
                if (scalar @s == 2) {
                    $id   = $s[0];
                    $type = $s[1];
                }
                
                # otherwise, it didn't.
                else {
                    $id   = 1;
                    $type = $t;
                }
               
                # if $type has an identifier, filter it out first.
                my ($id, $name) = split '.', $arg, 2;
                if (defined $name) { $type = $name }
                else               { $id   = $arg  }
                
                # global lookup
                given ($type) {
                when ('source') {
                    my $source =
                         server::lookup_by_name($arg)  ||
                        channel::lookup_by_name($arg)  ||
                           user::lookup_by_nick($arg);
                    return unless $source;
                    push @final_parameters, $param_id{$id} = $source;
                }

                # server lookup
                when ('server') {
                    my $server = server::lookup_by_name(col($arg));
                    return unless $server;
                    push @final_parameters, $param_id{$id} = $server;
                }

                # user lookup
                when ('user') {
                    my $nickname = (split ',', col($arg))[0];
                    my $usr = user::lookup_by_nick($nickname);

                    # not found, send no such nick.
                    if (!$usr) {
                        $user->numeric(ERR_NOSUCHNICK => $nickname);
                        return;
                    }

                    push @final_parameters, $param_id{$id} = $usr;
                }

                # channel lookup
                when ('channel') {
                    my $chaname = (split ',', col($arg))[0];
                    my $channel = channel::lookup_by_name($chaname);
                    
                    # not found, send no such channel.
                    if (!$channel) {
                        $user->numeric(ERR_NOSUCHCHANNEL => $chaname);
                        return;
                    }
                    
                    # if 'inchan' attribute, the requesting user must be in the channel.
                    if ($argttributes[$i]{inchan} && !$channel->has_user($user)) {
                        $user->numeric(ERR_NOTONCHANNEL => $channel->{name});
                        return;
                    }
                    
                    push @final_parameters, $param_id{$id} = $channel;
                }

                # the rest of a message
                when (':rest') {
                    my $str = (split /\s+/, $data, ($i + 1))[$i];
                    push @final_parameters, col($str) if defined $str;
                }

                # the rest of the message as separate parameters
                when (['...', '@rest']) {
                    push @final_parameters, @args[$i..$#args];
                }

                # any string
                when (['a', 'any', 'ts']) {
                    push @final_parameters, $arg;
                }

                # ignore a parameter
                when ('dummy') { }
                
                }
                
                default {
                    return;
                }
                
            }

            # call the actual handler.
            $opts{code}($user, $data, @final_parameters);

        }
    }

    # if parameters is provided and still exists, that means it was not an ARRAY reference.
    # if it looks like a number, it is a number of parameters to allow.
    elsif (defined $opts{parameters} && looks_like_number($opts{parameters})) {
        $parameters = $opts{parameters};
    }
    
    # register to juno.
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
