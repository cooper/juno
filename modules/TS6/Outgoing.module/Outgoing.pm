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

use Scalar::Util qw(blessed);
use M::TS6::Utils qw(ts6_id ts6_prefixes ts6_prefix ts6_closest_level);
use utils qw(notice cut_to_length);
use modes;

our ($api, $mod, $pool, $me);
my ($TS_CURRENT, $TS_MIN) =(
    $M::TS6::Base::TS_CURRENT,
    $M::TS6::Base::TS_MIN
);

our %ts6_outgoing_commands = (
     quit           => \&quit,
     new_server     => \&sid,
     new_user       => \&euid,
     nick_change    => \&nick,
     umode          => \&umode,
     privmsgnotice  => \&privmsgnotice,
     join           => \&_join,
   # oper           => \&oper,
     away           => \&away,
     return_away    => \&return_away,
     part           => \&part,
     topic          => \&topic,
     cmode          => \&tmode,
     channel_burst  => [ \&sjoin_burst, \&bmask ],
     kill           => \&skill,
     connect         => \&_connect,
     kick           => \&kick,
     login          => \&login,
     signon         => \&signon,
     ping           => \&ping,
     pong           => \&pong,
     topicburst     => \&topicburst,
     wallops        => \&wallops,
     chghost        => \&chghost,
     realhost       => \&realhost,
     save_user      => \&save,
     update_user    => \&update_user,
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
     users          => \&users,
     invite         => \&invite,
     knock          => \&knock,
     snotice        => \&snote,
     su_login       => \&su_login,
     su_logout      => \&su_logout,
     force_nick     => \&rsfnc,
     force_update   => \&force_update_user,
     ircd_rehash    => \&rehash
);

sub init {
    $pool->on('server.send_ts6_burst' => \&send_burst, 'ts6.mainburst');
    $pool->on('server.send_ts6_burst' => \&send_endburst,
        name     => 'ts6.endburst',
        with_eo  => 1,
        priority => -1000
    );
}

sub send_burst {
    my ($server, $event) = @_;

    # SVINFO is always at the start of the burst I think.
    $server->sendfrom(ts6_id($me), "SVINFO $TS_CURRENT $TS_MIN 0 ".time());

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

        # SID
        $server->forward(new_server => $serv);
        $done{$serv} = 1;

    }; $do->($_) foreach $pool->all_servers;

    # users.
    foreach my $user ($pool->global_users) {

        # ignore users the server already knows!
        next if $user->{server} == $server || $user->{source} == $server->{sid};

        # (E)UID, ENCAP REALHOST, ENCAP LOGIN
        $server->forward(new_user => $user);

        # AWAY
        $server->forward(away => $user)
            if length $user->{away};
    }

    # channels.
    foreach my $channel ($pool->channels) {

        # SJOIN
        $server->forward(channel_burst => $channel, $me, $channel->users);

        # (E)TB, TOPIC
        $server->forward(topicburst => $channel)
            if $channel->topic;
    }

}

