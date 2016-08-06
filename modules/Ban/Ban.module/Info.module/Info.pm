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

use utils qw(notice pretty_time pretty_duration);

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
# added         UTC timestamp when the ban was added. note that the modification
#               time is used for most things; this is mostly only for showing
#               opers when the ban was first introduced.
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
        if $ban->lifetime;

    # only activate enforcement if the ban has not expired.
    # this will also enforce the ban immediately.
    $ban->activate_enforcement
        if !$ban->has_expired;

    return 1;
}

# $ban->disable
#
# changes the ban's modified time to the current time and then copies that to
# the expire time. this way the ban will be preserved in the database until its
# lifetime is over, but it will no longer be enforced.
#
# does NOT (and you should not) deactivate the expiration timer.
# does NOT (and you should not) remove the ban from the database.
#
sub disable {
    my $ban = shift;

    # update the expire time
    if ($ban->modified < time) {
        $ban->modified = time;
    }
    else {
        $ban->modified++;
    }
    $ban->expires = $ban->modified;

    # disable enforcement
    $ban->deactivate_enforcement;

    # reactivate timer
    $ban->activate_timer
        if $ban->{timer_active};

    # update the ban in the db
    $ban->_db_update;
}

# $ban->validate
#
# checks that the info is valid and returns false if not.
# injects missing data when possible.
#
sub validate {
    my $ban = shift;

    # inject missing stuff
    $ban->added     ||= time;
    $ban->modified  ||= $ban->added;
    $ban->expires   ||= $ban->duration ? time + $ban->duration : 0;
    $ban->lifetime  ||= $ban->expires;

    # fix stuff that doesn't make sense
    $ban->lifetime = $ban->expires
        if $ban->lifetime < $ban->expires;

    # separate user and host fields
    if (!length $ban->match_host || !length $ban->match_user) {
        if ($ban->match =~ m/^(.*?)\@(.*)$/) {
            $ban->match_user = $1;
            $ban->match_host = $2;
        }
        else {
            $ban->match_user = '*';
            $ban->match_host = $ban->match;
        }
    }

    # at this point, we have to give up if any of these are missing.
    for (qw[ id type match duration ]) {
        next if defined $ban->{$_};
        warn "\$ban->validate() failed because '$_' is missing!";
        return;
    }

    return 1;
}

sub update {
    my ($ban, %opts) = @_;

    # do not accept a shorter lifetime
    if (exists $opts{lifetime} && $ban->lifetime > $opts{lifetime}) {
        delete $opts{lifetime};
    }

    # inject these options and validate.
    @$ban{ keys %opts } = values %opts;
    $ban->validate or return;

    # reactivate timer in case the expires/lifetime changed.
    $ban->activate_timer
        if $ban->{timer_active};

    $ban->_db_update;
    return 1;
}

# deactivate everything, remove from db, remove from ban table
sub destroy {
    my $ban = shift;

    # disable enforcement and timer
    $ban->deactivate_enforcement;
    $ban->deactivate_timer;

    # remove from db
    $ban->_db_delete;

    # remove from ban table
    M::Ban::_destroy_ban($ban);

}

###################
### ENFORCEMENT ###
################################################################################

# (re)activate ban enforcement
sub activate_enforcement {
    my $ban = shift;

    # disable if it was enabled
    $ban->deactivate_enforcement if $ban->{enforcement_active};

    # Custom activation
    # -----------------
    my $activate = $ban->type('activate_code');
    $activate->($ban) if $activate;

    # enable enforcement
    $ban->{enforcement_active}++;
    M::Ban::_activate_ban_enforcement($ban);

    # enforce the ban immediately
    $ban->enforce;

    return 1;
}

# deactivate ban enforcement
sub deactivate_enforcement {
    my $ban = shift;

    # check if enabled
    delete $ban->{enforcement_active} or return;

    # Custom deactivation
    # -------------------
    my $disable = $ban->type('disable_code');
    $disable->($ban) if $disable;

    # disable enforcement
    return M::Ban::_deactivate_ban_enforcement($ban);
}

# enforce the ban immediately on anything affected
sub enforce {
    my ($ban, @affected) = shift;
    push @affected, $ban->enforce_on_all_conns if $ban->type('conn_code');
    push @affected, $ban->enforce_on_all_users if $ban->type('user_code');
    return @affected;
}

# enforce the ban on a single connection
sub enforce_on_conn {
    my ($ban, $conn) = @_;

    # check that the connection matches
    my $conn_code = $ban->type('conn_code')   or return;
    my $action = $conn_code->($conn, $ban)    or return;

    # find the action conn code
    $action = M::Ban::get_ban_action($action) or return;
    my $enforce = $action->{conn_code}        or return;

    # do the action
    return $enforce->($conn, $ban);
}

