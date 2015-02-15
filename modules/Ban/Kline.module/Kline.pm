# Copyright (c) 2015, mitchell cooper
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
my $ban_m;

sub init {
    $ban_m = $api->get_module('Ban') or return;
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
    my @parts = utils::pretty_mask_parts($str);
    return "$parts[1]\@$parts[2]";
    
}

sub user_matches {
    my ($user, $ban) = @_;
    return utils::irc_match($user->{ident}.'@'.$user->{host}, $ban->{match});
}

$mod

