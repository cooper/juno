# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-MacBook-Pro.local
# Sat Feb 14 17:58:20 EST 2015
# Kline.pm
#
# @name:            'Ban::Kline'
# @package:         'M::Ban::Kline'
# @description:     'ban users from server by hostmask'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
# @depends.modules+ 'Ban'
#
package M::Ban::Kline;

use warnings;
use strict;
use 5.010;

use utils qw(irc_match);

our ($api, $mod, $pool);
my $KILL_CONN;

sub init {
    $KILL_CONN = $mod->get_ban_action('kill');
    $mod->register_ban_type(
        name       => 'kline',          # ban type
        add_cmd    => 'kline',          # add command
        del_cmd    => 'unkline',        # delete command
        reason     => 'K-Lined',        # reason prefix
        user_code  => \&user_or_conn_matches,   # user matcher
        conn_code  => \&user_or_conn_matches,   # connection matcher
        match_code => \&_match,         # match checker
    );
}

sub _match {
    my $str = shift;

    # does it match a user?
    if (my $user = $pool->lookup_user_nick($str)) {
        return '*@'.$user->{host};
    }

    # user[@]host only
    my @parts  = utils::pretty_mask_parts($str);
    my $result = "$parts[1]\@$parts[2]";

    return if $result eq '*@*';
    return $result;
}

sub user_or_conn_matches {
    my ($user_conn, $ban) = @_;
    my ($ident, $host, $ip) = @$user_conn{ qw(ident host ip) };
    return unless length $ident;

    return $KILL_CONN
        if irc_match("$ident\@$host", $ban->match);

    return $KILL_CONN
        if irc_match("$ident\@$ip",   $ban->match);

    return;
}

$mod
