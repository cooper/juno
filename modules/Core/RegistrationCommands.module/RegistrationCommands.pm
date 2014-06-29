# Copyright (c) 2014, mitchellcooper
#
# Created on Mitchells-Mac-mini.local
# Thu Jun 19 19:14:26 EDT 2014
# RegistrationCommands.pm
#
# @name:            'Core::RegistrationCommands'
# @package:         'M::Core::RegistrationCommands'
# @description:     'the core set of pre-registration commands'
#
# @depends.modules: ['Base::RegistrationCommands', 'Base::UserNumerics']
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Core::RegistrationCommands;

use warnings;
use strict;
use 5.010;
use utils qw(col conf notice);

our ($api, $mod, $pool);

sub init {    
    $mod->register_user_numeric(
        name   => 'ERR_INVALIDCAPCMD',
        number => 410,
        format => '%s :Invalid CAP subcommand'
    );
    
    $mod->register_registration_command(
        name       => shift @$_, code      => shift @$_,
        parameters => shift @$_, with_data => shift @$_,
        after_reg  => shift @$_
    ) or return foreach (
    #
    # PARAMS = number of parameters
    # DATA   = true if include $data string
    # USER   = true if the command should be allowed for users after registration
    #
    #   [ NAME      => \&sub            PARAMS  DATA    USER 
        [ CAP       => \&rcmd_cap,      1,      undef,  1   ],
        [ NICK      => \&rcmd_nick,     1,      undef,      ],
        [ USER      => \&rcmd_user,     4,      1,          ],
        [ SERVER    => \&rcmd_server,   5,      undef,      ],
        [ PASS      => \&rcmd_pass,     1,      undef,      ],
        [ QUIT      => \&rcmd_quit,     1,      1,          ],
        [ ERROR     => \&rcmd_error,    1,      undef,  1   ],
    );
    
    return 1;
}

####################
### CAPABILITIES ###
####################

# handle a CAP.
sub rcmd_cap {
    my ($connection, $event, @args) = @_;
    my $subcmd = lc shift @args;
    
    # handle the subcommand.
    if (my $code = __PACKAGE__->can("cap_$subcmd")) {
        return $code->($connection, $event, @args);
    }
    
    $connection->numeric(ERR_INVALIDCAPCMD => $subcmd);
    return;
    
}

# CAP LS: display the server's available caps.
sub cap_ls {
    my ($connection, $event, @args) = @_;
    my @flags = $pool->capabilities;

    # first LS - postpone registration.
    if (!$connection->{cap_suspend}) {
        $connection->{cap_suspend} = 1;
        $connection->reg_wait('cap');
    }
    
    $connection->early_reply(CAP => "LS :@flags");
}

# CAP LIST: display the client's active caps.
sub cap_list {
    my ($connection, $event, @args) = @_;
    my @flags = @{ $connection->{cap_flags} || [] };
    $connection->early_reply(CAP => "LIST :@flags");
}

# CAP REQ: client requests a capability.
sub cap_req {
    my ($connection, $event, @args) = @_;
    
    # first LS - postpone registration.
    if (!$connection->{cap_suspend}) {
        $connection->{cap_suspend} = 1;
        $connection->reg_wait('cap');
    }
    
    # handle each capability.
    my (@add, @remove, $nak);
    foreach my $item (@args) {
        $item = col($item);
        my ($m, $flag) = ($item =~ m/^([-]?)(.+)$/);
                
        # requesting to remove it.
        if ($m eq '-') {
            push @remove, $flag;
        }
        
        # no such flag.
        if (!$pool->has_cap($flag)) {
            $nak = 1;
            last;
        }
        
        # it was removed.
        next if $m eq '-';
        
        # adding.
        push @add, $flag;
        
    }
    
    # sending NAK; don't change anything.
    my $cmd = 'ACK';
    if ($nak) {
        $cmd = 'NAK';
        @add = @remove = ();
    }
    
    $connection->add_cap(@add);
    $connection->remove_cap(@remove);
    $connection->early_reply(CAP => "$cmd :@args");
}

# CAP CLEAR: remove all active capabilities from a client.
sub cap_clear {
    my ($connection, $event, @args) = @_;
    my @flags = @{ $connection->{cap_flags} || [] };
    $connection->remove_cap(@flags);
    @flags = map { "-$_" } @flags;
    $connection->early_reply(CAP => "ACK :@flags");
}

# CAP END: capability negotiation complete.
sub cap_end {
    my ($connection, $event) = @_;
    return if $connection->{type};
    $connection->reg_continue('cap') if delete $connection->{cap_suspend};
}

#########################
### USER REGISTRATION ###
#########################

sub rcmd_nick {
    my ($connection, $event, @args) = @_;
    my $nick = col(shift @args);

    # nick exists.
    if ($pool->nick_in_use($nick)) {
        $connection->numeric(ERR_NICKNAMEINUSE => $nick);
        return;
    }

    # invalid characters.
    if (!utils::validnick($nick)) {
        $connection->numeric(ERR_ERRONEUSNICKNAME => $nick);
        return;
    }

    # if a nick was already reserved, release it.
    my $old_nick = delete $connection->{nick};
    $pool->release_nick($old_nick) if defined $old_nick;

    # set the nick.
    $pool->reserve_nick($nick, $connection);
    $connection->{nick} = $nick;
    $connection->fire_event(reg_nick => $nick);
    $connection->reg_continue('id1');
    
}

sub rcmd_user {
    my ($connection, $event, $data, @args) = @_;
    $connection->{ident} = $args[0];
    $connection->{real}  = col((split /\s+/, $data, 5)[4]);
    $connection->fire_event(reg_user => @$connection{ qw(ident real) });
    $connection->reg_continue('id2');
}

###########################
### SERVER REGISTRATION ###
###########################

sub rcmd_server {
    my ($connection, $event, @args) = @_;
    $connection->{$_}   = shift @args foreach qw[sid name proto ircd];
    $connection->{desc} = col(join ' ', @args);

    # if this was by our request (as in an autoconnect or /connect or something)
    # don't accept any server except the one we asked for.
    if (exists $connection->{want} && lc $connection->{want} ne lc $connection->{name}) {
        $connection->done('Unexpected server');
        return;
    }

    # find a matching server
    if (defined(my $addr = conf(['connect', $connection->{name}], 'address'))) {

        # FIXME: we need to use IP comparison functions
        # check for matching IPs
        if ($connection->{ip} ne $addr) {
            $connection->done('Invalid credentials');
            notice(connection_invalid => $connection->{ip}, 'IP does not match block');
            return;
        }

    }

    # no such server
    else {
        $connection->done('Invalid credentials');
        notice(connection_invalid => $connection->{ip}, 'No block for this server');
        return;
    }

    # made it.
    $connection->reg_continue('id1');
    return 1;
    
}

sub rcmd_pass {
    my ($connection, $event, @args) = @_;
    $connection->{pass} = shift @args;
    $connection->reg_continue('id2');
}

###########################
### DISCONNECT MESSAGES ###
###########################

sub rcmd_quit {
    my ($connection, $event, $data) = @_;
    my $reason = col((split /\s+/,  $data, 2)[1]);
    $connection->done("~ $reason");
}

sub rcmd_error {
    my ($connection, $event, @args) = @_;
    $connection->done("Received ERROR: @args");
}

$mod

