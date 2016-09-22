# Copyright (c) 2010-16, Mitchell Cooper
#
# @name:            "JELP::Outgoing"
# @package:         "M::JELP::Outgoing"
# @description:     "basic set of JELP outgoing commands"
#
# @depends.modules: "JELP::Base"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::JELP::Outgoing;

use warnings;
use strict;
use 5.010;

use Scalar::Util qw(blessed);

our ($api, $mod, $me, $pool);

my %ocommands = (
    quit            => \&quit,
    new_server      => [ \&sid, \&aum, \&acm ],
    new_user        => \&uid,
    nickchange      => \&nickchange,
    umode           => \&umode,
    privmsgnotice   => \&privmsgnotice,
    join            => \&_join,
    oper            => \&oper,
    away            => \&away,
    return_away     => \&return_away,
    part            => \&part,
    topic           => \&topic,
    cmode           => \&cmode,
    channel_burst   => \&sjoin,
    kill            => \&skill,
    connect         => \&_connect,
    kick            => \&kick,
    num             => \&num,
    links           => \&links,
    whois           => \&whois,
    admin           => \&admin,
    motd            => \&motd,
    time            => \&_time,
    snotice         => \&snotice,
    version         => \&version,
    login           => \&login,                             # TODO: logout
    su_login        => \&su_login,                          # TODO: logout
    part_all        => \&partall,
    invite          => \&invite,
    save_user       => \&save,
    update_user     => \&userinfo,
    chghost         => \&chghost,
    realhost        => \&realhost,
    lusers          => \&lusers,
    users           => \&users,
    svsnick         => \&fnick,
    add_cmodes      => \&acm,
    add_umodes      => \&aum,
    burst           => \&burst,
    endburst        => \&endburst,
    ircd_rehash     => \&rehash,
    ircd_checkout   => \&checkout,
    ircd_update     => \&update,
    ircd_reload     => \&reload
);

sub init {

    # register outgoing commands
    $mod->register_outgoing_command(
        name => $_,
        code => $ocommands{$_}
    ) || return foreach keys %ocommands;

    # register server burst events.
    $pool->on('server.send_jelp_burst' => \&send_startburst,
        name     => 'jelp.startburst',
        with_eo  => 1,
        priority => 500
    );
    $pool->on('server.send_jelp_burst' => \&send_burst,
        name     => 'jelp.mainburst',
        with_eo  => 1
    );
    $pool->on('server.send_jelp_burst' => \&send_endburst,
        name     => 'jelp.endburst',
        with_eo  => 1,
        priority => -500
    );

    return 1;
}

sub send_startburst {
    my ($server, $fire, $time) = @_;
    $server->fire_command(burst => $me, $time);
}

sub send_burst {
    my ($server, $fire, $time) = @_;

    # servers and mode names
    my ($do, %done);

    # first, send modes of this server.
    $server->fire_command(add_umodes => $me);
    $server->fire_command(add_cmodes => $me);

    # don't send info for this server or the server we're sending to.
    $done{$server} = $done{$me} = 1;

    $do = sub {
        my $serv = shift;

        # already did this one.
        return if $done{$serv};

        # we learned about this server from the server we're sending to.
        return if defined $serv->{source} && $serv->{source} == $server->{sid};

        # we need to do the parent first.
        if (!$done{ $serv->{parent} } && $serv->{parent} != $serv) {
            $do->($serv->{parent});
        }

        # fire the command.
        $server->fire_command(new_server => $serv);
        $done{$serv} = 1;

    }; $do->($_) foreach $pool->all_servers;

    # users
    foreach my $user ($pool->global_users) {

        # ignore users the server already knows!
        next if $user->{server} == $server || $user->{source} == $server->{sid};

        $server->fire_command(new_user => $user);

        # oper flags
        if (scalar @{ $user->{flags} }) {
            $server->fire_command(oper => $user, @{ $user->{flags} })
        }

        # away reason
        if (exists $user->{away}) {
            $server->fire_command(away => $user)
        }

    }

    # channels, using compact CUM
    foreach my $channel ($pool->channels) {
        $server->fire_command(channel_burst => $channel, $me, $channel->users);
        $server->fire_command(topicburst => $channel) if $channel->topic;
    }

}

sub send_endburst {
    shift->fire_command(endburst => $me, time);
}

# this can take a server object, user object, or connection object.
sub quit {
    my ($to_server, $object, $reason, $from) = @_;
    $object = $object->type if $object->isa('connection');
    my $id  = $object->id;
    my $str = ":$id QUIT :$reason";
    if ($from) {
        my $from_id = $from->id;
        $str = "\@from=$from_id $str"
    }
    $str
}

