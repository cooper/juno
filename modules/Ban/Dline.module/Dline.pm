# Copyright (c) 2016, Mitchell Cooper
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
my $KILL_CONN;

sub init {
    $KILL_CONN = $mod->get_ban_action('kill');
    $mod->register_ban_type(
        name       => 'dline',          # ban type
        add_cmd    => 'dline',          # add command
        del_cmd    => 'undline',        # delete command
        reason     => 'D-Lined',        # reason prefix
        conn_code  => \&conn_matches,   # connection matcher
        match_code => \&_match,         # match checker
    );
}

sub _match {
    my $str = shift;

    # TODO: don't allow non-IPs

    # does it match a user?
    if (my $user = $pool->lookup_user_nick($str)) {
        return $user->{ip};
    }

    return $str;
}

sub conn_matches {
    my ($conn, $ban) = @_;
    return $KILL_CONN
        if utils::irc_match($conn->{ip}, $ban->{match});
    return;
}

$mod
