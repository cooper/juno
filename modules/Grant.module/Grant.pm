# Copyright (c) 2014, mitchell cooper
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

use utils qw(simplify notice);

our ($api, $mod, $pool);

our %user_commands = (GRANT => {
    code    => \&grant,
    desc    => 'grant privileges to a user',
    params  => '-oper(grant) user ...'
});

our %oper_notices = (grant => '%s granted flags to %s: %s');

sub grant {
    my ($user, $event, $t_user, @flags) = @_;

    # add the flags.
    @flags = simplify(@flags);
    @flags = $t_user->add_flags(@flags);
    
    # no new flags.
    if (!@flags) {
        $user->server_notice(grant => 'User already has those flags');
        return;
    }

    # user isn't an IRC cop yet.
    if (!$t_user->is_mode('ircop')) {
        my $mode   = $t_user->{server}->umode_letter('ircop');
        my $result = $t_user->handle_mode_string("+$mode", 1) or return;
        $pool->fire_command_all(umode => $t_user, $result);
    }

    # tell other servers about the flags.
    $pool->fire_command_all(oper => $t_user, @flags);
 
    # note: these will come from the server the GRANT command is issued on.   
    $t_user->server_notice("You now have flags: @{ $t_user->{flags} }") if $t_user->{flags};
    $t_user->numeric('RPL_YOUREOPER');
    
    notice(grant => $user->{nick}, $t_user->{nick}, "@flags");
    $user->server_notice(grant => "$$t_user{nick} was granted: @flags");
    return 1;
}

$mod