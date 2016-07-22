# Copyright (c) 2016, Mitchell Cooper
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
     umode          => \&umode,
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
   # acm            => \&acm,
   # aum            => \&aum,
     kill           => \&skill,
   # connect        => \&sconnect,
     kick           => \&kick,
     login          => \&login,
     ping           => \&ping,
     pong           => \&pong,
     topicburst     => \&tb,
     wallops        => \&wallops,
     chghost        => \&chghost,
     save_user      => \&save,
     update_user    => \&userinfo,
     num            => \&num,
     links          => \&links,
     whois          => \&whois,
     part_all       => \&join_zero,
     admin          => \&admin,
     time           => \&_time,
     info           => \&info,
     motd           => \&motd,
     version        => \&version,
     lusers         => \&lusers,
     invite         => \&invite,
     su_login       => \&su_login,
     su_logout      => \&su_logout,
     ircd_rehash     => \&rehash
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

    # SVINFO is always at the start of the burst I think.
    $server->sendfrom($me->id, "SVINFO 6 6 0 ".time());

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
        $server->fire_command(channel_burst => $channel, $me, $channel->users);
    }

}

sub send_endburst {
    my ($server, $event) = @_;
    $server->send($server->has_cap('eb') ? '' : sprintf ':%s PONG %s %s', ts6_id($me), $me->{name}, $server->{name});
}

# ts6 nick safety
sub safe_nick {
    my $user = shift;

    # if the nickname is the juno UID, use the ts6 uid
    if ($user->{nick} eq $user->{uid}) {
        return ts6_id($user);
    }

    return $user->{nick};
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
    safe_nick($user),                               # nickname
    $me->hops_to($user->{server}),                  # number of hops
    $user->{nick_time},                             # last nick-change time
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
    $mode_str = $mode_serv->convert_cmode_string(
        $server,    # the destination server, the one we're converting to
        $mode_str,  # the raw mode string in the perpsective of $mode_serv
        1,          # indicates that this is over a server protocol
        1           # skip status modes (TS 6 sends them as prefixes)
    ) if $mode_serv != $server;

    # create @UID +UID etc. strings.
    my @member_str = '';
    my $str_i = 0;
    my $uids_this_line = 0;
    foreach my $user (@members) {
        my $pfx = ts6_prefixes($server, $channel->user_get_levels($user));
        my $uid = ts6_id($user);

        # this SJOIN is getting too long.
        if ((length($member_str[$str_i]) || 0) > 500 || $uids_this_line > 12) {
            $str_i++;
            $member_str[$str_i] = '';
            $uids_this_line = 0;
        }

        $member_str[$str_i] .= "$pfx$uid ";
        $uids_this_line++;
    }

    return map {
        chop; # remove the last space
        sprintf(":%s SJOIN %d %s %s :%s",
            ts6_id($serv),          # SID of the source server
            $channel->{time},       # channel time
            $channel->{name},       # channel name
            $mode_str,              # includes +ntk, excludes +ovbI, etc.
            $_                      # the member string
        )
    } @member_str;
}

# for bursting, send SJOIN with all simple modes.
sub sjoin_burst {
    my ($server, $channel, $serv, @members) = @_;
    my $mode_str = $channel->mode_string_hidden($server);
    return sjoin(
        $server,        # destination server
        $channel,       # channel
        $serv,          # source server
        $mode_str,      # mode string
        $serv,          # mode perspective (in TS 6, same as source)
        @members        # members
    );
}

# JOIN
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

