# Copyright (c) 2009-16, Mitchell Cooper
#
# @name:            "Monitor"
# @package:         "M::Monitor"
# @description:     "provides client availability notifications"
#
# @depends.bases:   [ 'UserNumerics', 'UserCommands' ]
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Monitor;

use warnings;
use strict;
use 5.010;

use utils qw(conf irc_lc);

our ($api, $mod, $me, $pool);
my $monitor;

our %user_numerics = (
    RPL_MONONLINE    => [ 730, ':%s'                            ],
    RPL_MONOFFLINE   => [ 731, ':%s'                            ],
    RPL_MONLIST      => [ 732, ':%s'                            ],
    RPL_ENDOFMONLIST => [ 733, ':End of MONITOR list'           ],
    ERR_MONLISTFULL  => [ 734, '%d %s :Monitor list is full'    ]
);

our %user_commands = (MONITOR => {
    desc   => 'manage client availability notifications',
    params => '* *(opt)',
    code   => \&monitor
});

sub init {

    # find the monitor table
    $monitor = $pool->{monitor} ||= {};

    # add the MONITOR token to RPL_ISUPPORT
    $me->on(supported => sub {
        my (undef, undef, $supported) = @_;

        # if it is 0 or undef, this is unlimited
        my $limit = conf('limit', 'monitor') or return;

        $supported->{MONITOR} = $limit;
    }, 'monitor.limit');

    # hooks for user changes.
    # note that we use initially_set_modes such that, if cloaking is
    # automatic on connect, it will have already been enabled.
    $pool->on('user.quit' =>
        \&on_user_quit, 'monitor.clear');
    $pool->on('user.will_change_nick' =>
        \&monitor_signoff, 'monitor.update');
    $pool->on('user.change_nick' =>
        \&monitor_signon, 'monitor.update');
    $pool->on('user.initially_set_modes' =>
        \&monitor_signon, 'monitor.check');

    return 1;
}

my %sub_cmds = (
    '+' => \&monitor_add,
    '-' => \&monitor_remove,
    'C' => \&monitor_clear,
    'L' => \&monitor_list,
    'S' => \&monitor_sync
);

sub check_targets {
    my ($user, $targets) = @_;

    # no targets provided
    if (!defined $targets) {
        $user->numeric(ERR_NEEDMOREPARAMS => 'MONITOR');
        return;
    }

    # convert to a list
    $targets = [ split /,/, $targets ]
        unless ref $targets;

    return $targets;
}

# MONITOR
sub monitor {
    my ($user, $event, $sub_cmd, $targets) = @_;
    if (my $code = $sub_cmds{ uc $sub_cmd }) {
        return $code->($user, $targets);
    }
    return;
}

# MONITOR +
sub monitor_add {
    my ($user, $targets) = @_;
    $targets = check_targets($user, $targets) or return;
    my $limit = conf('limit', 'monitor');

    # add each nick
    my (@good, @bad, @limited);
    my $their_monitor = $user->{monitor} ||= [];
    my %already_have  = map { $_ => 1 } @$their_monitor;
    while (my $nick = shift @$targets) {

        # limit reached
        if (@$their_monitor >= $limit) {
            push @limited, $nick, @$targets;
            last;
        }

        # skip nicks already being monitored
        $nick = irc_lc($nick);
        next if $already_have{$nick};

        # add this user to the monitor table;
        # add this nick to the user's monitor instance
        my $mon_inst = $monitor->{$nick} ||= [];
        push @$mon_inst, $user->id;
        push @$their_monitor, $nick;

        my $found = $pool->lookup_user_nick($nick);
        push @good, $found->full if  $found;
        push @bad,  $nick        if !$found;
    }

    split_numeric($user, RPL_MONONLINE  => @good);
    split_numeric($user, RPL_MONOFFLINE => @bad);
    $user->numeric(ERR_MONLISTFULL => $limit, join(',', @limited))
        if @limited;
    return 1;
}

# MONITOR -
sub monitor_remove {
    my ($user, $targets, $quiet) = @_;
    $targets = check_targets($user, $targets) or return;

    # remove the user from each monitor instance
    foreach my $nick (@$targets) {
        $nick = irc_lc($nick);
        my $mon_inst      = $monitor->{$nick}        or next;
        my $their_monitor = $user->{monitor}         or next;
        @$mon_inst        = grep { $_ != $user->id } @$mon_inst;
        @$their_monitor   = grep { $_ ne $nick     } @$their_monitor;
    }

    return 1;
}

# MONITOR C
sub monitor_clear {
    my $user = shift;
    my $their_monitor = delete $user->{monitor} or return;
    monitor_remove($user, $their_monitor, 1);
}

# MONITOR L
sub monitor_list {
    my $user = shift;
    my $their_monitor = $user->{monitor} || [];
    split_numeric($user, RPL_MONLIST => @$their_monitor);
    $user->numeric(RPL_ENDOFMONLIST =>);
}

# MONITOR S
sub monitor_sync {
    my $user = shift;
    my $their_monitor = $user->{monitor} or return;

    my (@good, @bad);
    foreach my $nick (@$their_monitor) {
        my $found = $pool->lookup_user_nick($nick);
        push @good, $found->full if  $found;
        push @bad,  $nick        if !$found;
    }

    split_numeric($user, RPL_MONONLINE  => @good);
    split_numeric($user, RPL_MONOFFLINE => @bad);
}

# sends zero or more numeric replies for a list of entires,
# taking the message byte length limit into account
sub split_numeric {
    my ($user, $numeric, @entries) = @_;
    my $base_length = length $user->simulate_numeric($numeric => '');
    my ($str_i, @strs) = -1;
    foreach my $entry (@entries) {
        my $new_length = 3 + $base_length + length $entry;
        if ($str_i == -1 || $new_length > 512) {
            $strs[++$str_i] = $entry;
            next;
        }
        $strs[$str_i] .= ",$entry";
    }
    $user->numeric($numeric => $_) for @strs;
}

# notify users of a signon
sub monitor_signon {
    my $user = shift;
    my $mon_inst = $monitor->{ irc_lc($user->{nick}) } or return;
    foreach my $id (@$mon_inst) {
        my $listener = $pool->lookup_user($id) or next;
        $listener->numeric(RPL_MONONLINE => $user->full);
    }
}

# notify users of a signoff
sub monitor_signoff {
    my $user = shift;
    my $mon_inst = $monitor->{ irc_lc($user->{nick}) } or return;
    foreach my $id (@$mon_inst) {
        my $listener = $pool->lookup_user($id) or next;
        $listener->numeric(RPL_MONOFFLINE => $user->full);
    }
}

sub on_user_quit {
    my $user = shift;

    # if it's a local user, clear his monitor list
    monitor_clear($user) if $user->is_local;

    # notify clients monitoring this person
    monitor_signon($user);
}

$mod;