# new user
sub uid {
    my ($to_server, $user) = @_;
    my $cmd = sprintf(
        'UID %s %d %s %s %s %s %s %s :%s',
        $user->{uid}, $user->{nick_time}, $user->mode_string,
        $user->{nick}, $user->{ident}, $user->{host},
        $user->{cloak}, $user->{ip}, $user->{real}
    );
    ":$$user{server}{sid} $cmd"
}

sub sid {
    my ($to_server, $serv) = @_;
    return if $to_server == $serv;

    # hidden?
    my $desc = $serv->{desc};
    $desc = "(H) $desc" if $serv->{hidden};

    my $cmd = sprintf(
        'SID %s %d %s %s %s :%s',
        $serv->{sid},   $serv->{time}, $serv->{name},
        $serv->{proto}, $serv->{ircd}, $desc
    );
    ":$$serv{parent}{sid} $cmd"
}

sub topicburst {
    my ($to_server, $channel) = @_;
    return unless $channel->topic;
    my $cmd = sprintf(
        'TOPICBURST %s %d %s %d :%s',
        $channel->name,
        $channel->{time},
        $channel->{topic}{setby},
        $channel->{topic}{time},
        $channel->{topic}{topic}
    );
    ":$$me{sid} $cmd"
}

# nick change
sub nickchange {
    my ($to_server, $user) = @_;
    ":$$user{uid} NICK $$user{nick}"
}

# user mode change
sub umode {
    my ($to_server, $user, $modestr) = @_;
    ":$$user{uid} UMODE $modestr"
}

# privmsg and notice
sub privmsgnotice {
    my ($to_server, $cmd, $source, $target, $message, %opts) = @_;

    # complex stuff
    return &privmsgnotice_opmod         if $opts{op_moderated};
    return &privmsgnotice_smask         if defined $opts{serv_mask};
    return &privmsgnotice_atserver      if defined $opts{atserv_serv};
    return &privmsgnotice_status        if defined $opts{min_level};

    $target or return;
    my $id  = $source->id;
    my $tid = $target->id;
    ":$id $cmd $tid :$message"
}

# Complex PRIVMSG
#
#   a message to all users on server names matching a mask ('$$' followed by mask)
#   propagation: broadcast
#   Only allowed to IRC operators.
#
sub privmsgnotice_smask {
    my ($to_server, $cmd, $source, undef, $message, %opts) = @_;
    my $server_mask = $opts{serv_mask};
    my $id = $source->id;
    ":$id $cmd \$\$$server_mask :$message"
}

# - Complex PRIVMSG
#   '=' followed by a channel name, to send to chanops only, for cmode +z.
#   capab:          CHW and EOPMOD
#   propagation:    all servers with -D chanops
#
sub privmsgnotice_opmod {
    my ($to_server, $cmd, $source, $target, $message, %opts) = @_;
    return if !$target->isa('channel');

    return sprintf ':%s %s =%s :%s',
    $source->id,
    $cmd,
    $target->name,
    $message;
}

# - Complex PRIVMSG
#   a user@server message, to send to users on a specific server. The exact
#   meaning of the part before the '@' is not prescribed, except that "opers"
#   allows IRC operators to send to all IRC operators on the server in an
#   unspecified format.
#   propagation:    one-to-one
#
sub privmsgnotice_atserver {
    my ($to_server, $cmd, $source, undef, $message, %opts) = @_;
    return if !length $opts{atserv_nick} || !ref $opts{atserv_serv};
    my $id = $source->id;
    ":$id $cmd $opts{atserv_nick}\@$opts{atserv_serv}{sid} :$message"
}

# - Complex PRIVMSG
#   a status character ('@'/'+') followed by a channel name, to send to users
#   with that status or higher only.
#   capab:          CHW
#   propagation:    all servers with -D users with appropriate status
#
sub privmsgnotice_status {
    my ($to_server, $cmd, $source, $channel, $message, %opts) = @_;
    $channel or return;

    # convert the level to a mode letter
    my $letter = $ircd::channel_mode_prefixes{ $opts{min_level} } or return;
    $letter = $letter->[0];

    my $id = $source->id;
    my $ch_name = $channel->name;
    ":$id $cmd \@$letter$ch_name :$message"
}

# channel join
sub _join {
    my ($to_server, $user, $channel, $time) = @_;
    my @channels = ref $channel eq 'ARRAY' ? @$channel : $channel;
    map ":$$user{uid} JOIN $$_{name} $time", @channels;
}


