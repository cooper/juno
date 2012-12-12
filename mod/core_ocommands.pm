# Copyright (c) 2012, Mitchell Cooper
package ext::core_ocommands;
 
use warnings;
use strict;
use feature 'switch';

use utils qw(gv);

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
    connect       => \&sconnect
);

our $mod = API::Module->new(
    name        => 'core_ocommands',
    version     => '0.7',
    description => 'the core set of outgoing commands',
    requires    => ['outgoing_commands'],
    initialize  => \&init
);

sub init {

    # register outgoing commands
    $mod->register_outgoing_command(
        name => $_,
        code => $ocommands{$_}
    ) || return foreach keys %ocommands;

    return 1
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
        $channel->{topic}->{setby},
        $channel->{topic}->{time},
        $channel->{topic}->{topic}
    );
    my $sid = gv('SERVER')->{sid};
    ":$sid $cmd"
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
sub cum {
    my $channel = shift;
    # modes are from the perspective of this server, gv:SERVER

    my (%prefixes, @userstrs);

    my (@modes, @user_params, @server_params);
    my @set_modes = sort { $a cmp $b } keys %{$channel->{modes}};

    foreach my $name (@set_modes) {
      my $letter = gv('SERVER')->cmode_letter($name);
      given (gv('SERVER')->cmode_type($name)) {

        # modes with 0 or 1 parameters
        when ([0, 1, 2]) { push @modes, $letter; continue }

        # modes with EXACTLY ONE parameter
        when ([1, 2]) { push @server_params, $channel->{modes}->{$name}->{parameter} }

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
                if (exists $prefixes{$user}) { $prefixes{$user} .= $letter }
                                        else { $prefixes{$user}  = $letter }
            } # ugly br
        } # ugly bracke
    } } # ugly brackets 

    # make +modes params string without status modes
    my $modestr = '+'.join(' ', join('', @modes), @server_params);

    # create an array of uid!status
    foreach my $user (@{$channel->{users}}) {
        my $str = $user->{uid};
        $str .= '!'.$prefixes{$user} if exists $prefixes{$user};
        push @userstrs, $str
    }

    # note: use "-" if no users present
    ':'.gv('SERVER')->{sid}." CUM $$channel{name} $$channel{time} ".(join(',', @userstrs) || '-')." :$modestr"
}

# add cmodes
sub acm {
    my $serv  = shift;

    my @modes = map { 
        "$_:".$serv->cmode_letter($_).':'.$serv->cmode_type($_)
    } keys %{$serv->{cmodes}};

    ":$$serv{sid} ACM ".join(' ', @modes)
}

# add umodes
sub aum {
    my $serv  = shift;

    my @modes = map {
       "$_:".$serv->umode_letter($_)
    } keys %{$serv->{umodes}};

    ":$$serv{sid} AUM ".join(' ', @modes)
}

$mod
