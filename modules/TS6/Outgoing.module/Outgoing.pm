# Copyright (c) 2014, mitchellcooper
#
# Created on Mitchells-Mac-mini.local
# Fri Aug  8 22:47:11 EDT 2014
# Outgoing.pm
#
# @name:            'TS6::Outgoing'
# @package:         'M::TS6::Outgoing'
# @description:     'basic set of TS6 outgoing commands'
#
# @depends.modules: ['TS6::Utils', 'TS6::Base']
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::TS6::Outgoing;

use warnings;
use strict;
use 5.010;

use M::TS6::Utils qw(ts6_id ts6_prefixes);

our ($api, $mod, $pool, $me);

our %ts6_outgoing_commands = (
     quit           => \&quit,
     new_server     => \&sid,
     new_user       => \&euid,
     nickchange     => \&nick,
   # umode          => \&umode,
     privmsgnotice  => \&privmsgnotice,
     privmsgnotice_server_mask => \&privmsgnotice_smask,
     join           => \&_join,
   # oper           => \&oper,
     away           => \&away,
     return_away    => \&return_away,
     part           => \&part,
     topic          => \&topic,
     cmode          => \&tmode,
     channel_burst  => [ \&sjoin_burst, \&bmask, \&tb ],
     join_with_modes => \&sjoin,
   # acm            => \&acm,
   # aum            => \&aum,
     kill           => \&skill,
   # connect        => \&sconnect,
     kick           => \&kick,
     login          => \&login,
     pong           => \&pong,
     topicburst     => \&tb,
     wallops        => \&wallops,
     chghost        => \&chghost,
     save_user      => \&save,
   # num            => \&num,
   # links          => \&links,
   # whois          => \&whois
);

sub init {
    $pool->on('server.send_ts6_burst' => \&send_burst,
        name    => 'core', # conflicts with JELP, but it'll never be fired with that
        with_eo => 1
    );
    $pool->on('server.send_ts6_burst' => \&send_endburst,
        name     => 'endburst',
        with_eo  => 1,
        priority => -1000
    );
}

sub send_burst {
    my ($server, $event) = @_;

    # servers.
    my ($do, %done);
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

    # users.
    foreach my $user ($pool->global_users) {

        # ignore users the server already knows!
        next if $user->{server} == $server || $user->{source} == $server->{sid};
        $server->fire_command(new_user => $user);
        $server->fire_command(login => $user, $user->{account}{name}) if $user->{account};
        # TODO: oper flags
        $server->fire_command(away => $user) if length $user->{away};
    }

    # channels.
    foreach my $channel ($pool->channels) {
        $server->fire_command(channel_burst => $channel, $me);
    }

}

sub send_endburst {
    my ($server, $event) = @_;
    $server->send($server->has_cap('eb') ? '' : sprintf ':%s PONG %s %s', ts6_id($me), $me->{name}, $server->{name});
}

# SID
#
# source:       server
# propagation:  broadcast
# parameters:   server name, hopcount, sid, server description
#
# ts6-protocol.txt:805
#
sub sid {
    my ($server, $serv) = @_;
    return if $server == $serv;

    # hidden?
    my $desc = $serv->{desc};
    $desc = "(H) $desc" if $serv->{hidden};

    sprintf ':%s SID %s %d %s :%s',
    ts6_id($serv->{parent}),
    $serv->{name},
    $me->hops_to($serv),
    ts6_id($serv),
    $desc
}

