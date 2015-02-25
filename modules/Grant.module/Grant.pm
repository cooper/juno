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

use utils qw(simplify notice ref_to_list);

our ($api, $mod, $pool);

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

    # add the flags.
    @flags = simplify(@flags);
    @flags = $t_user->add_flags(@flags);
    
    # no new flags.
    if (!@flags) {
        $user->server_notice(grant => 'User already has those flags');
        return;
    }

    # user isn't an IRC cop yet.
    my $already_irc_cop = $t_user->is_mode('ircop');
    if (!$already_irc_cop) {
        my $mode = $t_user->{server}->umode_letter('ircop');
        $t_user->do_mode_string_unsafe("+$mode", 1);
    }

    # tell other servers about the flags.
    $pool->fire_command_all(oper => $t_user, @flags);
 
    # note: these will come from the server the GRANT command is issued on.
    my @all = ref_to_list($t_user->{flags});
    $t_user->server_notice("You now have flags: @all") if @all;
    $t_user->numeric('RPL_YOUREOPER') unless $already_irc_cop;
    
    notice(grant => $user->{nick}, $t_user->{nick}, "@flags");
    $user->server_notice(grant => "$$t_user{nick} was granted: @flags");
    return 1;
}

sub ungrant {
    my ($user, $event, $t_user, @flags) = @_;

    # removing all flags and unsetting oper.
    my $unopered = $flags[0] eq '*';
    if ($unopered) {
        @flags   = @{ $t_user->{flags} };
        my $mode = $t_user->{server}->umode_letter('ircop');
        $t_user->do_mode_string_unsafe("-$mode", 1);
    }

    # remove the flags.
    @flags = simplify(@flags);
    @flags = $t_user->remove_flags(@flags) unless $unopered;
    
    # none removed.
    if (!@flags && !$unopered) {
        $user->server_notice(grant => "User doesn't have any of those flags");
        return;
    }

    # tell other servers about the flags.
    $pool->fire_command_all(oper => $t_user, map { "-$_" } @flags);
 
    # note: these will come from the server the GRANT command is issued on.
    my @all = ref_to_list($t_user->{flags});
    
    # for notices
    if (!@all) {
        @all   = '(no flags)';
        @flags = '(all flags)';
    }
    
    # notices
    $t_user->server_notice("You now have flags: @all");
    notice(ungrant => $user->{nick}, $t_user->{nick}, "@flags");
    $user->server_notice(ungrant => "$$t_user{nick} was revoked of: @flags");
    
    return 1;
}

$mod