# Copyright (c) 2014, Mitchell Cooper
#
# @name:            "Git"
# @package:         "M::Git"
# @description:     "git repository management"
#
# @depends.modules: ['Base::UserCommands', 'JELP::Base']
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Git;

use warnings;
use strict;
use 5.010;

use utils qw(col);

our ($api, $mod, $pool);

sub init {
    $mod->register_user_command(
        name        => 'git',
        description => 'update the IRCd git repository',
        parameters  => '-oper(git) any(opt)',
        code        => \&ucmd_git,
        fantasy     => 1
    ) or return;
    
    return 1;
}

sub ucmd_git {
    #my ($user, $data
}

$mod