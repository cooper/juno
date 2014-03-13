# Copyright (c) 2014, Mitchell Cooper
# reload entire IRCd in one command.
package API::Module::Reload;

use warnings;
use strict;

our $mod = API::Module->new(
    name        => 'Reload',
    version     => '0.2',
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
    my $ver = $ircd::VERSION;
    $user->server_notice(reload => 'Reloading IRCd');
    
    # ignore submodules.
    my @mods_loaded = grep { !$_->{parent} } @{ $::API->{loaded} };
    
    # unload them all.
    $user->server_notice('Unloading modules');
    my %vers;
    foreach my $m (@mods_loaded) {
        my $name = $m->full_name;
        $user->server_notice("    * $name");
        $::API->unload_module($name) or
          $user->server_notice("$name refused to unload. See log.") and last;
        $vers{$name} = $m->{version};
    }
    
    # reload IRCd core.
    $user->server_notice('Reloading ircd core with start()');
    eval { ircd::start() }
      or $user->server_notice("start() failed (VERY BAD) $@") and return;
    
    # load all modules that were loaded.
    $user->server_notice('Loading modules');
    foreach my $m (@mods_loaded) {
        my $name = $m->full_name;
        my $res  = $::API->load_module($name, "$name.pm");
           $m    = $::API->get_module($name);
        my $old  = $vers{$name} // 0;
        my $v    = $m->{version} > ($old) ? "($old -> $$m{version})" : '';
        $user->server_notice("    * $name $v");
        $res or $user->server_notice("$name refused to load. See log."), last;
    }
    
    # difference in version.
    $user->server_notice(reload =>
        $ircd::VERSION != $ver ? "Server upgraded from $ver to $ircd::VERSION" :
        'Server reload complete'
    );
    
    return 1;
}

$mod
