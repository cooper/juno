# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-Mac-mini.local
# Thu Jun 19 18:05:23 EDT 2014
# Capabilities.pm
#
# @name:            'Base::Capabilities'
# @package:         'M::Base::Capabilities'
# @description:     'provides an interface for client capabilities'
#
# @depends.modules+ 'API::Methods'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Base::Capabilities;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool, $me);

sub init {

    # methods for managing capabilities
    $mod->register_module_method($_) or return for qw(
        register_capability enable_capability
        disable_capability set_capability_value
    );

    # we support cap-notify internally
    register_capability($mod, undef, 'cap-notify');

    # on unload, void capabilities
    $api->on('module.unload' => \&unload_module, 'void.capabilities');

    # methods for monitoring changes to capabilities. these will still
    # exist even when this module is unloaded (which is desired)
    *pool::capability_change_start = *_capability_change_start;
    *pool::capability_change_end   = *_capability_change_end;

    return 1;
}

sub register_capability {
    my ($mod, $event, $name, %opts) = @_;
    my $cap = \%opts;
    $name = lc $name;

    # add to the pool
    $pool->register_cap($mod->name, $name, $cap) or return;
    $mod->list_store_add('capabilities', $name);
    $pool->fire(capability_registered => $cap);
    L("Registered '$name'");

    # set the initial value
    set_capability_value($mod, undef, $name, $cap->{value})
        if length $cap->{value};

    # auto-enable
    enable_capability($mod, undef, $name)
        unless $cap->{manual_enable};

    return 1;
}

sub set_capability_value {
    my ($mod, $event, $name, $new_value) = @_;
    my $cap = $pool->has_cap($name) or return;

    # set the new value
    my $old_value  = $cap->{value};
    $cap->{value}  = $new_value;
    $pool->fire(capability_value_changed => $cap, $old_value, $new_value);

    # don't need to advertise any changes if the cap is not enabled
    return 1 if !$cap->{enabled};
    return 1 if $pool::monitoring_cap_changes;

    # advertise deletion of the cap
    # introduce the cap with the new value
    do_cap_del($name);
    do_cap_new([ $name, $new_value ]);
}

sub enable_capability {
    my ($mod, $event, $name) = @_;
    my $cap = $pool->has_cap($name) or return;

    # mark as enabled, unless it is already
    return if $cap->{enabled};
    $cap->{enabled}++;
    $pool->fire(capability_enabled => $cap);
    L("Enabled '$name'");

    return 1 if $pool::monitoring_cap_changes;

    # notify clients with cap-notify
    do_cap_new([ $name, $cap->{value} ]);
}

sub disable_capability {
    my ($mod, $event, $name, $no_delete) = @_;
    my $cap = $pool->has_cap($name) or return;

    # mark as disabled, unless it is already
    return if !$cap->{enabled};
    delete $cap->{enabled} unless $no_delete;
    $pool->fire(capability_disabled => $cap);
    L("Disabled '$name'");

    return 1 if $pool::monitoring_cap_changes;

    # remove it from all users which have it enabled
    $_->remove_cap($name) for $pool->connections;

    # notify clients with cap-notify
    do_cap_del($name);
}

sub _capability_change_start {
    my $pool = shift;
    $pool::monitoring_cap_changes++;

    # make a copy of the enabled capabilities.
    my %enabled = %{ $pool->{capabilities} || {} };

    return \%enabled;
}

# do not use this directly; use it
sub _capability_change_end {
    my ($pool, $previously_enabled) = @_;
    my (@new, @del);
    undef $pool::monitoring_cap_changes;

    # now go through each of the enabled capabilities.
    foreach my $name ($pool->capabilities) {
        my $new_cap = $pool->has_cap($name);
        my $old_cap = delete $previously_enabled->{$name};

        # this was not enabled before.
        if (!$old_cap || !$old_cap->{enabled}) {
            push @new, [ $name, $new_cap->{value} ]
                if $new_cap->{enabled};
            next;
        }

        # the value has changed.
        if (($new_cap->{value} // '') ne ($old_cap->{value} // '')) {
            push @del, $name
                if $old_cap->{enabled};
            push @new, [ $name, $new_cap->{value} ]
                if $new_cap->{enabled};
            next;
        }

        # otherwise, nothing has changed.
    }

    # anything still left in $previously_enabled has been disabled.
    push @del, grep { $previously_enabled->{$_}{enabled} }
        keys %$previously_enabled;

    # send to clients with cap-notify.
    # do dels first in case some will be re-added (for a value change).
    do_cap_del(@del) if @del;
    do_cap_new(@new) if @new;
}

sub do_cap_del {
    my @del = @_ or return;
    $_->remove_cap(@del) for $pool->real_local_users;
    user::sendfrom_to_all_with_opts(
        $me->name,
        "CAP * DEL :@del",
        { cap => 'cap-notify' }
    );
}

sub do_cap_new {
    my @new = @_;

    # for new, separate into users with IRCv3.2 and not
    my (@no_302, @with_302);
    foreach my $user ($pool->real_local_users) {
        my $conn = $user->conn or next;
        if (($conn->{cap_version} || 0) >= 302) {
            push @with_302, $user;
            next;
        }
        push @no_302, $user;
    }

    # send to clients with version <302 without values
    if (@no_302) {
        my @new_without_values = map {
            ref $_ ? $_->[0] : $_
        } @new;
        user::sendfrom_to_many_with_opts(
            $me->name,
            "CAP * NEW :@new_without_values",
            { cap => 'cap-notify' },
            @no_302
        );
    }

    # now add values for clients with >=302
    if (@with_302) {
        my @new_with_values = map {
            my ($name, $value) = ref $_ ? @$_ : $_;
            length $value ? "$name=$value" : $name;
        } @new;

        user::sendfrom_to_many_with_opts(
            $me->name,
            "CAP * NEW :@new_with_values",
            { cap => 'cap-notify' },
            @with_302
        );
    }

    return 1;
}

sub unload_module {
    my ($mod, $event) = @_;
    foreach my $name ($mod->list_store_items('capabilities')) {
        disable_capability($mod, undef, $name, 1);
        $pool->delete_cap($mod->name, $name);
    }
    return 1;
}

$mod
