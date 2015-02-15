# Copyright (c) 2015, mitchell cooper
#
# Created on Mitchells-MacBook-Pro.local
# Sat Feb 15 17:58:20 EST 2015
# Dline.pm
#
# @name:            'Ban::Dline'
# @package:         'M::Ban::Dline'
# @description:     'ban connections from server by IP'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
# @depends.modules: 'Ban'
#
package M::Ban::Dline;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

sub init {
    $mod->register_ban_type(
        name       => 'dline',          # ban type
        add_cmd    => 'dline',          # add command
        del_cmd    => 'undline',        # delete command
        reason     => 'D-Lined',        # reason prefix
        class      => 'conn',           # bans apply to
        conn_code  => \&conn_matches,   # connection matcher
        match_code => \&_match,         # match checker
    );
}

sub _match {
    my $str = shift;
    
    # does it match a user?
    if (my $user = $pool->lookup_user_nick($str)) {
        return $user->{ip};
    }
    
    # TODO: check if valid IP
    
    return $str;
}

sub conn_matches {
    my ($conn, $ban) = @_;
    return utils::irc_match($conn->{ip}, $ban->{match});
}

$mod

