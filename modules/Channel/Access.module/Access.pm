# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "Channel::Access"
# @package:         "M::Channel::Access"
# @description:     "implements channel access mode"
#
# @depends.modules: ['Base::ChannelModes', 'Base::UserCommands']
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Channel::Access;

use warnings;
use strict;
use 5.010;

use utils qw(conf match);

our ($api, $mod, $me, $pool);

our %user_commands = (
    UP => {
        desc   => 'grant yourself with your access privileges',
        params => 'channel(inchan)',
        code   => \&cmd_up,
        fntsy  => 1
    },
    DOWN => {
        desc   => 'remove all channel status modes',
        params => 'channel(inchan)',
        code   => \&cmd_down,
        fntsy  => 1
    }
);

sub init {

    # register access mode block.
    $mod->register_channel_mode_block(
        name => 'access',
        code => \&cmode_access
    ) or return;

    # events.
    $pool->on('channel.user_joined'    => \&on_user_joined,    with_eo => 1);
    $pool->on('user.account_logged_in' => \&on_user_logged_in, with_eo => 1);

    return 1;
}

sub cmd_up {
    my ($user, $event, $channel) = @_;
    
    # pretend join.
    on_user_joined($channel, undef, $user);
    
}

sub cmd_down {
    my ($user, $event, $channel) = @_;
    
    # find user's status modes.
    my @letters;
    foreach my $level (keys %ircd::channel_mode_prefixes) {
        my ($letter, $symbol, $name) = @{ $ircd::channel_mode_prefixes{$level} };
        push @letters, $letter if $channel->list_has($name, $user);
    }
    
    # no modes.
    return 1 unless scalar @letters;
    
    # create mode string.
    my $letters = join '', @letters;
    my $uids    = ($user->{uid} .q( )) x length $letters;
    my $sstr    = "-$letters $uids";
    
    # handle it and forward to users and servers as needed.
    $channel->do_mode_string($user->{server}, $user->{server}, $sstr, 1, 1);
    
    return 1;
}

# access mode handler.
sub cmode_access {
    my ($channel, $mode) = @_;

    # view access list.
    if (!defined $mode->{param} && $mode->{source}->isa('user') && $mode->{state}) {
        # TODO
        return;
    }

    # for setting and unsetting -
    # split status:mask. status can be either a status name or a letter.
    return unless defined $mode->{param};
    my ($status, $mask) = split ':', $mode->{param}, 2;
    
    # if either is not present, this is invalid.
    return if !defined $status || !defined $mask;

    # ensure that the status is valid.
    my $final_status;
    
    # first, let's see if this is a status name.
    if (defined $mode->{server}->cmode_letter($status)) {
        $final_status = $status;
    }

    # next, check if it is a status letter.
    else {
        $final_status = $mode->{server}->cmode_name($status);
    }
    
    # neither worked. give up.
    return if !defined $final_status;
    
    # ensure that this user is at least the $final_status unless forced.
    # TODO: should we always allow over-protocol?
    if (!$mode->{force} && $mode->{source}->isa('user')) {
        my $level1 = $channel->user_get_highest_level($mode->{source});
        my $level2 = conf('prefixes', $final_status)->[2];
        # TODO: major issues if improper configuration values are not array references.
        
        # the level being set is higher than the level of the setter.
        if ($level2 > $level1) {
            $mode->{send_no_privs} = 1;
            return;
        }
        
    }
    
    # set the parameter to the desired mode_name:mask format.
    $mode->{param} = $final_status.q(:).$mask;

    # setting.
    if ($mode->{state}) { 
    
        # this is valid; add it to the access list.
        $channel->add_to_list('access', $mode->{param},
            setby => $mode->{source}->name,
            time  => time
        );
        
    }

    # unsetting.
    else {
        $channel->remove_from_list('access', $mode->{param});
    }

    return 1;
}

# user joined channel event handler.
sub on_user_joined {
    my ($channel, $event, $user) = @_;
    my (@matches, @letters);
    return unless $user->is_local;
    
    # look for matches.
    my @items = $channel->list_elements('access') or return 1;
    foreach my $mask (@items) {
        my $realmask = (split ':', $mask, 2)[-1];
        
        # found a match.
        push @matches, $mask if match($user, $realmask);
        
    }
    
    
    # determine levels from names.
    my %levels;
    foreach my $level (keys %ircd::channel_mode_prefixes) {
        my ($letter, $symbol, $name) = @{ $ircd::channel_mode_prefixes{$level} };
        @levels{ $name, $letter } = ($level, $level);
    }
    
    # continue through matches.
    my %done;
    my $highest = -inf;
    foreach my $match (@matches) {
        
        # there is match, so let's continue.
        my ($modename, $mask) = split ':', $match, 2;
        
        # find the mode letter.
        my $letter = $me->cmode_letter($modename);
        
        # user already has this status.
        next if $done{$letter};
        next if $channel->user_is($user, $modename);
        
        # is this higher?
        if (exists $levels{$modename} && $levels{$modename} > $highest) {
            $highest = $levels{$modename};
        }
        
        push @letters, $letter;
        $done{$letter} = 1;
    }
    
    return 1 unless scalar @letters;
    
    # here, perhaps an existing status is higher than one about to be granted.
    my $maybe_higher = $channel->user_get_highest_level($user);
    $highest = $maybe_higher if $maybe_higher > $highest;
    
    # don't give anything less than their highest status
    # (other than op which will be granted below.)
    # this prevents things like +qohv or +hv, etc.
    @letters = grep { $levels{$_} >= $highest } @letters;
    
    # if they have >0 status, give o as well.
    my ($op, $give_op) = $me->cmode_letter('op');
    if (!$channel->user_is($user, 'op') and not $op ~~ @letters) {
        foreach my $level (keys %ircd::channel_mode_prefixes) {
            my ($letter, $symbol, $name) = @{ $ircd::channel_mode_prefixes{$level} };
            $give_op = 1, last if $letter ~~ @letters && $level > 0;
        }
        push @letters, $op if $give_op;
    }

    # create mode string.
    my $letters = join '', @letters;
    my $uids    = (q( ).$user->{uid}) x length $letters;
    my $sstr    = "+$letters$uids";
    
    # handle it locally (this sends to other servers too).
    # ($channel, $server, $source, $modestr, $force, $over_protocol)
    $channel->do_mode_string($user->{server}, $user->{server}, $sstr, 1, 1);
    
    return 1;
}

# user logged in to an account.
sub on_user_logged_in {
    my ($user, $event, $act) = @_;
    return unless $user->is_local;
    
    # pretend join.
    on_user_joined($_, undef, $user) foreach $user->channels;
    
}

$mod