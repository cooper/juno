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

our ($api, $mod, $pool, $conf, $me);

############
### JELP ###
############

*jelp_message = *M::JELP::Base::jelp_message;

# keys that are valid for propagation.
# note that 'reason' is not in this list because it's special.
my %good_keys = map { $_ => 1 }
    qw();

our %jelp_outgoing_commands = (
    ban     => \&out_ban,
    banidk  => \&out_banidk,
    baninfo => \&out_baninfo,
    bandel  => \&out_bandel
);

our %jelp_incoming_commands = (
    BAN => {
        params  => '...',
        code    => \&in_ban
    },
    BANINFO => {
                   # @from_user=uid       :sid BANINFO    id  type match :reason
        params   => '@from_user=user(opt) -source(server) *   *    *     :(opt)',
        code     => \&in_baninfo
    },
    BANIDK => {
        params  => '...',
        code    => \&in_banidk
    },
    BANDEL => {    # @from_user=uid      :sid BANDEL     id1 id2...
        params  => '@from_user=user(opt) -source(server) ...',
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

    # already did or no bans
    return 1 if $server->{bans_negotiated}++;
    my @bans = M::Ban::all_bans() or return 1;

    $server->fire_command(ban => @bans);
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
        $ban->clear_recent_source;
        $str .= ' ' if $str;
        $str .= $ban->id.q(,).$ban->modified;
    }

    ":$$me{sid} BAN $str"
}

# BANINFO: share ban data
sub out_baninfo {
    my ($to_server, $ban) = @_;
    my $str = '';

    # this info is added as tags
    my %tags = map { $_ => $ban->$_ } qw(
        duration added modified expires
        lifetime auser aserver
    );

    # get user set by, if available
    $tags{from_user} = $ban->recent_user;

    return jelp_message(
        command => 'BANINFO',
        source  => $me,
        params  => [ $ban->id, $ban->type, $ban->match, $ban->reason ],
        tags    => \%tags
    )->data;
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
    my @ban_ids = map $_->id, @_;
    return if !@ban_ids;

    # get user deleted by
    my $from = $_[0]->recent_user;

    return jelp_message(
        command => 'BANDEL',
        source  => $me,
        params  => \@ban_ids,
        tags    => { from_user => $from }
    )->data;
}

# Incoming
# -----

# BAN: burst bans
sub in_ban {
    my ($server, $msg, @items) = @_;
    my @idk;
    foreach my $item (@items) {

        # split into ban ID and modified time.
        my ($id, $modified) = split /,/, $item;
        next if !length $id || !length $modified;

        # does this ban exist?
        # ignore this if our existing mod time is the same or newer
        if (my $ban = M::Ban::ban_by_id($id)) {
            next if $ban->modified >= $modified;
        }

        push @idk, $id;
    }
    $server->fire_command(banidk => @idk) if @idk;
}

# BANINFO: share ban data
sub in_baninfo {
    my ($server, $msg, $from, $source_serv, $id, $type, $match, $reason) = @_;
    # $from may be a user object or it may be undef

    # consider: we may want to eventually ignore this message completely if the
    # stored modification time is equal or newer than the incoming one.
    # this is hardly necessary for the time being because BANINFO should never
    # be received unless the ban is being added or modified or we explicitly
    # requested its information during burst with BANIDK. however, BANINFO may
    # later be used by a user-initiated which would "resync" all global bans.

    # these things can be specified as tags, but all are optional
    my %possible_tags = map { $_ => $msg->tag($_) } qw(
        duration added modified expires
        lifetime auser aserver
    );
    defined $possible_tags{$_} or delete $possible_tags{$_}
        for keys %possible_tags;

    # create or update a ban based on the required parameters and optional tags.
    my $ban = M::Ban::create_or_update_ban(
        id      => $id,
        type    => $type,
        match   => $match,
        reason  => $reason,  # optional
        %possible_tags
    ) or return;

    #=== Forward ===#
    $ban->set_recent_source($from || $source_serv);
    $ban->notify_new($ban->recent_source);
    $msg->forward(baninfo => $ban);

    return 1;
}

# BANIDK: request ban data
sub in_banidk {
    my ($server, $msg, @ids) = @_;

    # send out ban info for each requested ID
    foreach my $id (@ids) {
        my $ban = M::Ban::ban_by_id($id) or next;
        $server->fire_command(baninfo => $ban);
    }

    return 1;
}

# BANDEL: delete a ban
sub in_bandel {
    my ($server, $msg, $from, $source_serv, @ids) = @_;
    my @bans;

    # handle each ban
    foreach my $id (@ids) {

        # find and delete the ban
        my $ban = M::Ban::ban_by_id($id) or next;

        $ban->set_recent_source($from || $server);
        $ban->disable;
        $ban->notify_delete($ban->recent_source);

        push @bans, $ban;
    }

    #=== Forward ===#
    $msg->forward(bandel => @bans) if @bans;

    return 1;
}

$mod
