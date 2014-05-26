# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "Account::Remote"
# @package:         "M::Account::Remote"
# @description:     "implements user accounts"
#
# @depends.modules: ['JELP']
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Account::Remote;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool, $db);

sub init {
    $db = $M::Account::db or return;

    # IRCd event for burst.
    $pool->on('server.send_burst' => \&send_burst,
        name  => 'account',
        after => 'core',
        with_evented_obj => 1
    );
    
    return 1;
}

#######################
### SERVER COMMANDS ###
#######################

sub send_burst {  
    my ($server, $fire, $time) = @_;
    print "SENDING BURST: $server, $fire, $time\n";
}

$mod