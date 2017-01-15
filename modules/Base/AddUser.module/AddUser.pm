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

sub init {
    $mod->register_module_method('add_user') or return;
}

sub add_user {
    my ($mod, $event, %opts) = @_;

    # create
    my $user = $pool->new_user(
      # nick  => defaults to UID
      # cloak => defaults to host
        ident  => 'user',
        host   => ($opts{server} || $me)->name,
        real   => 'realname',
        source => $me->id,
        ip     => '0',
        time   => time,
        fake   => 1,
        %opts
    );
    L('New virtual user '.$user->full);

    # propagate
    broadcast(new_user => $user);
    $user->fire('initially_propagated');
    $user->{initially_propagated}++;
    $user->{init_complete}++;

    return $user;
}

$mod
