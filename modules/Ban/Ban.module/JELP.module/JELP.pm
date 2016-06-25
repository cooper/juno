# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-MacBook-Pro.local
# Sat May 30 12:26:20 EST 2015
# JELP.pm
#
# @name:            'Ban::JELP'
# @package:         'M::Ban::JELP'
# @description:     'JELP ban propagation'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
# depends on JELP::Base, but don't put that here.
# companion submodule loading takes care of it.
#
package M::Ban::JELP;

use warnings;
use strict;
use 5.010;

M::Ban->import(qw(
    enforce_ban         activate_ban        enforce_ban
    get_all_bans        ban_by_id
    add_or_update_ban   delete_ban_by_id
));

our ($api, $mod, $pool, $conf, $me);

############
### JELP ###
############

my %jelp_commands = (
    BAN => {
        params  => '@rest',
        code    => \&scmd_ban,
        forward => 2 # never forward during burst
    },
    BANINFO => {
        params   => '@rest',
        code     => \&scmd_baninfo,
        forward  => 1
    },
    BANIDK => {
        params  => '@rest',
        code    => \&scmd_banidk
    },
    BANDEL => {
        params  => '@rest',
        code    => \&scmd_bandel,
        forward => 1
    }
);

sub init {
    return if !$api->module_loaded('JELP::Base');
    
    # IRCd event for burst.
    $pool->on('server.send_jelp_burst' => \&burst_bans,
        name    => 'jelp.banburst',
        after   => 'jelp.mainburst',
        with_eo => 1
    );
    
    # outgoing commands.
    $mod->register_outgoing_command(
        name => $_->[0],
        code => $_->[1]
    ) || return foreach (
        [ ban     => \&ocmd_ban     ],
        [ banidk  => \&ocmd_banidk  ],
        [ baninfo => \&ocmd_baninfo ],
        [ bandel  => \&ocmd_bandel  ]
    );
    
    # incoming commands.
    $mod->register_jelp_command(
        name       => $_,
        parameters => $jelp_commands{$_}{params},
        code       => $jelp_commands{$_}{code},
        forward    => $jelp_commands{$_}{forward}
    ) || return foreach keys %jelp_commands;
    
    return 1;
}

sub burst_bans {
    my ($server, $fire, $time) = @_;
    if (!$server->{bans_negotiated}) {
        $server->fire_command(ban => get_all_bans());
        $server->{bans_negotiated} = 1;
    }
}

# Outgoing
# -----

# BAN: burst bans
sub ocmd_ban {
    my $to_server = shift;
    return unless @_;
    my $str = '';
    foreach my $ban (@_) {
        $str .= ' ' if $str;
        $str .= $ban->{id}.q(,).$ban->{modified};
    }
    ":$$me{sid} BAN $str"
}

# BANINFO: share ban data
sub ocmd_baninfo {
    my ($to_server, $ban) = @_;
    my $str = '';
    foreach my $key (keys %$ban) {
        next if $key eq 'reason';
        my $value = $ban->{$key};
        next unless length $value;
        next if ref $value;
        $str .= "$key $value ";
    }
    my $reason = $ban->{reason} // '';
    ":$$me{sid} BANINFO $str:$reason"
}

# BANIDK: request ban data
sub ocmd_banidk {
    my $to_server = shift;
    my $str = join ' ', @_;
    ":$$me{sid} BANIDK $str"
}

# BANDEL: delete a ban
sub ocmd_bandel {
    my $to_server = shift;
    my $str = join ' ', @_;
    ":$$me{sid} BANDEL $str"
}

# Incoming
# -----

# BAN: burst bans
sub scmd_ban {
    my ($server, $msg, @items) = @_;

    # check ban times
    my (@i_dk, @u_dk, %done);
    foreach my $item (@items) {
        my @parts = split /,/, $item;
        next if @parts % 2;
        my ($id, $modified) = @parts;
        
        # does this ban exist?
        if (my %ban = ban_by_id($id)) {
            next if $ban{modified} == $modified;
            push @i_dk, $id if $modified > $ban{modified};
            push @u_dk, $id if $modified < $ban{modified};
        }
        
        push @i_dk, $id;
        $done{$id} = 1;
    }
    
    # if the server didn't mention some bans, send them out too
    push @u_dk, grep { !$done{$_} } map $_->{id}, get_all_bans();
    
    # FIXME: do I need u_dk or not?
    
    $server->fire_command(banidk => @i_dk) if @i_dk;
}

# BANINFO: share ban data
# :sid BANINFO key value key value :reason
sub scmd_baninfo {
    my ($server, $msg, @parts) = @_;
    
    # must be divisible by two.
    my $reason = pop @parts;
    return if @parts % 2;
    my %ban = @parts;
    $ban{reason} = $reason;
    
    # we need an ID at the very least
    return unless defined $ban{id};
    
    # update, enforce, and activate
    add_or_update_ban(%ban);
    enforce_ban(%ban);
    activate_ban(%ban);
    
}

# BANIDK: request ban data
sub scmd_banidk {
    my ($server, $msg, @ids) = @_;
    foreach my $id (@ids) {
        my %ban = ban_by_id($id) or next;
        $server->fire_command(baninfo => \%ban);
    }
}

# BANDEL: delete a ban
sub scmd_bandel {
    my ($server, $msg, @ids) = @_;
    foreach my $id (@ids) {
        delete_ban_by_id($id);
    }
}

$mod