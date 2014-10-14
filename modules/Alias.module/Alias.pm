# Copyright (c) 2014, mitchell cooper
#
# Created on Mitchells-Mac-mini.local
# Sat Aug 16 14:04:36 EDT 2014
# Alias.pm
#
# @name:            'Alias'
# @package:         'M::Alias'
# @description:     'support for command aliases'
#
# @depends.modules: 'Base::UserCommands'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Alias;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool, $conf);

# TODO: (evented configuration) this needs to use ->on_change_section() or something.
sub init {
    add_aliases();
}

sub add_aliases {
    my %aliases = $conf->hash_of_block('aliases');
    add_alias($_, $aliases{$_}) foreach keys %aliases;
}

sub add_alias {
    my ($alias, $format) = @_;
    
    # first, generate a format string for sprintf.
    
    my $var_name = my $var_type = my $sprintf_fmt = '';
    my ($in_variable, @variable_order, %variables);
    foreach my $char (split //, "$format\0") {
    
        # dollar starts a variable.
        if ($char eq '$') {
            $in_variable = 1;
            next;
        }

        # we are in a variable.
        if ($in_variable) {
        
            # - in a variable indicates it should be :rest.
            if ($char eq '-') {
                $var_type = ':rest';
                next;
            }
            
            # white space terminates a variable.
            my $is_whitespace = $char =~ m/\s/;
            if ($char eq "\0" || $is_whitespace) {
            
                # force numeric context.
                $var_name += 0;
                
                push @variable_order, $var_name;
                $variables{$var_name} = $var_type ||= '*';                
                
                # add to the format.
                # if it's :rest, it needs the sentinel.
                $sprintf_fmt .= $var_type eq ':rest' ? ':%s' : '%s';
                $sprintf_fmt .= $char if $is_whitespace;
                
                $var_name = $var_type = '';
                undef $in_variable;
                next;
            }
        
            # other character.
            $var_name .= $char;
            next;
            
        }
        
        # not in a variable. this is just part of the message format.
        next if $char eq "\0";
        $sprintf_fmt .= $char eq '%' ? '%%' : $char;
        
    }
    
    # then, generate a parameter string for juno.
    my @params    = map { $variables{$_} } sort keys %variables;
    my $param_fmt = join ' ', @params;
    
    # here is the code for the alias command handler.
    my $code = sub {
        my ($user, $event, @args) = @_;

        # put the arguments in the correct order for the format.
        @args = map { $args[$_ - 1] } @variable_order;
        
        # do the command string.
        $user->handle(sprintf $sprintf_fmt, @args);
        
    };
    
    # attach it.
    return $mod->register_user_command_new(
        name   => $alias,
        code   => $code,
        params => $param_fmt,
        desc   => 'command alias'
    );
    
}

$mod

