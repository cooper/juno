# Copyright (c) 2013-14, Mitchell Cooper
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
    foreach my $mask ($user->full, $user->fullreal, $user->fullip) {
        return $event->{matched} = 1 if _match($mask, @list);
    }
    return;
}

sub oper_matcher {
    my ($event, $user, @list) = @_;
    return unless $user->is_mode('ircop');
    
    foreach my $item (@list) {
    
        # just check if opered.
        return $event->{matched} = 1 if $item eq '$o';
        
        # match a specific oper flag.
        next unless $item =~ m/^\$o:(.+)/;
        return $event->{matched} = 1 if $user->has_flag($1);
        
    }
    
    return;
}

$mod