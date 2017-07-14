# Copyright (c) 2009-16, Mitchell Cooper
#
# @name:            "Base::AddUser"
# @package:         "M::Base::AddUser"
# @description:     "virtual user support"
#
# @depends.modules+ "API::Methods"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Base::AddUser;

use warnings;
use strict;
use 5.010;

use utils qw(broadcast);

our ($api, $mod, $pool, $me);
my %unloaded_users; # ID to user object

sub init {
    $mod->register_module_method('add_user') or return;
    
    # on module unload, quit users
    $api->on('module.unload' => \&on_unload, 'adduser.unload');
    
    # on change start, remember which fake users we had
    $pool->on(change_start => sub {
        my $state = shift;
        %unloaded_users = ();
        $state->{adduser} = \%unloaded_users;
    }, 'adduser.change');
    
    # on change end, any users remaining here were not reloaded,
    # so dispose of them
    $pool->on(change_end => sub {
        my $state = shift;
        return if !$state->{adduser};
        %unloaded_users = %{ $state->{adduser} };
        delete_user($_) for values %unloaded_users;
        %unloaded_users = ();
    }, 'adduser.change');
}

sub add_user {
    my ($mod, $event, $id, %opts) = @_;

    # already existed at this ID
    if (my $exists = delete $unloaded_users{$id}) {

        # same owner; we can preserve it
        if ($exists->{adduser_owner} eq $mod->name) {
            update_user($exists, %opts);
            $mod->list_store_add(added_users => $exists->id);
            return $exists;
        }

        # otherwise, dispose of it now
        L("User already exists by ID '$id' from $$exists{adduser_owner}");
        delete_user($exists);
    }

    # create
    my $user = $pool->new_user(
      # nick  => defaults to UID
      # cloak => defaults to host
        ident  => 'user',
        host   => ($opts{server} || $me)->name,
        real   => $opts{nick} || 'realname',
        source => $me->id,
        ip     => '0',
        fake   => 1,
        %opts,
        adduser_id      => $id,
        adduser_owner   => $mod->name
    ) or return;
    L('New virtual user '.$user->full);

    # propagate
    broadcast(new_user => $user);
    $user->fire('initially_propagated');
    $user->{initially_propagated}++;
    
    # simulate initialization
    $user->{init_complete}++;

    $mod->list_store_add(added_users => $user->id);
    return $user;
}

sub update_user {
    my ($user, %opts) = @_;
    return if !$user->{fake};
    # TODO
}

sub delete_user {
    my $user = shift;
    return if !$user->{fake};
    $user->quit('Unloaded');
}

sub on_unload {
    my $mod = shift;
    foreach my $uid ($mod->list_store_items('added_users')) {
        my $user = $pool->lookup_user($uid) or next;
        next if !$user->{fake};
        $unloaded_users{ $user->{adduser_id} } = $user;
    }
}

$mod