# JOIN
#
# 1.
# source:       user
# parameters:   '0' (one ASCII zero)
# propagation:  broadcast
#
sub join_zero {
    my ($to_server, $user) = @_;
    my $id = ts6_id($user);
    ":$id JOIN 0"
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
    safe_nick($user),
    $user->{nick_time}
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

    # convert to TS6
    my $str = $perspective->convert_cmode_string($server, $mode_str, 1);
    return if !length $str;

    sprintf ":%s TMODE %d %s %s",
    ts6_id($source),
    $time,
    $channel->{name},
    $str
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

        # ignore status modes in bmask
        next unless $server->cmode_type($mode_name) == 3;

        # find the items and the mode letter
        my @items  = $channel->list_elements($mode_name);
        my $letter = $server->cmode_letter($mode_name);

        # construct multiple messages if necessary
        my $base = my $str = sprintf(':%s BMASK %d %s %s ',
            ts6_id($me),
            $channel->{time},
            $channel->{name},
            $letter
        );

        # with each item
        while (length(my $item = shift @items)) {

            # this line is full; start a new one
            if (length $str >= 500 && @items) {
                chop $str;
                push @lines, $str;
                $str = $base;
            }

            # add the item
            $str .= "$item ";

        }

        # push the final line
        if (length $str && $str ne $base) {
            chop $str;
            push @lines, $str;
        }

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
    $reason = length $reason ? " :$reason" : '';
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
        join('!',
            $source->{server}->name,
            @$source{ qw(host ident) },
            safe_nick($source)
        ) : $source->name;
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

# SU
#
# encap only
# encap target: *
# source:       services server
# parameters:   target user, new login name (optional)
#
sub su_login {
    my ($to_server, $source_serv, $user, $acctname) = @_;
    my $sid = ts6_id($source_serv);
    my $uid = ts6_id($user);
    ":$sid ENCAP * SU $uid $acctname"
}

# SU
#
# encap only
# encap target: *
# source:       services server
# parameters:   target user, new login name (optional)
#
sub su_logout {
    my ($to_server, $source_serv, $user) = @_;
    my $sid = ts6_id($source_serv);
    my $uid = ts6_id($user);
    ":$sid ENCAP * SU $uid"
}

# PING
#
# source:       any
# parameters:   origin, opt. destination server
#
# ts6-protocol.txt:700
#
sub ping {
    my ($to_server, $source_serv, $dest_serv) = @_;
    my $sid1 = ts6_id($source_serv);

    # destination can be left out
    if (!$dest_serv) {
        return ":$sid1 PING $$source_serv{name}";
    }

    my $sid2 = ts6_id($dest_serv);
    ":$sid1 PING $$source_serv{name} $sid2"
}

# PONG
#
# source:       server
# parameters:   origin, destination
#
# ts6-protocol.txt:714
#
sub pong {
    my ($to_server, $source_serv, $dest_serv) = @_;
    my $sid1 = ts6_id($source_serv);
    my $sid2 = ts6_id($dest_serv);
    ":$sid1 PONG $$source_serv{name} $sid2"
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
    my ($to_server, $source, $message, $oper_only) = @_;
    my $id = ts6_id($source);

    # if it's oper only and the source is not a server, use OPERWALL.
    if ($oper_only && $source->isa('user')) {
        return ":$id OPERWALL :$message";
    }

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
    my ($to_server, $source_serv, $user, $nick_time) = @_;
    my $sid = ts6_id($source_serv);
    my $uid = ts6_id($user);

    # we use a different $nick_time in case using ->forward().
    # we want the nickTS to remain correct when propagated, not 100.

    # if the server does not support SAVE, send out a NICK message
    if (!$to_server->has_cap('save')) {
        my $fake_user = user->new(%$user,
            nick      => $uid,
            nick_time => 100
        );
        return nick($to_server, $fake_user);
    }

    ":$sid SAVE $uid $nick_time"
}

# WHOIS
# source: user
# parameters: hunted, target nick
#
sub whois {
    my ($to_server, $whoiser_user, $queried_user, $target_server) = @_;
    my $uid1 = ts6_id($whoiser_user);
    my $tsid = ts6_id($target_server);
    my $nick = safe_nick($queried_user);
    ":$uid1 WHOIS $tsid $nick"
}

# remote numerics
sub num {
    my ($to_server, $server, $t_user, $num, $message) = @_;
    my ($sid, $uid) = (ts6_id($server), ts6_id($t_user));
    ":$sid $num $uid $message"
}

# MODE
#
# 1.
# source: user
# parameters: client, umode changes
# propagation: broadcast
#
# 2.
# source: any
# parameters: channel, cmode changes, opt. cmode parameters...
#
sub umode {
    my ($to_server, $user, $mode_str) = @_;
    my $str = $me->convert_umode_string($to_server, $mode_str);
    my $id = ts6_id($user);
    ":$id MODE $id $str"
}

# ADMIN, INFO, MOTD, TIME, VERSION
#
# source:       user
# parameters:   hunted
#
sub admin   { generic_hunted('ADMIN',    @_) }
sub info    { generic_hunted('INFO',     @_) }
sub motd    { generic_hunted('MOTD',     @_) }
sub _time   { generic_hunted('TIME',     @_) }
sub version { generic_hunted('VERSION',  @_) }

sub generic_hunted {
    my ($command, $to_server, $source, $t_server) = (uc shift, @_);
    my $uid = ts6_id($source);
    my $sid = ts6_id($t_server);
    ":$uid $command $sid"
}

# LINKS
#
# source:       user
# parameters:   hunted, server mask
#
sub links  {
    my ($to_server, $user, $t_server, $query_mask) = @_;
    my $uid = ts6_id($user);
    my $sid = ts6_id($t_server);
    ":$uid LINKS $sid $query_mask"
}

# INVITE
#
# source:       user
# parameters:   target user, channel, opt. channelTS
# propagation:  one-to-one
#
sub invite {
    my ($to_server, $user, $t_user, $ch_name) = @_;

    # in JELP, the channel does not have to exist.
    # this is why the channel name is used here.
    # in TS6, invitations to nonexistent channels are not supported.
    my $channel = $pool->lookup_channel($ch_name);
    if (!$channel) {
        L("$$to_server{name} does not support invitations to nonexistent ".
          "channels; INVITE message dropped");
        return;
    }

    my $uid1 = ts6_id($user);
    my $uid2 = ts6_id($t_user);

    ":$uid1 INVITE $uid2 $$channel{name} $$channel{time}"
}

# REHASH
#
# charybdis TS6
# encap only
# source:       user
# parameters:   opt. rehash type
#
sub rehash {
    my ($to_server, $user, $serv_mask, $type, @servers) = @_;

    # server masks with $ are juno-specific and therefore not useful.
    undef $serv_mask if $serv_mask =~ m/\$/;

    my $uid = ts6_id($user);
    $type = length $type ? " :$type" : '';

    # if we have a mask, we can use it for encap propagation.
    if (length $serv_mask) {
        return ":$uid ENCAP $serv_mask REHASH$type";
    }

    # otherwise, we have to send a separate REHASH for each server.
    return map {
        sprintf ':%s ENCAP %s REHASH%s', $uid, ts6_id($_), $type
    } @servers;
}

# change user fields
sub userinfo {
    my ($to_server, $user, %fields) = @_;
    my @lines;

    # host changed
    push @lines, chghost($to_server, $user->{server}, $user, $fields{host})
        if length $fields{host};

    return @lines;
}

$mod
