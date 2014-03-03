# Copyright (c) 2012-14, Mitchell Cooper
package API::Module::Account;

use warnings;
use strict;
use 5.010;

our $db;

our $mod = API::Module->new(
    name        => 'Account',
    version     => '0.1',
    description => '',
    requires    => ['Database'],
    initialize  => \&init
);
 
sub init {
    $db = $mod->database('account') or return;
    
    # create or update the table if necessary.
    $mod->create_or_alter_table($db, 'accounts',
        id       => 'INT',          # numerical account ID
        name     => 'VARCHAR(50)',  # account name
        password => 'VARCHAR(512)', # (hopefully encrypted) account password
                                    #     255 is max varchar size on mysql<5.0.3
        created  => 'UNSIGNED INT', # UNIX time of account creation
                                    #     in SQLite, the max size is very large...
                                    #     in mysql and others, not so much.
        cserver  => 'VARCHAR(512)', # server name on which the account was registered
        csid     => 'INT(4)',       # SID of the server where registered
        updated  => 'UNSIGNED INT', # UNIX time of last account update
        userver  => 'VARCHAR(512)', # server name on which the account was last updated
        usid     => 'INT(4)'        # SID of the server where last updated
    ) or return;
    
    return 1;
}

$mod
