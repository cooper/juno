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
my $table;

sub init {
    $table = $M::Ban::table or return;
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