sub send_endburst {
    my ($server, $event) = @_;
    $server->send(
        $server->has_cap('eb') ? '' :
        sprintf ':%s PONG %s %s', ts6_id($me), $me->{name}, $server->{name}
    );
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

# ts6 host safety
sub safe_host {
    my ($host, $serv) = @_;

    # truncate when necessary
    if (my $limit = $serv->ircd_opt('truncate_hosts')) {
        $host = cut_to_length($limit, $host);
    }

    # replace slashes with dots when necessary
    # HACK: see issue #115
    if ($serv->ircd_opt('no_host_slashes')) {
        $host =~ s/\//\./g;
    }

    return $host;
}

# SID
#
# source:       server
# propagation:  broadcast
# parameters:   server name, hopcount, sid, server description
#
sub sid {
    my ($server, $serv) = @_;
    return if $server == $serv;

    # hidden?
    my $desc = $serv->{desc};
    $desc = "(H) $desc" if $serv->{hidden};

    sprintf ':%s SID %s %d %s :%s',
    ts6_id($serv->{parent}),            # source SID
    $serv->{name},                      # server name
    $me->hops_to($serv) + 1,            # hops away
    ts6_id($serv),                      # server SID
    $desc;                              # server description
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
sub euid {
    my ($server, $user) = @_;

    # no EUID support; use UID
    if (!$server->has_cap('EUID')) {
        my @uid_lines;

        # UID
        my $uid = sprintf ':%s UID %s %d %ld %s %s %s %s %s :%s',
            ts6_id($user->{server}),                # source SID
            safe_nick($user),                       # nickname
            $me->hops_to($user->{server}) + 1,      # number of hops
            $user->{nick_time},                     # last nick-change time
            $user->mode_string($server),            # +modes string
            $user->{ident},                         # username (w/ ~ if needed)
            safe_host($user->{cloak}, $server),     # visible hostname
            $user->{ip},                            # IP address
            ts6_id($user),                          # UID
            $user->{real};                          # real name
        push @uid_lines, $uid;

        # ENCAP REALHOST
        if ($user->{cloak} ne $user->{host}) {
            my $realhost = sprintf ':%s ENCAP * REALHOST %s',
                ts6_id($user),                      # source UID
                safe_host($user->{host}, $server);  # real hostname
            push @uid_lines, $realhost;
        }

        # ENCAP LOGIN
        if ($user->{account}) {
            push @uid_lines, login($server, $user, $user->{account}{name});
        }

        return @uid_lines;
    }

    # server supports EUID

    sprintf ":%s EUID %s %d %d %s %s %s %s %s %s %s :%s",
    ts6_id($user->{server}),                        # source SID
    safe_nick($user),                               # nickname
    $me->hops_to($user->{server}) + 1,              # number of hops
    $user->{nick_time},                             # last nick-change time
    $user->mode_string($server),                    # +modes string
    $user->{ident},                                 # username (w/ ~ if needed)
    safe_host($user->{cloak}, $server),             # visible hostname
    $user->{ip},                                    # IP address
    ts6_id($user),                                  # UID
    $user->{cloak} eq $user->{host} ?               # real hostname
        '*' : safe_host($user->{host}, $server),    #   (* if equal to visible)
    $user->{account} ?                              # account name
        $user->{account}{name} : '*',               #   (* if not logged in)
    $user->{real};                                  # real name
}

# SJOIN
#
# source:       server
# propagation:  broadcast
# parameters:   channelTS, channel, simple modes,
#               opt. mode parameters..., nicklist
#
# $server    = server object we're sending to
# $channel   = channel object
# $serv      = server source of the message
# $modes     = moderef
# @members   = channel members (user objects)
#
sub sjoin {
    my ($server, $channel, $serv, $modes, @members) = @_;
    my $mode_str = $modes->to_string($server, 1);

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
        );
    } @member_str;
}

