# Copyright (c) 2010-14, Mitchell Cooper
#
# @name:            "JELP::Outgoing"
# @version:         ircd->VERSION
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
    quit          => \&quit,
    sid           => \&sid,
    addumode      => \&addumode,
    addcmode      => \&addcmode,
    topicburst    => \&topicburst,
    uid           => \&uid,
    nickchange    => \&nickchange,
    umode         => \&umode,
    privmsgnotice => \&privmsgnotice,
    sjoin         => \&sjoin,
    oper          => \&oper,
    away          => \&away,
    return_away   => \&return_away,
    part          => \&part,
    topic         => \&topic,
    cmode         => \&cmode,
    cum           => \&cum,
    acm           => \&acm,
    aum           => \&aum,
    kill          => \&skill,
    connect       => \&sconnect,
    kick          => \&kick
);

sub init {

    # register outgoing commands
    $mod->register_outgoing_command(
        name => $_,
        code => $ocommands{$_}
    ) || return foreach keys %ocommands;

    # register server burst event.
    $mod->manage_object($pool);
    $pool->on('server.send_burst' => \&send_burst, name => 'core', with_evented_obj => 1);
    
    return 1;
}

###########
# servers #
###########

sub quit {
    my ($connection, $reason) = @_;
    my $id = $connection->{type}->id;
    ":$id QUIT :$reason"
}

# new user
sub uid {
    my $user = shift;
    my $cmd  = sprintf(
        'UID %s %d %s %s %s %s %s %s :%s',
        $user->{uid}, $user->{time}, $user->mode_string,
        $user->{nick}, $user->{ident}, $user->{host},
        $user->{cloak}, $user->{ip}, $user->{real}
    );
    ":$$user{server}{sid} $cmd"
}

sub sid {
    my $serv = shift;
    my $cmd  = sprintf(
        'SID %s %d %s %s %s :%s',
        $serv->{sid}, $serv->{time}, $serv->{name},
        $serv->{proto}, $serv->{ircd}, $serv->{desc}
    );
    ":$$serv{parent}{sid} $cmd"
}

sub addumode {
    my ($serv, $name, $mode) = @_;
    ":$$serv{sid} ADDUMODE $name $mode"
}

sub addcmode {
    my ($serv, $name, $mode, $type) = @_;
    ":$$serv{sid} ADDCMODE $name $mode $type"
}


sub topicburst {
    my $channel = shift;
    my $cmd     = sprintf(
        'TOPICBURST %s %d %s %d :%s',
        $channel->{name},
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
    my $user = shift;
    ":$$user{uid} NICK $$user{nick}"
}

# user mode change
sub umode {
    my ($user, $modestr) = @_;
    ":$$user{uid} UMODE $modestr"
}

# privmsg and notice
sub privmsgnotice {
    my ($cmd, $source, $target, $message) = @_;
    my $id  = $source->id;
    my $tid = $target->id;
    ":$id $cmd $tid :$message"
}


# channel join
sub sjoin {
    my ($user, $channel, $time) = @_;
    ":$$user{uid} JOIN $$channel{name} $time"
}


# add oper flags
sub oper {
    my ($user, @flags) = @_;
    ":$$user{uid} OPER @flags"
}


# set away
sub away {
    my $user = shift;
    ":$$user{uid} AWAY :$$user{away}"
}


# return from away
sub return_away {
    my $user = shift;
    ":$$user{uid} RETURN"
}

# leave a channel
sub part {
    my ($user, $channel, $time, $reason) = @_;
    $reason ||= q();
    ":$$user{uid} PART $$channel{name} $time :$reason"
}


sub topic {
    my ($user, $channel, $time, $topic) = @_;
    ":$$user{uid} TOPIC $$channel{name} $$channel{time} $time :$topic"
}

sub sconnect {
    my ($user, $server, $tname) = @_;
    ":$$user{uid} CONNECT $$server{name} $tname"
}

########
# both #
########

# channel mode change

sub cmode {
    my ($source, $channel, $time, $perspective, $modestr) = @_;
    my $id = $source->id;
    ":$id CMODE $$channel{name} $time $perspective :$modestr"
}

# kill

sub skill {
    my ($source, $tuser, $reason) = @_;
    my ($id, $tid) = ($source->id, $tuser->id);
    ":$id KILL $tid :$reason"
}

####################
# COMPACT commands #
####################

# channel user membership (channel burst)
# $server = server to send to
sub cum {
    my ($channel, $server) = @_;
    # modes are from the perspective of this server, v:SERVER

    my (%prefixes, @userstrs);

    my (@modes, @user_params, @server_params);
    my @set_modes = sort keys %{ $channel->{modes} };

    foreach my $name (@set_modes) {
      my $letter = $me->cmode_letter($name);
      given ($me->cmode_type($name)) {

        # modes with 0 or 1 parameters
        when ([0, 1, 2]) { push @modes, $letter; continue }

        # modes with EXACTLY ONE parameter
        when ([1, 2]) { push @server_params, $channel->{modes}{$name}{parameter} }

        # lists
        when (3) {
            foreach my $thing ($channel->list_elements($name)) {
                push @modes,         $letter;
                push @server_params, $thing
            }
        }

        # lists of users
        when (4) {
            foreach my $user ($channel->list_elements($name)) {
                ($prefixes{$user} //= '') .= $letter;
            }
        }
    } }

    # make +modes params string without status modes
    my $modestr = '+'.join(' ', join('', @modes), @server_params);

    # create an array of uid!status
    foreach my $user (@{ $channel->{users} }) {
    
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
    my $serv  = shift;
    my $modes = q();
    
    # iterate through each mode on the server.
    foreach my $name (keys %{ $serv->{cmodes} }) {
        my ($letter, $type) = ($serv->cmode_letter($name), $serv->cmode_type($name));
        
        # first, make sure this isn't garbage.
        next if !defined $letter || !defined $type;
        
        # it's not. append it to the mode list.
        $modes .= " $name:$letter:$type";

    }

    return ":$$serv{sid} ACM$modes";
}

# add umodes
sub aum {
    my $serv  = shift;

    my @modes = map {
       "$_:".($serv->umode_letter($_) || '')
    } keys %{ $serv->{umodes} };

    ":$$serv{sid} AUM ".join(' ', @modes)
}

# KICK command.
sub kick {
    my ($source, $channel, $target, $reason) = @_;
    my $sourceid = $source->can('id') ? $source->id : '';
    my $targetid = $target->can('id') ? $target->id : '';
    return ":$source KICK $$channel{name} $targetid :$reason";
}

#############
### BURST ###
#############

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
        $server->fire_command(sid => $serv);
        $done{$serv} = 1;
        
        # send modes using compact AUM and ACM
        $server->fire_command(aum => $serv);
        $server->fire_command(acm => $serv);
        
    }; $do->($_) foreach $pool->servers;


    # users
    foreach my $user ($pool->users) {

        # ignore users the server already knows!
        next if $user->{server} == $server || $user->{source} == $server->{sid};
        
        $server->fire_command(uid => $user);
        
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
        $server->fire_command(cum => $channel, $server);
        
        # there is no topic or this server is how we got the topic.
        next if !$channel->topic;
        
        $server->fire_command(topicburst => $channel);
    }
    
}

$mod