# EUID
#
# charybdis TS6
#
# capab         EUID
# source:       server
# parameters:   nickname, hopcount, nickTS, umodes, username, visible hostname,
#               IP address, UID, real hostname, account name, gecos
# propagation:  broadcast
#
# ts6-protocol.txt:315
#
sub euid {
    my ($server, $user) = @_;

    if (!$server->has_cap('euid')) {
        # TODO: use UID
    }

    sprintf ":%s EUID %s %d %d %s %s %s %s %s %s %s :%s",
    ts6_id($user->{server}),                        # source SID
    $user->{nick},                                  # nickname
    $me->hops_to($user->{server}),                  # number of hops
    $user->{nick_time} // $user->{time},            # last nick-change time
    $user->mode_string($server),                    # +modes string
    $user->{ident},                                 # username (w/ ~ if needed)
    $user->{cloak},                                 # visible hostname
    $user->{ip},                                    # IP address
    ts6_id($user),                                  # UID
    $user->{cloak} eq $user->{host} ?               # real hostname
        '*' : $user->{host},                        #   (* if equal to visible)
    $user->{account} ?                              # account name
        $user->{account}{name} : '*',               #   (* if not logged in)
    $user->{real}
}

# SJOIN
#
# source:       server
# propagation:  broadcast
# parameters:   channelTS, channel, simple modes, opt. mode parameters..., nicklist
#
# ts6-protocol.txt:821
#
# join_with_modes:
#
# $server    = server object we're sending to
# $channel   = channel object
# $serv      = server source of the message
# $mode_str  = mode string being sent
# $mode_serv = server object for mode perspective
# @members   = channel members (user objects)
#
sub sjoin {
    my ($server, $channel, $serv, $mode_str, $mode_serv, @members) = @_;

    # if the mode perspective is not the server we're sending to, convert.
    $mode_str = $mode_serv->convert_cmode_string($server, $mode_str)
      if $mode_serv != $server;

    # create @UID +UID etc. strings.
    my @member_str;
    foreach my $user (@members) {
        my $pfx = ts6_prefixes($server, $channel->user_get_levels($user));
        my $uid = ts6_id($user);
        push @member_str, "$pfx$uid";
    }

    # TODO: probably should split this into several SJOINs?
    sprintf ":%s SJOIN %d %s %s :%s",
    ts6_id($serv),                      # SID of the source server
    $channel->{time},                   # channel time
    $channel->{name},                   # channel name
    $mode_str,                          # includes +ntk, excludes +ovbI, etc.
    "@member_str"
}

# for bursting, send SJOIN with all simple modes and all users if none specified.
sub sjoin_burst {
    my ($server, $channel, $serv, @members) = @_;
    my $mode_str = $channel->mode_string_hidden($server);
    @members = $channel->users if !@members;
    return sjoin($server, $channel, $serv, $mode_str, $server, @members);
}

# JOIN
#
# 1.
# source:       user
# parameters:   '0' (one ASCII zero)
# propagation:  broadcast
#
# 2.
# source:       user
# parameters:   channelTS, channel, '+' (a plus sign)
# propagation:  broadcast
#
# ts6-protocol.txt:397
#
sub _join {
    my ($server, $user, $channel, $time) = @_; # why $time?
    my @channels = ref $channel eq 'ARRAY' ? @$channel : $channel;
    my @lines;
    foreach my $channel (@channels) {

        # there's only one user, so this channel was just created.
        # we will just pretend we're bursting, sending the single user with modes
        # from THIS local server ($me).
        if (scalar $channel->users == 1) {
            push @lines, sjoin_burst($server, $channel, $me);
            next;
        }

        push @lines, sprintf ':%s JOIN %d %s +',
            ts6_id($user),
            $channel->{time},
            $channel->{name};
    }
    return @lines;
}

# NICK
#
# 1.
# source:       user
# parameters:   new nickname, new nickTS
# propagation:  broadcast
#
# 2. (not used in TS 6)
# source:       server
# parameters:   nickname, hopcount, nickTS, umodes, username, hostname, server, gecos
#
# ts6-protocol.txt:562
#
sub nick {
    my ($server, $user) = @_;
    sprintf ':%s NICK %s :%d',
    ts6_id($user),
    $user->{nick},
    $user->{nick_time} // $user->{time}
}