# for bursting, send SJOIN with all simple modes.
sub sjoin_burst {
    my ($server, $channel, $serv, @members) = @_;
    my $modes = $channel->modes_with(0, 1, 2, 5);
    return sjoin(
        $server,        # destination server
        $channel,       # channel
        $serv,          # source server
        $modes,         # moderef
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
sub _join {
    my ($server, $user, $channel, $time) = @_; # why $time?
    my @channels = ref $channel eq 'ARRAY' ? @$channel : $channel;
    my @lines;
    foreach my $channel (@channels) {

        # there's only one user, so this channel was just created.
        # we will just pretend we're bursting, sending the single user with
        # modes from THIS local server ($me).
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
# parameters:   nickname, hopcount, nickTS, umodes, username, hostname, server,
#               gecos
#
sub nick {
    my ($server, $user) = @_;
    sprintf ':%s NICK %s :%d',
    ts6_id($user),          # source UID
    safe_nick($user),       # TS6-safe nickname
    $user->{nick_time};     # nick TS
}

# TMODE
#
# source:       any
# parameters:   channelTS, channel, cmode changes, opt. cmode parameters...
#
sub tmode {
    my ($server, $source, $channel, $time, $perspective, $mode_str) = @_;

    # convert to TS6
    $mode_str = $perspective->convert_cmode_string($server, $mode_str, 1);
    return if !length $mode_str;

    sprintf ":%s TMODE %d %s %s",
    ts6_id($source),        # UID or SID
    $time,                  # channel TS
    $channel->{name},       # channel name
    $mode_str;              # mode string in target perspective
}

# BMASK
#
# source:       server
# propagation:  broadcast
# parameters:   channelTS, channel, type, space separated masks
#
sub bmask {
    my ($server, $channel) = @_;
    my @lines;

    foreach my $mode_name (keys %{ $server->{cmodes} }) {

        # ignore all non-list modes
        next unless $server->cmode_type($mode_name) == MODE_LIST;

        # find the items and the mode letter
        my @items  = $channel->list_elements($mode_name);
        my $letter = $server->cmode_letter($mode_name);

        # construct multiple messages if necessary
        my $base = my $str = sprintf(':%s BMASK %d %s %s ',
            ts6_id($me),        # source SID
            $channel->{time},   # channel TS
            $channel->{name},   # channel name
            $letter             # banlike mode letter
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

# wrapper which uses whichever topic burst method is available
# the $source_maybe and %opts may be not be available on initial burst.
#
# source      => $s_serv
# old         => the old $channel->{topic}
# channel_ts  => $channel->{time}
#
sub topicburst {
    my ($to_server, $channel, %opts) = @_;

    # if this is MY burst, use TB.
    # don't waste time trying to guess what to do.
    #
    # <jilles> mad, ETB is not used in bursts for compatibility reasons, since
    #   there is no way to force a non-ETB server to apply the correct change
    #   in the general case
    # <jilles> once non-ETB servers are deemed uninteresting/obsolete,
    #   it's possible to use ETB in bursts
    #
    if ($to_server->{i_am_burst} && $to_server->has_cap('TB')) {
        return tb($to_server, $channel);
    }

    # find the stuff we need
    $opts{new}        ||= $channel->{topic}; # or undef
    $opts{source}     ||= $me;
    $opts{channel_ts} ||= $channel->{time};
    my ($source, $old, $new, $ch_time) = @opts{ qw(source old new channel_ts) };

    # if we can use ETB, this is very simple.
    if ($to_server->has_cap('EOPMOD')) {
        return etb($to_server, $channel, %opts);
    }

    # determine if the text has changed.
    my $text_changed = !$old || $new && $old->{topic} ne $new->{topic};

    # use TB if possible.
    if ($to_server->has_cap('TB')) {
        my $can_use_tb =
            $text_changed && # TB is only useful if the text has changed
            $new && length $new->{topic} && # it cannot unset topics
            (!$old || $old->{time} > $new->{time}); # topicTS has to be newer
        return tb($to_server, $channel, %opts) if $can_use_tb;
    }

    # we can't use TB. fall back to TOPIC.
    # note that this will fail if the source is not a user.
    # ($to_server, $source, $channel, undef, $topic
    return topic(
        $to_server, $source, $channel, undef,
        $new ? $new->{topic} : ''
    ) if $text_changed;

    return;
}

# TB
#
# capab:        TB
# source:       server
# propagation:  broadcast
# parameters:   channel, topicTS, opt. topic setter, topic
#
sub tb {
    my ($to_server, $channel) = @_;
    return unless $channel->topic;

    sprintf ':%s TB %s %d %s:%s',
    ts6_id($me),                # source SID
    $channel->{name},           # channel name
    $channel->{topic}{time},    # topic TS
    $to_server->ircd_opt('burst_topicwho') ? "$$channel{topic}{setby} " : '',
    $channel->{topic}{topic};   # topic
}

# ETB
# capab:        EOPMOD
# source:       any
# propagation:  broadcast
# parameters:   channelTS, channel, topicTS, topic setter, opt. extensions,
#               topic
#
sub etb {
    my ($to_server, $channel, %opts) = @_;
    sprintf ':%s ETB %d %s %d %s :%s',
    ts6_id($opts{source}),                      # source UID or SID
    $opts{channel_ts},                          # channel TS
    $channel->{name},                           # channel name
    $opts{new} ? $opts{new}{time}  : 0,         # FIXME
    $opts{new} ? $opts{new}{setby} : $me->name, # FIXME
    $opts{new} ? $opts{new}{topic} : '';        # topic
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
    my ($to_server, $cmd, $source, $target, $message, %opts) = @_;

    # complex stuff
    return &privmsgnotice_opmod         if $opts{op_moderated};
    return &privmsgnotice_smask         if defined $opts{serv_mask};
    return &privmsgnotice_atserver      if defined $opts{atserv_serv};
    return &privmsgnotice_status        if defined $opts{min_level};

    $target or return;
    my $id  = ts6_id($source);
    my $tid = ts6_id($target);
    ":$id $cmd $tid :$message"
}

# Complex PRIVMSG
#
#   a message to all users on server names matching a mask
#       ('$$' followed by mask)
#   propagation: broadcast
#   Only allowed to IRC operators.
#
sub privmsgnotice_smask {
    my ($to_server, $cmd, $source, undef, $message, %opts) = @_;
    my $server_mask = $opts{serv_mask};
    my $id = ts6_id($source);
    ":$id $cmd \$\$$server_mask :$message"
}

# - Complex PRIVMSG
#   '=' followed by a channel name, to send to chanops only, for cmode +z.
#   capab:          CHW and EOPMOD
#   propagation:    all servers with -D chanops
#
# charybdis@8fed90ba8a221642ae1f0fd450e8e580a79061fb/ircd/send.cc#L581
#
sub privmsgnotice_opmod {
    my ($to_server, $cmd, $source, $target, $message, %opts) = @_;
    return if !$target->isa('channel');

    # unfortunately we can't do anything for servers without CHW.
    return if !$to_server->has_cap('CHW');

    # if the target server has EOPMOD, we can use the '=' prefix.
    if ($to_server->has_cap('EOPMOD')) {
        return sprintf ':%s %s =%s :%s',
        ts6_id($source),        # source UID or SID
        $cmd,                   # PRIVMSG or NOTICE
        $target->name,          # channel name
        $message;               # message text
    }

    # no EOPMOD. use NOTICE @#channel
    #
    # note: charybdis also checks if the channel is moderated, and if so,
    # sends a normal PRIVMSG or NOTICE from the original source. I don't know
    # why that would be desirable though, because it would go to all members?
    #
    $target or return;
    return sprintf ':%s NOTICE @%s :<%s:%s> %s',
    ts6_id($source->server),    # source's server SID
    $target->name,              # channel name
    $source->name,              # source nickname or server name
    $target->name,              # channel name
    $message;                   # message text
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
    my $id = ts6_id($source);
    ":$id $cmd $opts{atserv_nick}\@$opts{atserv_serv}{name} :$message"
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

    # convert the level to the nearest TS6 prefix
    my $level  = ts6_closest_level($to_server, $opts{min_level});
    my $prefix = ts6_prefix($to_server, $level);
    defined $prefix or return;

    my $id = ts6_id($source);
    my $ch_name = $channel->name;
    ":$id $cmd $prefix$ch_name :$message"
}

# PART
#
# source:       user
# parameters:   comma separated channel list, message
#
sub part {
    my ($to_server, $user, $channel, $reason) = @_;
    my $id = ts6_id($user);
    $reason //= '';
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
# SQUIT
# parameters:   target server, comment
#
sub quit {
    my ($to_server, $object, $reason, $from) = @_;
    $object = $object->type if $object->isa('connection');

    # if it's a server, SQUIT.
    if ($object->isa('server')) {
        $from ||= $object->{parent};
        return sprintf ":%s SQUIT %s :%s",
        ts6_id($from),
        ts6_id($object),
        $reason;
    }

    my $id = ts6_id($object);
    ":$id QUIT :$reason"
}

# KICK
#
# source:       any
# parameters:   channel, target user, opt. reason
# propagation:  broadcast
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
sub topic {
    my ($to_server, $source, $channel, undef, $topic) = @_;

    # can't do anything about this.
    if (!$source->isa('user')) {
        notice(server_protocol_warning =>
            $to_server->notice_info,
            'cannot be sent topic change due to protocol limitations'
        );
        return;
    }

    # consider: charybdis has some crazy stuff to send SJOIN with the user
    # opped, set the topic, and then part immediately after if the user is not
    # in the channel.
    # charybdis@8fed90ba8a221642ae1f0fd450e8e580a79061fb/modules/m_tb.cc#L207

    my $uid = ts6_id($source);
    ":$uid TOPIC $$channel{name} :$topic"
}

# KILL
#
# source:       any
# parameters:   target user, path
# propagation:  broadcast
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

# REALHOST
#
# charybdis TS6
# encap only
# encap target: *
# source:       user
# parameters:   real hostname
#
sub realhost {
    my ($to_server, $user, $host) = @_;
    my $uid = ts6_id($user);
    ":$uid ENCAP * REALHOST $host"
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

# ADMIN, INFO, MOTD, TIME, VERSION, USERS
#
# source:       user
# parameters:   hunted
#
sub admin   { generic_hunted('ADMIN',    @_) }
sub info    { generic_hunted('INFO',     @_) }
sub motd    { generic_hunted('MOTD',     @_) }
sub _time   { generic_hunted('TIME',     @_) }
sub version { generic_hunted('VERSION',  @_) }
sub users   { generic_hunted('USERS',    @_) }

# this can only be used for commands with a user source and one hunted parameter
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
    my $channel = blessed $ch_name ? $ch_name : $pool->lookup_channel($ch_name);
    if (!$channel) {
        notice(server_protocol_warning =>
            $to_server->notice_info,
            'does not support invitations to nonexistent channels; '.
            'invite message dropped'
        );
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

sub force_update_user {
    my ($to_server, $source_serv, @rest) = @_;
    return _update_user($source_serv, $to_server, @rest);
}

# change user fields
sub update_user  { _update_user(undef, @_) }
sub _update_user {
    my ($source_serv, $to_server, $user, %fields) = @_;
    my @lines;

    # if we have all the required fields, use SIGNON.
    my @needed = qw(nick ident host nick_time account);
    if (scalar(grep { defined $fields{$_} } @needed) == @needed) {
        undef $fields{account} if $fields{account} eq '*';
        return signon($to_server, $user, @fields{@needed});
    }

    # host changed
    push @lines, chghost(
        $to_server,
        $source_serv || $user->{server},        # source server
        $user,                                  # the user
        safe_host($fields{host}, $to_server)    # TS6-safe new visible host
    ) if length $fields{host};

    return @lines;
}

# SIGNON
#
# source:       user
# propagation:  broadcast
# parameters:   new nickname, new username, new visible hostname,
#               new nickTS, new login name
#
sub signon {
    my ($to_server, $user, $new_nick, $new_ident, $new_host,
        $new_nick_time, $new_act_name) = @_;
    $new_act_name = '0' if !length $new_act_name;
    sprintf ':%s SIGNON %s %s %s %s %s',
    ts6_id($user),      # source UID
    $new_nick,          # new nickname
    $new_ident,         # new username
    $new_host,          # new visible hostname
    $new_nick_time,     # new nick TS
    $new_act_name;      # new account name
}

# CONNECT
#
# source:       any
# parameters:   server to connect to, port, hunted
#
sub _connect {
    my ($to_server, $source, $connect_mask, $t_server) = @_;
    my $id  = ts6_id($source);
    my $sid = ts6_id($t_server);
    ":$id CONNECT $connect_mask 0 $sid"
}

# LUSERS
#
# source:       user
# parameters:   server mask, hunted
#
sub lusers {
    my ($to_server, $user, $t_server) = @_;
    my $uid = ts6_id($user);
    my $sid = ts6_id($t_server);
    ":$uid LUSERS * $sid"
}

# SNOTE
#
# charybdis TS6
# encap only
# source:       server
# parameters:   snomask letter, text
#
sub snote {
    my ($to_server, $server, $flag, $message, undef, $ts6_letter) = @_;
    my $sid = ts6_id($server);
    # no letter; this is a juno snotice
    if (!$ts6_letter) {
        $ts6_letter = 's';
        (my $pretty = ucfirst $flag) =~ s/_/ /g;
        $message = "$pretty: $message";
    }
    ":$sid ENCAP * SNOTE $ts6_letter :$message"
}

# RSFNC
#
# encap only
# capab:        RSFNC
# encap target: single server
# source:       services server
# parameters:   target user, new nickname, new nickTS, old nickTS
#
sub rsfnc {
    my ($to_server, $server, $user, $new_nick, $new_nick_ts, $old_nick_ts) = @_;
    sprintf ':%s ENCAP %s RSFNC %s %s %d %d',
    ts6_id($server),        # services server SID
    $user->server->name,    # user's server name (ENCAP target)
    ts6_id($user),          # UID
    $new_nick,              # new nickname
    $new_nick_ts,           # new nick TS
    $old_nick_ts;           # old nick TS
}

# KNOCK
#
# capab:        KNOCK
# source:       user
# parameters:   channel
# propagation:  broadcast
#
sub knock {
    my ($to_server, $user, $channel) = @_;

    # KNOCK not supported
    return if !$to_server->has_cap('KNOCK');

    sprintf ':%s KNOCK %s',
    ts6_id($user),
    $channel->name;
}

$mod
