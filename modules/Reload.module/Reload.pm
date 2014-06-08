# Copyright (c) 2012-14, Mitchell Cooper
#
# @name:            "Reload"
# @package:         "M::Reload"
# @description:     "reload the entire IRCd in one command"
#
# @depends.modules: ['Base::UserCommands', 'Base::OperNotices']
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Reload;

use warnings;
use strict;

use utils qw(notice);

our ($api, $mod);

sub init {
    $mod->register_user_command(
        name        => 'reload',
        code        => \&cmd_reload,
        description => 'reload the entire IRCd',
        parameters  => '-oper(reload) @rest(opt)'
    ) or return;
    
    $mod->register_oper_notice(
        name   => 'reload',
        format => '%s (%s@%s): %s'
    ) or return;
    
    return 1;
}

sub cmd_reload {
    my ($user, $data, @rest) = @_;
    
    # command flags.
    my $verbose;
    foreach (@rest) {
        $verbose = 1 if $_ eq '-v';
    }
    
    my $old_v = $ircd::VERSION;
    $user->server_notice(reload => "Reloading IRCd $old_v");

    # log to user if verbose.
    my $cb;
    $cb = $::api->on(log => sub { $user->server_notice("- $_[1]") },
        name      => 'cmd.reload',
        permanent => 1 # we will remove it manually afterward
    ) if $verbose;
    
    # determine modules loaded beforehand.
    my @mods_loaded = @{ $api->{loaded} };
    my $num = scalar @mods_loaded;

    # reload ircd first and then all other modules.
    my $ircd = $api->get_module('ircd');
    $api->reload_module($ircd, grep {
        $_ != $ircd &&
        !$_->{UNLOADED} &&
        !$_->{parent}
    } @mods_loaded);
    my $new_v = ircd->VERSION;
    
    # module summary.
    $user->server_notice('- Module summary');
    my $reloaded = 0;
    foreach my $old_m (@mods_loaded) {
        my $new_m = $api->get_module($old_m->name);
        
        # not loaded.
        if (!$new_m) {
            $user->server_notice("    - Not loaded: $$old_m{name}{full}");
            next;
        }
        
        # version change.
        if ($new_m->{version} > $old_m->{version}) {
            $user->server_notice("    - Upgraded: $$new_m{name}{full} ($$old_m{version} -> $$new_m{version})");
            next;
        }
        
        $reloaded++;
    }
    
    # find new modules.
    NEW: foreach my $new_m (@{ $api->{loaded} }) {
        foreach my $old_m (@mods_loaded) {
            next NEW if $old_m->name eq $new_m->name;
        }
        $user->server_notice("    - Loaded: $$new_m{name}{full}");
    }
    
    $user->server_notice("    - $reloaded modules reloaded and not upgraded");
    
    # difference in version.
    my $info;
    if ($new_v != $old_v) {
        my $amnt = sprintf('%.f', abs($new_v - $::VERSION) * 100);
        $info = "Server upgraded from $old_v to $new_v (up $amnt versions since start)";
    }
    else {
        $info = 'Server reloaded';
    }

    $::api->delete_callback('log', $cb->{name}) if $verbose;
    $user->server_notice(reload => $info);
    notice(reload => $user->notice_info, $info);
    return 1;
}

$mod