# enforce the ban on all connections
sub enforce_on_all_conns {
    my $ban = shift;
    my @affected;
    foreach my $conn ($pool->connections) {
        my $affected = $ban->enforce_on_conn($conn);
        push @affected, $conn if $affected;
    }
    return @affected;
}

# enforce the ban on a single user
sub enforce_on_user {
    my ($ban, $user) = @_;
    return unless $user->is_local;

    # check that the user matches
    my $user_code = $ban->type('user_code')   or return;
    my $action = $user_code->($user, $ban)    or return;

    # find the action user code
    $action = M::Ban::get_ban_action($action) or return;
    my $enforce = $action->{user_code}        or return;

    # do the action
    return $enforce->($user, $ban);
}

# enforce the ban on all users
sub enforce_on_all_users {
    my $ban = shift;
    my @affected;
    foreach my $user ($pool->local_users) {
        my $affected = $ban->enforce_on_user($user);
        push @affected, $user if $affected;
    }
    return @affected;
}

##############
### TIMERS ###
################################################################################

# (re)activate the ban timer
sub activate_timer {
    my $ban = shift;
    $ban->deactivate_timer if $ban->{timer_active};
    $ban->{timer_active}++;
    return M::Ban::_activate_ban_timer($ban);
}

# deactivate the ban timer
sub deactivate_timer {
    my $ban = shift;
    delete $ban->{timer_active} or return;
    return M::Ban::_deactivate_ban_timer($ban);
}

#####################
### NOTIFICATIONS ###
################################################################################

# notify opers of a new ban
sub notify_new {
    my ($ban, $source) = @_;
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
    my ($ban, $source) = @_;
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
    my $type_name = shift->{type};
    if (defined(my $key = shift)) {
        my $type = $M::Ban::ban_types{$type_name} or return;
        return $type->{$key};
    }
    return $type_name;
}

# matchers
sub match       : lvalue { shift->{match}       }   # ban matcher
sub match_user  : lvalue { shift->{match_user}  }   # user field from matcher
sub match_host  : lvalue { shift->{match_host}  }   # host field from matcher

# timestamps and durations
sub added    : lvalue { shift->{added}      }   # timestamp when originally added
sub modified : lvalue { shift->{modified}   }   # timestamp when last modified
sub expires  : lvalue { shift->{expires}    }   # timestamp of expiration
sub lifetime : lvalue { shift->{lifetime}   }   # timestamp of end-of-life
sub duration : lvalue { shift->{duration}   }   # ban duration in seconds

# strings (all of these are optional and may be undef)
sub reason  : lvalue { shift->{reason}      }   # reason text
sub aserver : lvalue { shift->{aserver}     }   # server name where ban originated
sub auser   : lvalue { shift->{auser}       }   # nick!ident@host that added it

# set recent source.
sub set_recent_source {
    my ($ban, $source_obj) = @_;
    $ban->{_just_set_by} = $source_obj->id;
}

# object which just set or unset the ban.
sub recent_source {
    my $ban = shift;
    return $pool->lookup_user($ban->{_just_set_by}) ||
    $pool->lookup_server($ban->{_just_set_by});
}

# same as above except only return a user.
sub recent_user {
    my $ban = shift;
    return $pool->lookup_user($ban->{_just_set_by});
}

# the expire time relative to the modification time.
# this is usually the same as ->duration.
sub expires_duration {
    my $ban = shift;
    return $ban->modified - $ban->expires;
}

# the lifetime relative to the modification time.
sub lifetime_duration {
    my $ban = shift;
    return $ban->modified - $ban->lifetime;
}

# true if the ban has expired. it may still have lifetime though.
sub has_expired {
    my $ban = shift;
    return if !$ban->expires; # permanent
    return $ban->expires <= time;
}

# true if the ban's lifetime has expired.
sub has_expired_lifetime {
    my $ban = shift;
    return if !$ban->lifetime; # permanent
    return $ban->lifetime <= time;
}

# Human-readable stuff

# ban type
sub hr_ban_type {
    return shift->type('hname') || 'ban';
}

# expire time
sub hr_expires  {
    my $expires = shift->expires;
    return 'never' if !$expires;
    return pretty_time($expires);
}

# lifetime
sub hr_lifetime  {
    my $lifetime = shift->lifetime;
    return 'forever' if !$lifetime;
    return pretty_time($lifetime);
}

# added time
sub hr_added {
    return pretty_time(shift->added);
}

# modified time
sub hr_modified {
    return pretty_time(shift->modified);
}

# duration
sub hr_duration {
    my $duration = shift->duration;
    return 'permanent' if !$duration;
    return pretty_duration($duration);
}

# time remaining until expires
sub hr_remaining {
    return pretty_duration(shift->expires - time);
}

# time remaining until end-of-life
sub hr_remaining_lifetime {
    return pretty_duration(shift->lifetime - time);
}

# reason
sub hr_reason {
    my $reason = shift->{reason};
    return 'no reason' if !length $reason;
    return $reason;
}

$mod
