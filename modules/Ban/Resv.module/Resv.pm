# Copyright (c) 2016, Mitchell Cooper
#
# @name:            'Ban::Resv'
# @package:         'M::Ban::Resv'
# @description:     'reserve nicknames matching a mask'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
# @depends.modules: 'Ban'
#
package M::Ban::Resv;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

sub init {
    $mod->register_ban_type(
        name            => 'resv',           # ban type
        hname           => 'reserve',        # human-readable name
        add_cmd         => 'resv',           # add command
        del_cmd         => 'unresv' ,        # delete command
        reason          => 'Reserved',       # reason prefix
        activate_code   => \&activate_resv,  # activation code
        disable_code    => \&expire_resv,    # expire code
        match_code      => \&_match          # match checker
    );
}

sub _match {
    my $str = shift;
    return $str;
}

sub activate_resv {
    print "ACTIVATE RESV: @_\n";
    my $ban = shift;
    $pool->add_resv($ban->match, $ban->expires);
}

sub expire_resv {
    my $ban = shift;
    $pool->delete_resv($ban->match);
}

$mod
