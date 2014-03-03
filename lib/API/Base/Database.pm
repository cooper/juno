# Copyright (c) 2014, Mitchell Cooper
package API::Base::Database;

use warnings;
use strict;
use 5.010;

use utils qw(log2 conf);

sub database {
    my ($mod, $name) = @_;
    
    # use sqlite.
    if (conf('database', 'type') eq 'sqlite') {
        my $dbfile = "$main::run_dir/db/$name.db";
        return DBI->connect("dbi:SQLite:dbname=$dbfile", '', '');
    }
    
    return;
}

sub _unload {
    my ($class, $mod) = @_;
    return 1;
}

1
