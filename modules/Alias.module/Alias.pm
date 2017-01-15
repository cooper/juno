# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-Mac-mini.local
# Sat Aug 16 14:04:36 EDT 2014
# Alias.pm
#
# @name:            'Alias'
# @package:         'M::Alias'
# @description:     'support for command aliases'
#
# @depends.bases+   'UserCommands'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Alias;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool, $conf);
my %current_aliases;

sub init {
    $pool->on('rehash_after' => \&update_aliases, 'update.aliases');
    return update_aliases();
}

sub update_aliases {
    my (@remove, @keep);
    my %new_aliases = $conf->hash_of_block('aliases');
    $new_aliases{ uc $_ } = $new_aliases{$_} for keys %new_aliases;

    # these ones were removed from the configuration or have been changed.
    foreach my $command (keys %current_aliases) {
        $command = uc $command;

        # it was removed from the configuration
        if (!length $new_aliases{$command}) {
            push @remove, $command;
        }

        # the format has changed
        elsif ($new_aliases{$command} ne $current_aliases{$command}) {
            push @remove, $command;
        }

        # otherwise it's unchanged
        else {
            push @keep, $command;
        }

    }

    # remove missing or modified aliases.
    delete_alias($_) foreach @remove;

    # add new aliases.
    delete @new_aliases{@keep};
    add_alias($_, $new_aliases{$_}) foreach keys %new_aliases;

    return 1;
}

sub delete_alias {
    my $alias = shift;
    $alias = uc $alias;
    $mod->delete_user_command($alias);
    delete $current_aliases{$alias};
}

sub add_alias {
    my ($alias, $format) = @_;
    $alias = uc $alias;
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

            # - in a variable indicates it should be :
            if ($char eq '-') {
                $var_type = ':';
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
                # if it's :, it needs the sentinel.
                $sprintf_fmt .= $var_type eq ':' ? ':%s' : '%s';
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
    $mod->register_user_command_new(
        name   => $alias,
        code   => $code,
        params => $param_fmt,
        desc   => 'command alias'
    ) or return;

    # remember it.
    $current_aliases{$alias} = $format;

    return 1;
}

$mod
