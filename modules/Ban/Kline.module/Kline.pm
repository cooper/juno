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
# @depends.modules: 'Ban'
#
package M::Ban::Kline;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

sub init {
    $mod->register_ban_type(
        name       => 'kline',          # ban type
        add_cmd    => 'kline',          # add command
        del_cmd    => 'unkline',        # delete command
        reason     => 'K-Lined',        # reason prefix
        class      => 'user',           # bans apply to
        user_code  => \&user_matches,   # user matcher
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

sub user_matches {
    my ($user, $ban) = @_;
    return 1 if utils::irc_match($user->{ident}.'@'.$user->{host}, $ban->{match});
    return 1 if utils::irc_match($user->{ident}.'@'.$user->{ip},   $ban->{match});
    return;
}

$mod
