# Copyright (c) 2014, Mitchell Cooper
# reload entire IRCd in one command.
package API::Module::Reload;

use warnings;
use strict;

our $mod = API::Module->new(
    name        => 'Reload',
    version     => '0.1',
    description => 'reload entire IRCd in one command',
    requires    => ['UserCommands'],
    initialize  => \&init
);

sub init {
    $mod->register_user_command(
        name        => 'reload',
        code        => \&cmd_reload,
        description => 'reload the entire IRCd',
        parameters  => '-oper(reload)'
    ) or return;
    
    return 1;
}

sub cmd_reload {
    my ($user, $data) = @_;
    my $v = $ircd::VERSION;
    $user->server_notice(reload => 'Reloading IRCd');
    
    # ignore submodules.
    my @mods_loaded = map { $_->full_name } grep { !$_->{parent} }
      @{ $main::API->{loaded} };
    
    # unload them all.
    $user->server_notice('Unloading modules');
    foreach my $name (@mods_loaded) {
        $user->server_notice("    * $name");
        $main::API->unload_module($name) or
          $user->server_notice("$name refused to unload. See log.") and last;
    }
    
    # reload IRCd core.
    $user->server_notice('Reloading ircd core with start()');
    eval { ircd::start() }
      or $user->server_notice("start() failed (VERY BAD) $@") and return;
    
    # load all modules that were loaded.
    $user->server_notice('Loading modules');
    foreach my $name (@mods_loaded) {
        $user->server_notice("    * $name");
        $main::API->load_module($name, "$name.pm") or
          $user->server_notice("$name refused to load. See log.") and last;
    }
    
    # difference in version.
    $user->server_notice(reload =>
        $ircd::VERSION != $v ? "Server upgraded from $v to $ircd::VERSION" :
        'Server reload complete'
    );
    
    return 1;
}

$mod
