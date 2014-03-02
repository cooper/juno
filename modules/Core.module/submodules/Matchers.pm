# Copyright (c) 2013, Mitchell Cooper
package API::Module::Core::Matchers;
 
use warnings;
use strict;
 
use utils qw(log2 _match);

our $mod = API::Module->new(
    name        => 'Matchers',
    version     => $API::Module::Core::VERSION,
    description => 'the core set of mask matchers',
    requires    => ['Matching'],
    initialize  => \&init
);
 
sub init {

    $mod->register_matcher(
        name => 'standard',
        code => \&standard_matcher
    ) or return;
    
    $mod->register_matcher(
        name => 'oper',
        code => \&oper_matcher
    ) or return;
    
    return 1;
}

sub standard_matcher {
    my ($event, $user, @list) = @_;
    foreach my $mask ($user->full, $user->fullcloak, $user->fullip) {
        return $event->{matched} = 1 if _match($mask, @list);
    }
    return;
}

sub oper_matcher {
    my ($event, $user, @list) = @_;
    grep { $_ eq '$o' } @list or return;
    return $event->{matched} = 1 if $user->is_mode('ircop');
    return;
}

$mod