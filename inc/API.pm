# Copyright (c) 2012, Mitchell Cooper
package API;

use warnings;
use strict;
use feature 'switch';

use utils qw(conf log2 gv set);

our @loaded;

# load modules in the configuration
sub load_config {
    log2('Loading configuration modules');
    if (my $mods = conf('api', 'modules')) {
        load_module($_, "$_.pm") foreach @$mods;
    }
    log2('Done loading modules');
}

sub load_module {
    my $name = shift;

    # if we haven't already, load API::Module
    if (!$INC{'API/Module.pm'}) {
        require API::Module
    }

    # make sure it hasn't been loaded
    foreach my $mod (@loaded) {
        next unless lc $mod->{name} eq lc $name;
        log2("module $name appears to be loaded already.");
        return
    }

    # load the module
    log2('Loading module '.$name);
    my $file   = $main::run_dir.q(/mod/).shift();
    my $module = do $file or log2("couldn't load $file: $@") and return;

    # make sure it returned properly.
    # even though this is unsupported nowadays, it is
    # still the easiest way to prevent a fatal error
    if (!UNIVERSAL::isa($module, 'API::Module')) {
        log2('Module did not return an API::Module object.');
        return
    }

    # second check that the module doesn't exist already.
    # we really should check this earlier as well, seeing as subroutines and other symbols
    # could have been changed beforehand. this is just a double check.
    foreach my $mod (@loaded) {
        next unless $mod->{package} eq $module->{package};
        log2("module $$module{name} appears to be loaded already.");
        return
    }

    # load the requirements if they are not already
    load_requirements($module) or log2('could not satisfy dependencies') and return;

    # initialize
    log2('initializing module');
    $module->{initialize}->() or log2('module refused to load.') and return;

    log2('Module loaded successfully');
    push @loaded, $module;
    return 1
}

sub unload_module {
    my ($name, $file) = @_;

    # find it..
    my $mod;
    foreach my $module (@loaded) {
        next unless lc $module->{name} eq lc $name;
        $mod = $module;
        last
    }

    if (!$mod) {
        log2("couldn't unload $name because it doesn't exist.");
        return
    }

    # unload all of its commands, loops, modes, etc. unload package.
    call_unloads($mod);
    class_unload($mod->{package});

    # remove from @loaded
    @loaded = grep { $_ != $mod } @loaded;

    # call void if exists.
    if ($mod->{void}) {
        $mod->{void}->()
        or log2("module $$mod{name} refused to unload")
        and return;
    }

    return 1
}

sub load_requirements {
    my $mod = shift;
    return unless $mod->{requires};
    return if ref $mod->{requires} ne 'ARRAY';

    foreach (@{$mod->{requires}}) {
        when ('user_commands')     { load_base('UserCommands')     or return }
        when ('user_modes')        { load_base('UserModes')        or return }
        when ('channel_modes')     { load_base('ChannelModes')     or return }
        when ('server_commands')   { load_base('ServerCommands')   or return }
        when ('outgoing_commands') { load_base('OutgoingCommands') or return }
        default                    { log2('unknown requirement '.$_); return }
    }

    return 1
}

sub load_base {
    my $base = shift;
    return 1 if $INC{"API/Base/$base.pm"}; # already loaded
    log2("loading base $base");
    require "API/Base/$base.pm" or log2("Could not load base $base") and return;
    unshift @API::Module::ISA, "API::Base::$base";
    return 1
}

sub call_unloads {
    my $module = shift;
    $_->unload($module) foreach @API::Module::ISA;
}

# from Class::Unload on CPAN.
# copyright (c) 2011 by Dagfinn Ilmari MannsÃ¥ker.
sub class_unload {
    my $class = shift;
    no strict 'refs';

    # Flush inheritance caches
    @{$class . '::ISA'} = ();

    my $symtab = $class.'::';
    # Delete all symbols except other namespaces
    for my $symbol (keys %$symtab) {
        next if $symbol =~ /\A[^:]+::\z/;
        delete $symtab->{$symbol};
    }

    my $inc_file = join( '/', split /(?:'|::)/, $class ) . '.pm';
    delete $INC{ $inc_file };

    return 1
}

# temporarily store the loaded array on reload
ircd::reloadable(sub {
    $main::TMP_API_LOADED = \@loaded
}, sub {
    @loaded = @{$main::TMP_API_LOADED};
    undef $main::TMP_API_LOADED
})
