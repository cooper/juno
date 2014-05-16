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
        database table_exists create_table db_hashref
        db_arrayref db_single create_or_alter_table
    );
    
    # module unload event.
    $api->on('module.unload' => \&unload_module, with_evented_obj => 1) or return;
    
    return 1;
}

# create a database object.
sub database {
    print "@_\n";
    my ($mod, $event, $name) = @_;
    
    # use sqlite.
    if (conf('database', 'type') eq 'sqlite') {
        my $dbfile = "$::run_dir/db/$name.db";
        return DBI->connect("dbi:SQLite:dbname=$dbfile", '', '');
    }
    
    return;
}

# a table exists.
# FIXME: currently specific to SQLite.
sub table_exists {
    print "@_\n";
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

# select an arrayref.
sub db_arrayref {
    my ($mod, $event, $db, $query, @args) = @_;
    my $sth = $db->prepare($query);
    $sth->execute(@args) or return;
    return $sth->fetchrow_arrayref;
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
    my ($mod, $event, $db, $table_name, @columns) = @_;
    
    # table doesn't exist; create it.
    if (!table_exists($mod, $event, $db, $table_name)) {
        return create_table($mod, $db, $table_name, @columns);
    }
    
    # table exists. check if its coulumns are up-to-date.
    while (@columns) {
        my ($column, $type) = (shift @columns, shift @columns);
        # TODO: finished this.
        # maybe use PRAGMA table_info(table_name)
    }
    
    return 1;
}

$mod