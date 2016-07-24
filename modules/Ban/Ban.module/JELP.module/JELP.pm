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
    get_all_bans        ban_by_id
    delete_ban_by_id    add_update_enforce_activate_ban
));

our ($api, $mod, $pool, $conf, $me);

############
### JELP ###
############

# keys that are valid for propagation.
# note that 'reason' is not in this list because it's special.
my %good_keys = map { $_ => 1 }
    qw(id type match duration added modified expires auser aserver);

our %jelp_outgoing_commands = (
    ban     => \&out_ban,
    banidk  => \&out_banidk,
    baninfo => \&out_baninfo,
    bandel  => \&out_bandel
);

our %jelp_incoming_commands = (
    BAN => {
        params  => '@rest',
        code    => \&in_ban
    },
    BANINFO => {
        params   => '@rest',
        code     => \&in_baninfo
    },
    BANIDK => {
        params  => '@rest',
        code    => \&in_banidk
    },
    BANDEL => {
        params  => '@rest',
        code    => \&in_bandel
    }
);

sub init {

    # IRCd event for burst.
    $pool->on('server.send_jelp_burst' => \&burst_bans,
        name    => 'jelp.banburst',
        after   => 'jelp.mainburst',
        with_eo => 1
    );

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
sub out_ban {
    my $to_server = shift;
    return unless @_;

    # add IDs and modified times for each ban
    my $str = '';
    foreach my $ban (@_) {
        $str .= ' ' if $str;
        $str .= $ban->{id}.q(,).$ban->{modified};
    }

    ":$$me{sid} BAN $str"
}

# BANINFO: share ban data
sub out_baninfo {
    my ($to_server, $ban) = @_;
    my $str = '';

    # remove bogus keys
    delete @$ban{ grep !$good_keys{$_}, keys %$ban };

    # add each key and value
    foreach my $key (keys %$ban) {
        my $value = $ban->{$key};
        next unless length $value;
        next if ref $value;
        $str .= "$key $value ";
    }

    my $reason = $ban->{reason} // '';
    ":$$me{sid} BANINFO $str:$reason"
}

# BANIDK: request ban data
sub out_banidk {
    my $to_server = shift;
    my $str = join ' ', @_;
    ":$$me{sid} BANIDK $str"
}

# BANDEL: delete bans
sub out_bandel {
    my $to_server = shift;
    my $str = join ' ', map $_->{id}, @_;
    ":$$me{sid} BANDEL $str"
}

# Incoming
# -----

# BAN: burst bans
sub in_ban {
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
sub in_baninfo {
    my ($server, $msg, @parts) = @_;

    # the reason is always last
    my $reason = pop @parts;

    # the rest must be divisible by two
    return if @parts % 2;
    my %ban = (@parts, reason => $reason);

    # ignore unknown keys
    delete @ban{ grep !$good_keys{$_}, keys %ban };

    # validate, update, enforce, and activate
    %ban = add_update_enforce_activate_ban(%ban) or return;

    #=== Forward ===#
    $msg->forward(baninfo => \%ban);

    return 1;
}

# BANIDK: request ban data
sub in_banidk {
    my ($server, $msg, @ids) = @_;

    # send out ban info for each requested ID
    foreach my $id (@ids) {
        my %ban = ban_by_id($id) or next;
        $server->fire_command(baninfo => \%ban);
    }

    return 1;
}

# BANDEL: delete a ban
sub in_bandel {
    my ($server, $msg, @ids) = @_;

    foreach my $id (@ids) {

        # find and delete each ban
        my %ban = ban_by_id($id) or next;
        delete_ban_by_id($id);

        #=== Forward ===#
        $msg->forward(bandel => \%ban);

    }

    return 1;
}

$mod
