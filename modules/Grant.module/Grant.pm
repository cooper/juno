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
# @depends.bases:   [ 'UserCommands', 'OperNotices' ]
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Grant;

use warnings;
use strict;
use 5.010;

use utils qw(gnotice simplify broadcast);

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
    @flags = simplify(@flags) or return;

    # notice
    gnotice($user, grant =>
        $user->notice_info, $t_user->notice_info, "@flags");

    # local user
    if ($t_user->is_local) {

        # add the flags
        @flags = $user->add_flags(@flags);
        $user->update_flags;

        # tell other servers
        broadcast(oper => $user, @flags);
    }

    # send out FOPER.
    else {
        $t_user->forward(force_oper => $me, $t_user, @flags);
    }

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

    # notice
    gnotice($user, ungrant =>
        $user->notice_info, $t_user->notice_info, "@flags");

    # local user
    if ($t_user->is_local) {

        # remove the flags
        @flags = $user->remove_flags(@flags);
        $user->update_flags;

        # tell other servers
        broadcast(oper => $user, map { "-$_" } @flags);
    }

    # send out FOPER.
    else {
        $t_user->forward(foper =>
            $me, $t_user,
            map { "-$_" } @flags
        );
    }


    return 1;
}

$mod
