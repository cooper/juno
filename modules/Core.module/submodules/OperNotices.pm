# Copyright (c) 2014, Mitchell Cooper
package API::Module::Core::OperNotices;
 
use warnings;
use strict;
 
use utils qw(log2 conf v);

my %notices = (
    new_connection  => '%s (%d)',
    new_user        => '%s (%s@%s) [%s] on %s',
    new_server      => ''
);

our $mod = API::Module->new(
    name        => 'OperNotices',
    version     => $API::Module::Core::VERSION,
    description => 'the core set of oper notices',
    requires    => ['OperNotices'],
    initialize  => \&init
);
 
sub init {

    $mod->register_oper_notice(
        name    => $_,
        format  => $notices{$_}
    ) || return foreach keys %notices;
    
    undef %notices;
    return 1;
}

$mod
