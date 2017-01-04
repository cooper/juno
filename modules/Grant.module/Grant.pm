# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-Mac-mini.local
# Fri Aug  8 15:47:20 EDT 2014
# Grant.pm
#
# @name:            'Grant'
# @package:         'M::Grant'
# @description:     'grant privileges to a user'
#
# @depends.modules: ['Base::UserCommands', 'Base::OperNotices']
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Grant;

use warnings;
use strict;
use 5.010;

use utils qw(gnotice simplify);

our ($api, $mod, $pool, $me);

our %user_commands = (
    GRANT => {
        code    => \&grant,
        desc    => 'grant privileges to a user',
        params  => '-oper(grant) user ...'
    },
    UNGRANT => {
        code    => \&ungrant,
        desc    => "revoke a user's privileges",
        params  => '-oper(grant) user ...'
    }
);

our %oper_notices = (
    grant   => '%s granted flags to %s: %s',
    ungrant => '%s removed flags from %s: %s'
);

sub grant {
    my ($user, $event, $t_user, @flags) = @_;
    @flags = simplify(@flags);

    # send out FOPER.
    $t_user->{location}->fire_command(force_oper => $me, $t_user, @flags);

    gnotice($user, grant =>
        $user->notice_info, $t_user->notice_info, "@flags");
    return 1;
}

sub ungrant {
    my ($user, $event, $t_user, @flags) = @_;

    # removing all flags.
    @flags = @{ $t_user->{flags} } if $flags[0] eq '*';
    @flags = simplify(@flags);

    # none removed.
    if (!@flags) {
        $user->server_notice(grant => "User doesn't have any of those flags");
        return;
    }

    # send out FOPER.
    $t_user->{location}->fire_command(foper =>
        $me, $t_user,
        map { "-$_" } @flags
    );

    @flags = '(all)' if !scalar @{ $t_user->{flags} };
    gnotice($user, ungrant =>
        $user->notice_info, $t_user->notice_info, "@flags");
    return 1;
}

$mod
