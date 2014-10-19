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
   # quit           => \&quit,
     new_server     => \&sid,
     new_user       => \&euid,
     nickchange     => \&nick,
   # umode          => \&umode,
     privmsgnotice  => \&privmsgnotice,
     join           => \&_join,
   # oper           => \&oper,
   # away           => \&away,
   # return_away    => \&return_away,
   # part           => \&part,
   # topic          => \&topic,
     cmode          => \&tmode,
     channel_burst  => [ \&sjoin_burst, \&bmask, \&tb ],
     join_with_modes => \&sjoin,
   # acm            => \&acm,
   # aum            => \&aum,
   # kill           => \&skill,
   # connect        => \&sconnect,
   # kick           => \&kick,
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
        
        # TODO: oper flags
        # TODO: away reason
    }
    
    # channels.
    foreach my $channel ($pool->channels) {
        $server->fire_command(channel_burst => $channel, $me);
    }
    
}

sub send_endburst {
    my ($server, $event) = @_;
    $server->send($server->has_cap('eb') ? '' : sprintf 'PING :%s', ts6_id($me));
}

# SID
#
# source:       server
# propagation:  broadcast
# parameters:   server name, hopcount, sid, server description
#
# ts6-protocol.txt:805
sub sid {
    my ($server, $serv) = @_;
    return if $server == $serv;
    sprintf ':%s SID %s %d %s :%s',
    ts6_id($serv->{parent}),
    $serv->{name},
    $me->hops_to($serv),
    ts6_id($serv),
    $serv->{desc}
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
    $user->account ? $user->account->name : '*',    # account name
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
    
    # there's only one user, so this channel was just created.
    # we will just pretend we're bursting, sending the single user with modes
    # from THIS local server ($me).
    return sjoin_burst($server, $channel, $me) if scalar $channel->users == 1;
    
    sprintf ':%s JOIN %d %s +',
    ts6_id($user),
    $channel->{time},
    $channel->{name}
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
    my ($server, $channel) = @_;
    $server->has_cap('tb') or return;
    return unless $channel->topic;
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

$mod