# part all channels
sub partall {
    my ($to_server, $user) = @_;
    ":$$user{uid} PARTALL"
}

# add oper flags
sub oper {
    my ($to_server, $user, @flags) = @_;
    ":$$user{uid} OPER @flags"
}


# set away
sub away {
    my ($to_server, $user) = @_;
    ":$$user{uid} AWAY :$$user{away}"
}


# return from away
sub return_away {
    my ($to_server, $user) = @_;
    ":$$user{uid} RETURN"
}

# leave a channel
sub part {
    my ($to_server, $user, $channel, $reason) = @_;
    $reason //= q();
    my @channels = ref $channel eq 'ARRAY' ? @$channel : $channel;
    map ":$$user{uid} PART $$_{name} $$_{time} :$reason", @channels;
}


sub topic {
    my ($to_server, $source, $channel, $time, $topic) = @_;
    my $id = $source->id;
    ":$id TOPIC $$channel{name} $$channel{time} $time :$topic"
}

sub _connect {
    my ($to_server, $source, $connect_mask, $t_server) = @_;
    my $id = $source->id;
    ":$id CONNECT $connect_mask \$$$t_server{sid}"
}

# $wuser   = whoiser
# $quser   = target user
# $wserver = target server
sub whois {
    my ($to_server, $wuser, $quser, $wserver) = @_;
    "\@for=$$wserver{sid} :$$wuser{uid} WHOIS $$quser{uid}"
}

# channel mode change

sub cmode {
    my ($to_server, $source, $channel, $time, $perspective, $modestr) = @_;
    return unless length $modestr;
    my $id  = $source->id;
    my $pid = $perspective->id;
    ":$id CMODE $$channel{name} $time $pid :$modestr"
}

# kill

sub skill {
    my ($to_server, $source, $tuser, $reason) = @_;
    my ($id, $tid) = ($source->id, $tuser->id);
    ":$id KILL $tid :$reason"
}