# TMODE
#
# source:       any
# parameters:   channelTS, channel, cmode changes, opt. cmode parameters...
#
# ts6-protocol.txt:937
#
sub tmode {
    my ($server, $source, $channel, $time, $perspective, $mode_str) = @_; # why $time?
    sprintf ":%s TMODE %d %s %s",
    ts6_id($source),
    $time,
    $channel->{name},
    $perspective->convert_cmode_string($server, $mode_str, 1)
}

# BMASK
#
# source:       server
# propagation:  broadcast
# parameters:   channelTS, channel, type, space separated masks
#
# ts6-protocol.txt:194
#
sub bmask {
    my ($server, $channel) = @_;
    my @lines;
    foreach my $mode_name (keys %{ $server->{cmodes} }) {
        next unless $server->cmode_type($mode_name) == 3;
        my @items  = $channel->list_elements($mode_name);
        my $letter = $server->cmode_letter($mode_name);
        push @lines, sprintf(
            ':%s BMASK %d %s %s %s',
            ts6_id($me),
            $channel->{time},
            $channel->{name},
            $letter,
            $_
        ) foreach @items;
    }
    return @lines;
}

# TB
#
# capab:        TB
# source:       server
# propagation:  broadcast
# parameters:   channel, topicTS, opt. topic setter, topic
#
# ts6-protocol.txt:916
#
sub tb {
    my ($to_server, $channel) = @_;
    return unless $channel->topic;

    # if TB is not supported, use TOPIC.
    if (!$to_server->has_cap('tb')) {
        return topic(
            $to_server, $me, $channel,
            $channel->{topic}{time}, $channel->{topic}{topic}
        );
    }

    sprintf
    ':%s TB %s %d %s :%s',
    ts6_id($me),
    $channel->{name},
    $channel->{topic}{time},
    $channel->{topic}{setby},
    $channel->{topic}{topic}
}

# PRIVMSG
#
# source:       user
# parameters:   msgtarget, message
#
#
# NOTICE
#
# source:       any
# parameters:   msgtarget, message
#
#
sub privmsgnotice {
    my ($to_server, $cmd, $source, $target, $message) = @_;
    my $id  = ts6_id($source);
    my $tid = ts6_id($target);
    ":$id $cmd $tid :$message"
}

# Complex PRIVMSG
#
#   a message to all users on server names matching a mask ('$$' followed by mask)
#   propagation: broadcast
#   Only allowed to IRC operators.
#
# privmsgnotice_server_mask =>
#     $command, $source,
#     $mask, $message
#
sub privmsgnotice_smask {
    my ($to_server, $cmd, $source, $server_mask, $message) = @_;
    my $id = ts6_id($source);
    ":$id $cmd \$\$$server_mask :$message"
}

# PART
#
# source:       user
# parameters:   comma separated channel list, message
#
# ts6-protocol.txt:617
#
sub part {
    my ($to_server, $user, $channel, $reason) = @_;
    my $id = ts6_id($user);
    $reason //= q();
    my @channels = ref $channel eq 'ARRAY' ? @$channel : $channel;
    map ":$id PART $$_{name} :$reason", @channels;
}

# QUIT
#
# source:       user
# parameters:   comment
#
# this can take a server object, user object, or connection object.
#
# ts6-protocol.txt:694
#
# SQUIT
# parameters:   target server, comment
#
# ts6-protocol.txt:858
#
sub quit {
    my ($to_server, $object, $reason) = @_;
    $object = $object->type if $object->isa('connection');

    # if it's a server, SQUIT.
    if ($object->isa('server')) {
        return sprintf ":%s SQUIT %s :%s",
            ts6_id($object->{parent}),
            ts6_id($object),
            $reason;
    }

    my $id  = ts6_id($object);
    ":$id QUIT :$reason"
}

