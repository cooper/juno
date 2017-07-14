# Copyright (c) 2017, Mitchell Cooper
#
# @name:            "AddUserTest"
# @package:         "M::AddUserTest"
# @description:     "AddUser API test"
#
# @depends.bases+   'AddUser'
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::AddUserTest;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

sub init {
    my $u = $mod->add_user('nickserv', nick => 'NickServ', cloak => 'asdfasdfasdf.com') or return;
    $u->handle('JOIN #k');
    $u->handle('PRIVMSG #k :Hello');
}

$mod
