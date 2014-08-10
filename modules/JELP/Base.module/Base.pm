# Copyright (c) 2010-14, Mitchell Cooper
#
# @name:            "JELP::Base"
# @package:         "M::JELP::Base"
#
# @depends.modules: ['API::Methods']
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::JELP::Base;

use warnings;
use strict;
use 5.010;

use utils qw(col trim notice);
use Scalar::Util qw(looks_like_number);

our ($api, $mod, $pool);

sub init {
    
    # register methods.
    $mod->register_module_method('register_server_command'  ) or return;
    $mod->register_module_method('register_global_command'  ) or return;
    $mod->register_module_method('register_outgoing_command') or return;
    
    # module unload event.
    $api->on('module.unload' => \&unload_module, with_eo => 1) or return;
    
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

    my ($CODE, $parameters) = ($opts{code}, 0); # discuss: $parameters is not used
    
    # parameters:
    #     channel channel name lookup
    #     source  global ID (checks for UIDs, channel names, SIDs) lookup
    #     server  SID lookup
    #     user    UID lookup
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
    #
    # BORROWED FROM USER HANDLERS BUT DISABLED:
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
            my ($server, $data, @params) = @_;
            my (@final_parameters, %param_id);

            # param_i = current actual parameter index
            # match_i = current matcher index
            # (because a matcher might not really be a parameter matcher at all)
            my ($param_i, $match_i) = (-1, -1);
            
            # remove the command.
            my $command = splice @params, 1, 1;
            
            # error sub.
            my $err = sub {
                my $error = shift;
                notice(server_warning => "Received invalid $command from $$server{name}: $error");
                return;
            };
            
            # check argument count.
            if (scalar @params < $required_parameters) {
                return $err->('Not enough parameters');
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
                
                # inject command
                # this should probably have a dash on it like -command
                when ('command') {
                    push @final_parameters, $command;
                }
                
                # global lookup
                when ('object') {
                    $param = col($param);
                    my $obj =
                         $pool->lookup_server($param)  ||
                         $pool->lookup_channel($param) ||
                         $pool->lookup_user($param);
                    return unless $obj;
                    push @final_parameters, $param_id{$id} = $obj;
                }
                
                # user or server lookup
                when ('source') {
                    $param = col($param);
                    my $source =
                         $pool->lookup_server($param)  ||
                         $pool->lookup_user($param);
                    return unless $source;
                    push @final_parameters, $param_id{$id} = $source;
                }

                # server lookup
                when ('server') {
                    my $server = $pool->lookup_server(col($param));

                    # not found, send no such server.
                    if (!$server) {
                        return $err->('No such server '.col($param));
                    }

                    push @final_parameters, $param_id{$id} = $server;
                }

                # user lookup
                when ('user') {
                    my $uid = (split ',', col($param))[0];
                    my $usr = $pool->lookup_user($uid);

                    # not found, send no such nick.
                    if (!$usr) {
                        return $err->("No such user $uid");
                    }

                    push @final_parameters, $param_id{$id} = $usr;
                }

                # channel lookup
                when ('channel') {
                    my $chaname = (split ',', col($param))[0];
                    my $channel = $pool->lookup_channel($chaname);
                    
                    # not found, send no such channel.
                    if (!$channel) {
                        return $err->("No such channel $chaname");
                    }
                    
                    # TODO: maybe make this use the source if it's a user.
                    # if 'inchan' attribute, the requesting user must be in the channel.
                    #if ($match_attr[$match_i]{inchan} && !$channel->has_user($user)) {
                    #    $user->numeric(ERR_NOTONCHANNEL => $channel->name);
                    #    return;
                    #}
                    
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
                    $mod->_log("unknown parameter type $type!");
                    return;
                }
                
                }
                
            }

            # call the actual handler.
            $opts{code}($server, $data, @final_parameters);

        }
    }

    # if parameters is provided and still exists, that means it was not an ARRAY reference.
    # if it looks like a number, it is a number of parameters to allow.
    elsif (defined $opts{parameters} && looks_like_number($opts{parameters})) {
        $parameters = $opts{parameters};
    }

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

sub register_global_command {
    my ($mod, $event, %opts) = @_;
    
    # make sure all required options are present
    foreach my $what (qw|name|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        L("global command $opts{name} does not have '$what' option");
        return;
    }
    
    # create a handler that calls ->handle_unsafe().
    $opts{code} = sub {
        my ($server, $data, $user, $rest) = @_;
        $user->handle_unsafe("$opts{name} $rest");
    };
    
    # pass it on to this base's ->register_server_command().
    return register_server_command($mod, $event,
        %opts,
        parameters => 'user :rest(opt)'
    );
    
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
        $opts{code},
        'jelp'
    ) or return;

    L("JELP outgoing command $opts{name} registered");
    $mod->list_store_add('outgoing_commands', $opts{name});
    return 1;
}

sub unload_module {
    my ($mod, $event) = @_;
    $pool->delete_server_handler($_) foreach $mod->list_store_items('server_commands');
    $pool->delete_outgoing_handler($_, 'jelp')
        foreach $mod->list_store_items('outgoing_commands');
    return 1;
}

$mod
