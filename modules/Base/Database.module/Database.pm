# Copyright (c) 2014, Mitchell Cooper
#
# @name:            "Base::Database"
# @version:         ircd->VERSION
# @package:         "M::Base::Database"
#
# @depends.modules: "API::Methods"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Base::Database;

use warnings;
use strict;
use 5.010;

use utils qw(conf);

our ($api, $mod);

sub init {
    
    # register methods.
    $mod->register_module_method($_) || return foreach qw(
        database table_exists create_table db_hashref db_hashrefs
        db_arrayref db_arrayrefs db_single create_or_alter_table
        db_insert_hash db_update_hash
    );
        
    return 1;
}

# create a database object.
sub database {
    my ($mod, $event, $name) = @_;
    
    # use sqlite.
    if (conf('database', 'type') eq 'sqlite') {
        my $dbfile = "$::run_dir/db/$name.db";
        return DBI->connect("dbi:SQLite:dbname=$dbfile", '', '');
    }
    
    return;
}

# a table exists.
sub table_exists {
    my ($mod, $event, $db, $table) = @_;
    my $sth = $db->prepare("SELECT name FROM sqlite_master WHERE type='table' AND name=?");
    $sth->execute($table);
    my @a = $sth->fetchrow_array;
    return scalar @a;
}

# create table.
sub create_table {
    my ($mod, $event, $db, $table_name, @columns) = @_;
    my @columns_left = @columns;
    my $query = "CREATE TABLE IF NOT EXISTS $table_name (";
    while (@columns_left) {
        my ($column, $type) = (shift @columns_left, shift @columns_left);
        $query .= $column.q(  ).$type;
        $query .= ',' if scalar @columns_left;
    }
    $query .= ')';
    return defined $db->do($query, undef, @columns);
}

# select a hashref.
sub db_hashref {
    my ($mod, $event, $db, $query, @args) = @_;
    my $sth = $db->prepare($query);
    $sth->execute(@args) or return;
    return $sth->fetchrow_hashref;
}

# select many hashrefs.
sub db_hashrefs {
    my ($mod, $event, $db, $query, @args) = @_;
    my $sth = $db->prepare($query);
    $sth->execute(@args) or return;
    my @a;
    while (my $next = $sth->fetchrow_hashref) {
        push @a, $next;
    }
    return \@a;
}

# select an arrayref.
sub db_arrayref {
    my ($mod, $event, $db, $query, @args) = @_;
    my $sth = $db->prepare($query);
    $sth->execute(@args) or return;
    return $sth->fetchrow_arrayref;
}

# select many arrayrefs.
sub db_arrayrefs {
    my ($mod, $event, $db, $query, @args) = @_;
    my $sth = $db->prepare($query);
    $sth->execute(@args) or return;
    my @a;
    while (my $next = $sth->fetchrow_arrayref) {
        push @a, $next;
    }
    return @a;
}

# select a single value.
sub db_single {
    my ($mod, $event, $db, $query, @args) = @_;
    my $sth = $db->prepare($query);
    $sth->execute(@args) or return;
    return $sth->fetchrow_arrayref->[0];
}

# create a table if necessary.
# add new columns if necessary.
sub create_or_alter_table {
    my ($mod, $event, $db, $table_name, %columns) = @_;
    
    # table doesn't exist; create it.
    if (!table_exists($mod, $event, $db, $table_name)) {
        return create_table($mod, $event, $db, $table_name, %columns);
    }
    
    # table exists. check if its coulumns are up-to-date.
    my $sth = $db->prepare("PRAGMA table_info($table_name)"); $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        delete $columns{ $row->{name} };
    }
    foreach my $name (keys %columns) {
        my $type = $columns{$name};
        $db->do("ALTER TABLE $table_name ADD COLUMN $name $type");
    }
    
    return 1;
}

# insert from a hash.
sub db_insert_hash {
    my ($mod, $event, $db, $table_name, %hash) = @_;
    my @keys   = keys %hash;
    my @values = @hash{@keys};
    
    my $str    = "INSERT INTO $table_name(";
       $str   .= "$_, " foreach @keys;  substr($str, -2, 2) = '';
    
    # add values.
    $str .= ') VALUES (';
    $str .= '?, ' x @keys;              substr($str, -2, 2) = '';
    $str .= ')';

    # insert.
    $db->do($str, undef, @values);
    
}

# update from a hash.
sub db_update_hash {
    my ($mod, $event, $db, $table_name, $where_hash, $update_hash) = @_;
    my @u_keys   = keys %$update_hash;
    my @u_values = @$update_hash{@u_keys};
    my @w_keys   = keys %$where_hash;
    my @w_values = @$where_hash{@w_keys};
    
    my $str  = "UPDATE $table_name SET ";
       $str .= "$_ = ?, " foreach @u_keys;
    substr($str, -2, 2) = '';
    
    # add values.
    $str .= ' WHERE ';
    $str .= "$_ = ? AND " foreach @w_keys;
    substr($str, -5, 5) = '';

    # insert.
    $db->do($str, undef, @u_values, @w_values);
    
}

$mod