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

# construct a ban object
sub construct {
    my ($class, %opts) = @_;
    bless \%opts, $class;
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
##########################

# $ban->disable
#
# changes the ban's modified time to the current time (plus one second) and then
# copies that to the expire time. this way the ban will be preserved in the
# database until its lifetime is over, but it will no longer be enforced.
#
# does NOT (and you should not) deactivate expiration timer.
# does NOT (and you should not) remove the ban from the database.
#
sub disable : method {
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

### ENFORCEMENT

sub activate_enforcement {

}

sub deactivate_enforcement {

}

### TIMERS

# (re)activate the ban timer
sub activate_timer {
    my $ban = shift;
    $ban->deactivate_timer if $ban->{timer_active};
    $ban->{timer_active}++;
    M::Ban::activate_ban_timer($ban);
}

# deactivate the ban timer
sub deactivate_timer {
    my $ban = shift;
    delete $ban->{timer_active} or return;
    M::Ban::deactivate_ban_timer($ban);
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

# getters
sub type    { shift->{type} }
sub id      { shift->{id}   }

$mod