# KICK
#
# source:       any
# parameters:   channel, target user, opt. reason
# propagation:  broadcast
#
# ts6-protocol.txt:433
#
sub kick {
    my ($to_server, $source, $channel, $target, $reason) = @_;
    my $sourceid = ts6_id($source);
    my $targetid = ts6_id($target);
    my $reason = length $reason ? " :$reason" : '';
    return ":$sourceid KICK $$channel{name} $targetid$reason";
}

# TOPIC
#
# source:       user
# propagation:  broadcast
# parameters:   channel, topic
#
# ts6-protocol.txt:957
#
sub topic {
    my ($to_server, $source, $channel, $time, $topic) = @_;
    my $id = ts6_id($source);
    ":$id TOPIC $$channel{name} :$topic"
}

# KILL
#
# source:       any
# parameters:   target user, path
# propagation:  broadcast
#
# ts6-protocol.txt:444
#
sub skill {
    my ($to_server, $source, $tuser, $reason) = @_;
    my ($id, $tid) = (ts6_id($source), ts6_id($tuser));
    my $path = $source->isa('user') ?
        join('!', $source->{server}->name, @$source{qw(host ident nick)}) :
        $source->name;
    ":$id KILL $tid :$path ($reason)"
}

# LOGIN
# encap only
#
# source:       user
# parameters:   account name
#
# ts6-protocol.txt:505
#
sub login {
    my ($to_server, $user, $acctname) = @_;
    my $id = ts6_id($user);
    ":$id ENCAP * LOGIN $acctname"
}

# PONG
#
# source:       server
# parameters:   origin, destination
#
# ts6-protocol.txt:714
#
sub pong {
    my ($to_server, $source_serv, $dest) = @_;
    my $id = ts6_id($source_serv);
    $dest ||= $to_server->id;
    ":$id PONG $$source_serv{name} $dest"
}

# AWAY
#
# source:       user
# propagation:  broadcast
# parameters:   opt. away reason
#
# ts6-protocol.txt:215
#
sub away {
    my ($to_server, $user) = @_;
    my $id = ts6_id($user);
    ":$id AWAY :$$user{away}"
}

# AWAY (Return)
#
# source:       user
# propagation:  broadcast
# parameters:   opt. away reason
#
# ts6-protocol.txt:215
#
sub return_away {
    my ($to_server, $user) = @_;
    my $id = ts6_id($user);
    ":$id AWAY"
}

# WALLOPS
#
# 1.
# source:       user
# parameters:   message
# propagation:  broadcast
#
# 2.
# source:       server
# parameters:   message
# propagation:  broadcast
#
# ts6-protocol.txt:1140
#
sub wallops {
    my ($to_server, $source, $message) = @_;
    my $id = ts6_id($source);
    ":$id WALLOPS :$message"
}
# CHGHOST
#
# charybdis TS6
# source:       any
# propagation:  broadcast
# parameters:   client, new hostname
#
sub chghost {
    my ($to_server, $source, $user, $new_host) = @_;
    my ($source_id, $user_id) = (ts6_id($source), ts6_id($user));

    # no EUID support, so use the old ENCAP CHGHOST.
    if (!$to_server->has_cap('euid')) {
        # :<SID> ENCAP * CHGHOST <UID> <VHOST>
        return ":$source_id ENCAP * CHGHOST $user_id $new_host"
    }

    ":$source_id CHGHOST $user_id $new_host"
}

# SAVE
#
# capab:        SAVE
# source:       server
# propagation:  broadcast
# parameters:   target uid, TS
#
sub save {
    my ($to_server, $source_serv, $user) = @_;
    my $sid = ts6_id($source_serv);
    my $uid = ts6_id($user);

    # if the server does not support SAVE, send out a NICK message
    if (!$to_server->has_cap('save')) {
        my $fake_user = user->new(%$user,
            nick      => $uid,
            nick_time => 0
        );
        return nick($to_server, $fake_user);
    }

    ":$sid SAVE $uid $$user{nick_time}"
}

$mod
