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
# @depends.modules: ['TS6::Utils']
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::TS6::Outgoing;

use warnings;
use strict;
use 5.010;

use M::TS6::Utils qw(ts6_id ts6_prefix);

our ($api, $mod, $pool);

our %ts6_outgoing = (
   # quit           => \&quit,
   # sid            => \&sid,
   # addumode       => \&addumode,
   # addcmode       => \&addcmode,
   # topicburst     => \&topicburst,
     uid            => \&euid,
     nickchange     => \&nick,
   # umode          => \&umode,
   # privmsgnotice  => \&privmsgnotice,
     sjoin          => \&_join,
   # oper           => \&oper,
   # away           => \&away,
   # return_away    => \&return_away,
   # part           => \&part,
   # topic          => \&topic,
     cmode          => \&tmode,
     cum            => \&sjoin,
   # acm            => \&acm,
   # aum            => \&aum,
   # kill           => \&skill,
   # connect        => \&sconnect,
   # kick           => \&kick,
   # num            => \&num,
   # links          => \&links
);

sub init {
    $pool->on('server.send_burst' => \&send_burst, name => 'core', with_eo => 1);
}

sub send_burst {
    my ($server, $event) = @_;
    $server->{link_type} eq 'ts6' or return;
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
    my ($server, $user) = @_; # no $server
    sprintf ":%s EUID %s %d %d %s %s %s %s %s %s %s",
    ts6_id($user->{server}),                        # source SID
    $user->{nick},                                  # nickname
    $me->hops_to($user->{server}),                  # number of hops
    $user->{nick_time} // $user->{time},            # last nick-change time
    $user->mode_string($server),                    # +modes string
    $user->{ident},                                 # username (w/ ~ if needed)
    $user->{cloak},                                 # visible hostname
    $user->{ip},                                    # IP address
    ts6_id($user),                                  # UID
    $user->{host},                                  # real hostname
    $user->account ? $user->account->name : '*'     # account name
}

# SJOIN
#
# source:       server
# propagation:  broadcast
# parameters:   channelTS, channel, simple modes, opt. mode parameters..., nicklist
#
# ts6-protocol.txt:821
#
sub sjoin {
    my ($server, $channel) = @_; # backwards
    
    my @members;
    foreach my $user ($channel->users) {
        my $pfx = ts6_prefix($channel->user_get_highest_level($user));
        my $uid = ts6_id($user);
        push @members, "$pfx$uid";
    }
    
    # TODO: probably should split this into several SJOINs?
    sprintf ":%s SJOIN %d %s %s :%s",
    ts6_id($me),                                    # SID of this server
    $channel->{time},                               # channel time
    $channel->{name},                               # channel name
    $channel->mode_string_hidden($server),          # includes +ntk, excludes +ovbI, etc.
    "@members"
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
    my ($server, $user, $channel, $time) = @_; # no $server, why $time?
    
    # there's only one user, so this channel was just created.
    # consider: if a permanent channel mode is added, idk how TS6 bursts that.
    # this might need to be rethought.
    return sjoin($server, $channel) if scalar $channel->users == 1;
    
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
    my $user = shift;
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
    my ($server, $source, $channel, $time, $perspective, $modestr) = @_; # no $server, why $time?
    sprintf ":%s TMODE %d %s %s",
    ts6_id($source),
    $time,
    $channel->{name},
    $perspective->convert_cmode_string($server)
}


$mod

