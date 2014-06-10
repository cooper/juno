# Copyright (c) 2014, Mitchell Cooper
#
# @name:            "Base::UserCommands"
# @version:         ircd->VERSION
# @package:         "M::Base::UserCommands"
#
# @depends.modules: "API::Methods"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Base::UserCommands;

use warnings;
use strict;
use 5.010;

use utils qw(col trim);
use Scalar::Util qw(looks_like_number);

our ($api, $mod, $pool);

sub init {
    
    # register methods.
    $mod->register_module_method('register_user_command') or return;
    
    # module unload event.
    $api->on('module.unload' => \&unload_module, with_evented_obj => 1) or return;
    
    return 1;
}

sub register_user_command {
    my ($mod, $event, %opts) = @_;

    # make sure all required options are present
    foreach my $what (qw|name description code|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        L("user command $opts{name} does not have '$what' option");
        return;
    }

    my ($CODE, $parameters) = ($opts{code}, 0);
    
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
            $opts{parameters} = [ split /\s+/, $opts{parameters} ];
        }

        # parse argument type attributes.
        my $required_parameters = 0; # number of parameters that will be checked
        my @match_attr;              # matcher attributes (i.e. opt)
        
        my $i = -1;
        foreach (@{ $opts{parameters} }) { $i++;
        
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
                
                $match_attr[$i] = $attributes;
            }
            
            # no attribute list, no attributes.
            else {
                $match_attr[$i] = {};
            }
            
            # unless there is an 'opt' (optional) attribute
            # or it is one of these fake parameters
            next if $match_attr[$i]{opt};
            next if m/^-/; # ex: -command or -id.command
            
            # increase required parameter count.
            $required_parameters++;
            
        }

        # create the new handler.
        $CODE = sub {
            my ($user, $data, @params) = @_;
            my (@final_parameters, %param_id);

            # param_i = current actual parameter index
            # match_i = current matcher index
            # (because a matcher might not really be a parameter matcher at all)
            my ($param_i, $match_i) = (-1, -1);
            
            # remove the command.
            my $command = shift @params;
            
            # check argument count.
            if (scalar @params < $required_parameters) {
                $user->numeric(ERR_NEEDMOREPARAMS => $command);
                return;
            }

            foreach my $_t (@{ $opts{parameters} }) {

                # if it starts with -,
                # don't increment current parameter.
                $match_i++;

                # so basically the dash (-) means that this will not be
                # counted in the required parameters AND that it does
                # not actually have a real parameter associated with it.
                # if it does use a real parameter, DO NOT USE THIS!
                # use (opt) instead if that is the case.
                
                # is this a fake (ignored) matcher?
                my ($t, $fake) = $_t;
                if ($t =~ s/^-//) { $fake = 1 }
                else { $param_i ++ }

                # split into a type and possibly an identifier.
                my ($type, $id);
                my $param = $params[$param_i];
                my @s     = split /\./, $t, 2;
                if (scalar @s == 2) { ($id, $type) = @s }
                else {
                    $id   = 1;
                    $type = $t;
                }
                
                # if this is not a fake matcher, and if there is no parameter,
                # we should skip this. well, we should be done with the rest, too.
                last if !$fake && !defined $param;
                
                given ($type) {
                
                # inject command (should be used with dash)
                when ('command') {
                    push @final_parameters, $command;
                }
                
                # oper flag check (should be used with dash)
                when ('oper') {
                    foreach my $flag (keys %{ $match_attr[$match_i] }) {
                        if (!$user->has_flag($flag)) {
                            $user->numeric('ERR_NOPRIVILEGES', $flag);
                            return;
                        }
                        # FIXME: what if you did opt or some other
                        # option here. that wouldn't be a flag.
                    }
                }
                
                # global lookup
                when ('object') {
                    my $obj =
                         $pool->lookup_server_name($param)  ||
                         $pool->lookup_channel($param)      ||
                         $pool->lookup_user_nick($param);
                    return unless $obj;
                    push @final_parameters, $param_id{$id} = $obj;
                }

                # user or server.
                when ('source') {
                    my $source =
                         $pool->lookup_server_name($param)  ||
                         $pool->lookup_user_nick($param);
                    return unless $source;
                    push @final_parameters, $param_id{$id} = $source;
                }

                # server lookup
                when ('server') {
                    my $server = $pool->lookup_server_name(col($param));

                    # not found, send no such server.
                    if (!$server) {
                        $user->numeric(ERR_NOSUCHSERVER => col($param));
                        return;
                    }

                    push @final_parameters, $param_id{$id} = $server;
                }

                # user lookup
                when ('user') {
                    my $nickname = (split ',', col($param))[0];
                    my $usr = $pool->lookup_user_nick($nickname);

                    # not found, send no such nick.
                    if (!$usr) {
                        $user->numeric(ERR_NOSUCHNICK => $nickname);
                        return;
                    }

                    push @final_parameters, $param_id{$id} = $usr;
                }

                # channel lookup
                when ('channel') {
                    my $chaname = (split ',', col($param))[0];
                    my $channel = $pool->lookup_channel($chaname);
                    
                    # not found, send no such channel.
                    if (!$channel) {
                        $user->numeric(ERR_NOSUCHCHANNEL => $chaname);
                        return;
                    }
                    
                    # if 'inchan' attribute, the requesting user must be in the channel.
                    if ($match_attr[$match_i]{inchan} && !$channel->has_user($user)) {
                        $user->numeric(ERR_NOTONCHANNEL => $channel->name);
                        return;
                    }
                    
                    push @final_parameters, $param_id{$id} = $channel;
                }

                # the rest of a message
                # 0   1    2  3     4
                #          0  1     2
                # :hi KICK #k mitch :message
                when (':rest') {
                    my $str = (split /\s+/, $data, $param_i + 2)[-1];
                    push @final_parameters, col($str) if defined $str;
                }

                # the rest of the message as separate parameters
                when (['...', '@rest']) {
                    push @final_parameters, @params[$param_i..$#params];
                }

                # any string
                when (['a', 'any', 'ts']) {
                    push @final_parameters, $param;
                }

                # ignore a parameter
                when ('dummy') { }
                
                # uknown!
                default {
                    $mod->_api("unknown parameter type $type!");
                    return;
                }
                
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
    
    # register the handler.
    $opts{name} = uc $opts{name};
    $pool->register_user_handler(
        $mod->name,
        $opts{name},
        $parameters,
        $CODE,
        $opts{description},
        $opts{fantasy}
    ) or return;

    L("$opts{name} registered: $opts{description}");
    $mod->list_store_add('user_commands', $opts{name});
    return 1;
}

sub unload_module {
    my ($mod, $event) = @_;
    $pool->delete_user_handler($_) foreach $mod->list_store_items('user_commands');
    return 1;
}

$mod