# Copyright (c) 2009-16, Mitchell Cooper
#
# @name:            "Modules"
# @package:         "M::Modules"
# @description:     "manage modules from IRC"
#
# @depends.modules: ['Base::UserCommands', 'Base::OperNotices']
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Modules;

use warnings;
use strict;
use 5.010;

use utils qw(notice irc_match);

our ($api, $mod, $me, $pool);

our %user_commands = (
    MODULES => {
        desc   => 'display a list of loaded modules',
        params => '*(opt)',
        code   => \&modules
    },
    MODLOAD => {
        desc   => 'load a module',
        params => '-oper(modules) *',
        code   => \&modload
    },
    MODUNLOAD => {
        desc   => 'unload a module',
        params => '-oper(modules) *',
        code   => \&modunload
    },
    MODRELOAD => {
        desc   => 'unload and then load a module',
        params => '-oper(modules) *',
        code   => \&modreload
    }
);

sub init {

    # oper notices.
    $mod->register_oper_notice(
        name   => shift @$_,
        format => shift @$_
    ) or return foreach (
        [ module_load    => '%s loaded %s (%s)' ],
        [ module_unload  => '%s unloaded %s'    ],
        [ module_reload  => '%s reloaded %s'    ]
    );

    return 1;
}

my $indent;
sub display_module {
    my ($user, $module) = @_;
    $indent = 0;
    my $say = sub {
        $user->server_notice(q(  ).('    ' x $indent).($_ // '')) foreach @_;
    };

    $say->(undef, sprintf "\2%s\2 %s", $module->name, $module->{version});
    $indent++;
    $say->(ucfirst $module->{description}) if $module->{description};

    # say the items of each array store.
    my @array_stores = grep {
        ref $module->retrieve($_) eq 'ARRAY' or
        ref $module->retrieve($_) eq 'HASH'
    } keys %{ $module->{store} };

    foreach my $store (@array_stores) {
        next if $store eq 'managed_events';
        (my $pretty = uc $store) =~ s/_/ /g;
        $say->($pretty);

        # fetch the items. for a hash, use keys.
        my @items = ref $module->{store}{$store} eq 'HASH' ?
            keys %{ $module->{store}{$store} }             :
            $module->list_store_items($store);
        @items = sort @items;

        # while we remove each item.
        my @lines   = '';
        my $current = 0;
        while (my $item = shift @items) {

            # if the length of the line will be over 50, no.
            if (length "$lines[$current], $item" > 50) {
                $current++;
                $lines[$current] //= '';
                redo;
            }

            $lines[$current] .= ", $item";
        }
        $indent++;
            $say->($_) foreach map { substr $_, 2, length() - 2 } @lines;
        $indent--;
    }

    # display submodules intended.
    display_module($user, $_) foreach @{ $module->{submodules} || [] };

    $indent--;
}

sub modules {
    my ($user, $event, $query) = (shift, shift, shift // '*');
    $user->server_notice('modules', 'Loaded IRCd modules');

    # find matching modules.
    my @matches =
        sort { $a->name cmp $b->name       }
        grep { irc_match($_->name, $query) }
        grep { !$_->{parent}               }
            @{ $api->{loaded}              };
    display_module($user, $_) foreach @matches;

    $user->server_notice('   ') if @matches;
    $user->server_notice('modules', 'End of modules list');
    return 1;
}

sub modload {
    my ($user, $event, $mod_name) = @_;
    $user->server_notice(modload => "Loading module \2$mod_name\2.");

    # attempt.
    my $result = wrap(sub { $api->load_module($mod_name) }, $user);

    # failure.
    if (!$result) {
        $user->server_notice(modload => 'Module failed to load.');
        return;
    }

    # success.
    notice($user, module_load => $user->notice_info, $result->name, $result->VERSION);
    return 1;

}

sub modunload {
    my ($user, $event, $mod_name) = @_;
    $user->server_notice(modunload => "Unloading module \2$mod_name\2.");

    # attempt.
    my $result = wrap(sub { $api->unload_module($mod_name) }, $user);

    # failure.
    if (!$result) {
        $user->server_notice(modunload => 'Module failed to unload.');
        return;
    }

    # success.
    notice($user, module_unload => $user->notice_info, $result);
    return 1;

}

sub modreload {
    my ($user, $event, $mod_name) = @_;
    $user->server_notice(modreload => "Reloading module \2$mod_name\2.");

    # attempt.
    my $result = wrap(sub { $api->reload_module($mod_name) }, $user);

    # failure.
    if (!$result) {
        $user->server_notice(modreload => 'Module failed to reload.');
        return;
    }

    # success.
    notice($user, module_reload => $user->notice_info, $mod_name);
    return 1;

}

sub wrap {
    my ($code, $user) = @_;

    # attach logging callback
    my $cb = $api->on(log => sub { $user->server_notice("- $_[1]") });

    # before reloading any modules, copy the mode mapping and cap tables
    my $old_modes = server::protocol::mode_change_start($me);
    my $old_caps  = $pool->capability_change_start
        if $pool->can('capability_change_start');

    # do the code
    my $result = $code->();

    # notify servers of mode/cap changes
    server::protocol::mode_change_end($me, $old_modes);
    $pool->capability_change_end($old_caps)
        if $pool->can('capability_change_end');

    # remove logging callback
    $api->delete_callback(log => $cb->{name});

    return $result;
}

$mod