# channel burst
sub sjoin {
    my ($server, $channel, $serv, @members) = @_;
    $serv ||= $me;

    # make +modes params string without status modes.
    # modes are from the perspective of the source server.
    my (undef, $modestr) = $channel->mode_string_all($serv, 1);

    # fetch the prefixes for each user.
    my (%prefixes, @userstrs);
    foreach my $name (keys %{ $channel->{modes} }) {
        next if $serv->cmode_type($name) != 4;
        my $letter = $serv->cmode_letter($name);
        ($prefixes{$_} //= '') .= $letter foreach $channel->list_elements($name);
    }

    # create an array of uid!status
    foreach my $user (@members) {

        # this is the server that told us about the user. it already knows.
        next if $user->{location} == $server;

        my $str = $user->{uid};
        $str .= '!'.$prefixes{$user} if exists $prefixes{$user};
        push @userstrs, $str;
    }

    my $userstr = join ' ', @userstrs;
    ":$$serv{sid} SJOIN $$channel{name} $$channel{time} $modestr :$userstr"
}

# add cmodes
sub acm {
    my ($to_server, $serv, $added, $removed) = @_;
    my @mode_strs;

    # if the lists are omitted, this is an initial ACM during burst.
    # send out all registered cmodes.
    if (!$added) {
        my %cmodes = %{ $serv->{cmodes} };

        # remove ones with no mode blocks
        foreach (keys %cmodes) {
            next if $pool->{channel_modes}{$_};
            delete $cmodes{$_};
        }

        $added = [ map [ $_, @{ $cmodes{$_} }{qw(letter type)} ], keys %cmodes ];
        $removed = [];
    }

    # additions
    foreach (@$added) {
        my ($name, $letter, $type) = @$_;
        push @mode_strs, "$name:$letter:$type";
    }

    # removals
    foreach my $rem (@$removed) {
        push @mode_strs, "-$rem";
    }

    # if there are none, just don't.
    scalar @mode_strs or return;

    ":$$serv{sid} ACM ".join(' ', @mode_strs)
}

# add umodes
sub aum {
    my ($to_server, $serv, $added, $removed) = @_;
    my @mode_strs;

    # if the lists are omitted, this is an initial AUM during burst.
    # send out all registered umodes.
    if (!$added) {
        my %umodes = %{ $serv->{umodes} };

        # remove ones with no mode blocks
        foreach (keys %umodes) {
            next if $pool->{user_modes}{$_};
            delete $umodes{$_};
        }

        $added = [ map [ $_, $umodes{$_}{letter} ], keys %umodes ];
        $removed = [];
    }

    # additions
    foreach (@$added) {
        my ($name, $letter) = @$_;
        push @mode_strs, "$name:$letter";
    }

    # removals
    foreach my $rem (@$removed) {
        push @mode_strs, "-$rem";
    }

    # if there are none, just don't.
    scalar @mode_strs or return;

    ":$$serv{sid} AUM ".join(' ', @mode_strs)
}

# KICK command.
sub kick {
    my ($to_server, $source, $channel, $target, $reason) = @_;
    my $sourceid = $source->can('id') ? $source->id : '';
    my $targetid = $target->can('id') ? $target->id : '';
    return ":$sourceid KICK $$channel{name} $targetid :$reason";
}

# remote numerics
sub num {
    my ($to_server, $server, $t_user, $num, $message) = @_;
    ":$$server{sid} NUM $$t_user{uid} $num :$message"
}

sub links {
    my ($to_server, $user, $t_server, $query_mask) = @_;
    "\@for=$$t_server{sid} :$$user{uid} LINKS * $query_mask"
}

sub users {
    my ($to_server, $user, $t_server) = @_;
    "\@for=$$t_server{sid} :$$user{uid} USERS"
}

sub lusers {
    my ($to_server, $user, $t_server) = @_;
    "\@for=$$t_server{sid} :$$user{uid} LUSERS"
}

sub burst {
    my ($to_server, $serv, $time) = @_;
    ":$$serv{sid} BURST $time"
}

sub endburst {
    my ($to_server, $serv, $time) = @_;
    ":$$serv{sid} ENDBURST $time"
}

sub admin {
    my ($to_server, $user, $t_server) = @_;
    ":$$user{uid} ADMIN \$$$t_server{sid}"
}

sub motd {
    my ($to_server, $user, $t_server) = @_;
    ":$$user{uid} MOTD \$$$t_server{sid}"
}

sub _time {
    my ($to_server, $user, $t_server) = @_;
    ":$$user{uid} TIME \$$$t_server{sid}"
}

sub snotice {
    my ($to_server, $server, $flag, $message, $from_user) = @_;
    my $text = ":$$server{sid} SNOTICE $flag :$message";
    if ($from_user) {
        $text = "\@from_user=$$from_user{uid} $text";
    }
    return $text;
}

sub version {
    my ($to_server, $user, $t_server) = @_;
    ":$$user{uid} VERSION \$$$t_server{sid}"
}

sub su_login {
    my ($to_server, $source_serv, $user, $actname) = @_;
    return login($to_server, $user, $actname);
}

# :uid LOGIN accountname,others,...
# the comma-separated list is passed as a list here.
sub login {
    my ($to_server, $user, @items) = @_;
    my $items = join ',', @items;
    ":$$user{uid} LOGIN $items"
}

sub invite {
    my ($to_server, $user, $t_user, $ch_name) = @_;
    $ch_name = $ch_name->{name} if ref $ch_name;
    ":$$user{uid} INVITE $$t_user{uid} $ch_name"
}

sub reload {
    my ($to_server, $user, $flags, @servers) = @_;
    my $sids = join '', map '$'.$_->id, @servers;
    $flags = length $flags ? " $flags" : '';
    ":$$user{uid} RELOAD $sids$flags"
}

sub checkout {
    my ($to_server, $user, @servers) = @_;
    my $sids = join '', map '$'.$_->id, @servers;
    ":$$user{uid} CHECKOUT $sids"
}

sub update {
    my ($to_server, $user, @servers) = @_;
    my $sids = join '', map '$'.$_->id, @servers;
    ":$$user{uid} UPDATE $sids"
}

sub rehash {
    # $serv_mask and $type are not used in JELP
    my ($to_server, $user, $serv_mask, $type, @servers) = @_;
    my $sids = join '', map '$'.$_->id, @servers;
    ":$$user{uid} REHASH $sids"
}

sub save {
    my ($to_server, $source_serv, $user, $nick_time) = @_;
    ":$$source_serv{sid} SAVE $$user{uid} $nick_time"
}

sub chghost {
    my ($to_server, $source, $user, $new_host) = @_;
    return userinfo($to_server, $user, host => $new_host);
}

sub realhost {
    my ($to_server, $user, $host) = @_;
    return userinfo($to_server, $user, real_host => $host);
}

sub userinfo {
    my ($to_server, $user, %fields) = @_;
    return message->new(
        source  => $user->id,
        command => 'USERINFO',
        tags    => \%fields
    )->data;
}

sub fnick {
    my ($to_server, $server, $user, $new_nick, $new_nick_ts, $old_nick_ts) = @_;
    ":$$server{sid} FNICK $$user{uid} $new_nick $new_nick_ts $old_nick_ts"
}

$mod
