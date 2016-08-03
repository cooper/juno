# Copyright (c) 2016, Mitchell Cooper
#
# @name:            'Ban::Info'
# @package:         'M::Ban::Info'
# @description:     'objective representation of a ban'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Ban::Info;

use warnings;
use strict;
use 5.010;

use utils qw(pretty_time pretty_duration);

our ($api, $mod, $pool, $conf, $me);
my ($table, %unordered_format, @format);

# specification
# -----
#
#   RECORDED IN DATABASE
#
# id            ban identifier
#
#               IDs are unique globally, not just per server or per ban type
#               in the format of <server ID>.<local ID>
#               where <server ID> is the SID of the server on which the ban was created
#               and <local ID> is a numeric ID of the ban which is specific to that server
#               e.g. 0.1
#
# type          string representing type of ban
#               e.g. kline, dline, ...
#
# match         mask or string to match
#               string representing what to match
#               e.g. *@example.com, 127.0.0.*, ...
#
# duration      duration of ban in seconds
#               or 0 if the ban is permanent
#               e.g. 300 (5 minutes)
#
# added         UTC timestamp when the ban was added
#
# modified      UTC timestamp when the ban was last modified
#
# expires       UTC timestamp when ban will expire and no longer be in effect
#               or 0 if the ban is permanent
#
# lifetime      UTC timestamp when ban should be removed from the database
#               or nothing/0 if it is the same as 'expires'
#
# auser         mask of user who added the ban
#               e.g. someone!someone[@]somewhere
#
# aserver       name of server where ban was added
#               e.g. s1.example.com
#
# reason        user-set reason for ban
#
#   NOT RECORDED IN DATABASE
#
# inactive      set by activate_ban() so that we know not to enforce an
#               expired ban
#
# _just_set_by  SID/UID of who set a ban. used for propagation
#

sub init {
    $table = $M::Ban::table or return;
    %unordered_format = @format = @M::Ban::format or return;
    return 1;
}

####################
### CONSTRUCTORS ###
################################################################################

# construct a ban object
sub construct {
    my ($class, %opts) = @_;
    my $ban = bless \%opts, $class;
    $ban->validate or return;
    return $ban;
}

# construct a ban object from db with ID
sub construct_by_id {
    my ($class, $id) = @_;
    my %ban_info = $table->row(id => $id)->select_hash;
    %ban_info or return;
    return $class->construct(%ban_info);
}

# construct a ban object from db with matcher
sub construct_by_type_match {
    my ($class, $type, $match) = @_;
    my %ban_info = $table->row(type => $type, match => $match)->select_hash;
    %ban_info or return;
    return $class->construct(%ban_info);
}

##########################
### HIGH-LEVEL METHODS ###
################################################################################

# $ban->activate
#
# enables enforcement and expiration timer when necessary. this is used just
# as a ban is introduced or when it is resurrected from the database.
#
sub activate {
    my $ban = shift;

    # activate the timer as long as it is not permanent.
    # ifs lifetime is over when calling this, it will be immediately destroyed.
    $ban->activate_timer or return
        if $ban{lifetime};

    # only activate enforcement if the ban has not expired.
    $ban->activate_enforcement
        if !$ban{expires} || $ban{expires} > time;

    return 1;
}

# $ban->disable
#
# changes the ban's modified time to the current time (plus one second) and then
# copies that to the expire time. this way the ban will be preserved in the
# database until its lifetime is over, but it will no longer be enforced.
#
# does NOT (and you should not) deactivate expiration timer.
# does NOT (and you should not) remove the ban from the database.
#
sub disable {
    my $ban = shift;

    # update the expire time
    if ($ban->{modified} < time) {
        $ban->{modified} = time;
    }
    else {
        $ban->{modified}++;
    }
    $ban->{expires} = $ban->{modified};

    # disable enforcement
    $ban->deactivate_enforcement;

    # update the ban in the db
    $ban->_db_update(%ban);
}

# $ban->validate
#
# checks that the info is valid and returns false if not.
# injects missing data when possible.
#
sub validate {
    my $ban = shift;
    $ban->{added}     ||= time;
    $ban->{modified}  ||= $ban{added};
    $ban->{expires}   ||= $ban{duration} ? time + $ban{duration} : 0;
    $ban->{lifetime}  ||= $ban{expires};
    return 1;
}

sub update {
    my ($ban, %opts) = @_;
    $ban{ keys %opts } = values %opts;
    $ban->validate or return;
    $ban->_db_update;
    return 1;
}

###################
### ENFORCEMENT ###
################################################################################

# (re)activate ban enforcement
sub activate_enforcement {
    my $ban = shift;
    $ban->deactivate_enforcement if $ban->{enforcement_active}++;
    M::Ban::_activate_ban_enforcement($ban);
}

# deactivate ban enforcement
sub deactivate_enforcement {
    my $ban = shift;
    delete $ban->{enforcement_active} or return;
    M::Ban::_deactivate_ban_enforcement($ban);
}

# enforce the ban
sub enforce {

}

##############
### TIMERS ###
################################################################################

# (re)activate the ban timer
sub activate_timer {
    my $ban = shift;
    $ban->deactivate_timer if $ban->{timer_active}++;
    M::Ban::_activate_ban_timer($ban);
}

# deactivate the ban timer
sub deactivate_timer {
    my $ban = shift;
    delete $ban->{timer_active} or return;
    M::Ban::_deactivate_ban_timer($ban);
}

#####################
### NOTIFICATIONS ###
################################################################################

# notify opers of a new ban
sub notify_new {
    my ($source, $ban) = @_;
    my @user = $source if $source->isa('user') && $source->is_local;
    notice(@user, $ban->type =>
        ucfirst $ban->hr_ban_type,
        $ban->{match},
        $source->notice_info,
        $ban->hr_expires,
        $ban->hr_duration,
        $ban->hr_reason
    );
}

# notify opers of a deleted ban
sub notify_delete {
    my ($source, $ban) = @_;
    my @user = $source if $source->isa('user') && $source->is_local;
    notice(@user, "$$ban{type}_delete" =>
        ucfirst $ban->hr_ban_type,
        $ban->{match},
        $source->notice_info,
        $ban->hr_reason
    );
}

################
### DATABASE ###
################################################################################

# insert or update the ban
sub _db_update {
    my $ban = shift;
    my %ban_info = %$ban;
    delete @ban_info{ grep !$unordered_format{$_}, keys %ban_info };
    $table->row(id => $ban->id)->insert_or_update(%ban_info);
}

# delete the ban
sub _db_delete {
    my $ban = shift;
    $table->row(id => $ban->id)->delete;
}

###############
### GETTERS ###
################################################################################

sub id { shift->{id} }

# $ban->type
# $ban->type('hname')
sub type {
    my $type = shift->{type};
    my $key = shift;
    return $type->{$key} if defined $key;
    return $type;
}

# Human-readable stuff

# ban type
sub hr_ban_type {
    return shift->type('hname') || 'ban';
}

# expire time
sub hr_expires  {
    my $expires = shift->{expires};
    return 'never' if !$expires;
    return pretty_time($expires);
}

# duration
sub hr_duration {
    my $duration = shift->{duration};
    return 'permanent' if !$duration;
    return pretty_duration($duration);
}

# reason
sub hr_reason {
    my $reason = shift->{reason};
    return 'no reason' if !length $reason;
    return $reason;
}

$mod
