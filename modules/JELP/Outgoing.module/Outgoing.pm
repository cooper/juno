# Copyright (c) 2010-14, Mitchell Cooper
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

our ($api, $mod, $me, $pool);

my %ocommands = (
    quit            => \&quit,
    new_server      => [ \&sid, \&aum, \&acm ],          # sid / aum / acm
    new_user        => \&uid,                               # uid
    nickchange      => \&nickchange,
    umode           => \&umode,
    privmsgnotice   => \&privmsgnotice,
    join            => \&_join,                             # sjoin
    oper            => \&oper,
    away            => \&away,
    return_away     => \&return_away,
    part            => \&part,
    topic           => \&topic,
    cmode           => \&cmode,
    channel_burst   => [ \&cum, \&topicburst ],         # cum
    create_channel  => \&cum,
    kill            => \&skill,
    connect         => \&sconnect,
    kick            => \&kick,
    num             => \&num,
    links           => \&links,
    
    # JELP-specific
    
    acm             => \&acm,
    aum             => \&aum
    
);

sub init {

    # register outgoing commands
    $mod->register_outgoing_command(
        name => $_,
        code => $ocommands{$_}
    ) || return foreach keys %ocommands;

    # register server burst events.
    $pool->on('server.send_jelp_burst' => \&send_burst,
        name     => 'core',
        with_eo  => 1
    );
    $pool->on('server.send_jelp_burst' => \&send_startburst,
        name     => 'startburst',
        with_eo  => 1,
        priority => 1000
    );
    $pool->on('server.send_jelp_burst' => \&send_endburst,
        name     => 'endburst',
        with_eo  => 1,
        priority => -1000
    );
    
    return 1;
}

#############
### BURST ###
#############

sub send_startburst {
    my ($server, $fire, $time) = @_;
    $server->sendme("BURST $time");
}

sub send_burst {
    my ($server, $fire, $time) = @_;

    # servers and mode names
    my ($do, %done);

    # first, send modes of this server.
    $server->fire_command(aum => $me);
    $server->fire_command(acm => $me);

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
        $server->fire_command(channel_burst => $channel);
    }
    
}

sub send_endburst {
    shift->sendme('ENDBURST '.time);
}

###########
# servers #
###########

sub quit {
    my ($to_server, $connection, $reason) = @_;
    my $id = $connection->{type}->id;
    ":$id QUIT :$reason"
}

# new user
sub uid {
    my ($to_server, $user) = @_;
    my $cmd = sprintf(
        'UID %s %d %s %s %s %s %s %s :%s',
        $user->{uid}, $user->{time}, $user->mode_string,
        $user->{nick}, $user->{ident}, $user->{host},
        $user->{cloak}, $user->{ip}, $user->{real}
    );
    ":$$user{server}{sid} $cmd"
}

sub sid {
    my ($to_server, $serv) = @_;
    return if $to_server == $serv;
    my $cmd = sprintf(
        'SID %s %d %s %s %s :%s',
        $serv->{sid},   $serv->{time}, $serv->{name},
        $serv->{proto}, $serv->{ircd}, $serv->{desc}
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


#########
# users #
#########

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
    my ($to_server, $cmd, $source, $target, $message) = @_;
    my $id  = $source->id;
    my $tid = $target->id;
    ":$id $cmd $tid :$message"
}


# channel join
sub _join {
    my ($to_server, $user, $channel, $time) = @_;
    ":$$user{uid} JOIN $$channel{name} $time"
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
    my ($to_server, $user, $channel, $time, $reason) = @_;
    $reason ||= q();
    ":$$user{uid} PART $$channel{name} $time :$reason"
}


sub topic {
    my ($to_server, $user, $channel, $time, $topic) = @_;
    ":$$user{uid} TOPIC $$channel{name} $$channel{time} $time :$topic"
}

sub sconnect {
    my ($to_server, $user, $server, $tname) = @_;
    ":$$user{uid} CONNECT $$server{name} $tname"
}

########
# both #
########

# channel mode change

sub cmode {
    my ($to_server, $source, $channel, $time, $perspective, $modestr) = @_;
    return unless length $modestr;
    my $id = $source->id;
    ":$id CMODE $$channel{name} $time $perspective :$modestr"
}

# kill

sub skill {
    my ($to_server, $source, $tuser, $reason) = @_;
    my ($id, $tid) = ($source->id, $tuser->id);
    ":$id KILL $tid :$reason"
}

####################
# COMPACT commands #
####################

# channel user membership (channel burst)
# $server = server to send to
# @users  = for create_channel only, the users to send.
sub cum {
    my ($server, $channel, $serv, @users) = @_;
    
    # make +modes params string without status modes.
    # modes are from the perspective of this server, $me.
    my $modestr = $channel->mode_string_all($me, 1);
    
    # fetch the prefixes for each user.
    my (%prefixes, @userstrs);
    foreach my $name (keys %{ $channel->{modes} }) {
        next if $me->cmode_type($name) != 4;
        my $letter = $me->cmode_letter($name);
        ($prefixes{$_} //= '') .= $letter foreach $channel->list_elements($name);
    }

    # create an array of uid!status
    @users = $channel->users if !@users;
    foreach my $user (@users) {
    
        # this is the server that told us about the user. it already knows.
        next if $user->{location} == $server;
        
        my $str = $user->{uid};
        $str .= '!'.$prefixes{$user} if exists $prefixes{$user};
        push @userstrs, $str;
    }

    # note: use "-" if no users present
    ":$$me{sid} CUM $$channel{name} $$channel{time} ".(join(',', @userstrs) || '-')." :$modestr"
}

# add cmodes
sub acm {
    my ($to_server, $serv, $modes) = (shift, shift, '');

    # iterate through each mode on the server.
    foreach my $name (keys %{ $serv->{cmodes} }) {
        my ($letter, $type) = ($serv->cmode_letter($name), $serv->cmode_type($name));
        
        # first, make sure this isn't garbage.
        next if !defined $letter || !defined $type;
        
        # it's not. append it to the mode list.
        $modes .= " $name:$letter:$type";

    }
    
    return unless length $modes;
    return ":$$serv{sid} ACM$modes";
}

# add umodes
sub aum {
    my ($to_server, $serv) = (shift, shift);

    my @modes = map {
       "$_:".($serv->umode_letter($_) || '')
    } keys %{ $serv->{umodes} };

    # if there are none, just don't.
    scalar @modes or return;

    ":$$serv{sid} AUM ".join(' ', @modes)
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
    my ($to_server, $user, $target_server, $server_mask, $query_mask) = @_;
    ":$$user{uid} LINKS $$target_server{sid} $server_mask $query_mask"
}

$mod
