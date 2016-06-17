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
use utils qw(col keys_values);

our ($api, $mod, $pool, $me);

sub init {
    $mod->register_user_numeric(
        name   => 'ERR_INVALIDCAPCMD',
        number => 410,
        format => '%s :Invalid CAP subcommand'
    );

    $mod->register_registration_command(
        keys_values([qw/name code parameters after_reg/], $_)
    ) or return foreach (
    #
    # PARAMS = number of parameters
    # LATER  = true if the command should be handled even after registration
    #
    #   [ NAME      => \&sub            PARAMS  LATER
        [ PING      => \&rcmd_ping,     1,              ],
        [ PONG      => sub { 1 },       undef,  1       ],
        [ CAP       => \&rcmd_cap,      1,      1       ],
        [ NICK      => \&rcmd_nick,     1,              ],
        [ USER      => \&rcmd_user,     4,      1       ],
        [ QUIT      => \&rcmd_quit,     undef,          ],
        [ ERROR     => \&rcmd_error,    1,      1       ],
    );

    return 1;
}

#################
### PING PONG ###
#################

sub rcmd_ping {
    my ($connection, $event, $given) = @_;
    $connection->sendme("PONG $$me{name} :$given");
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
    foreach my $item (map { split / / } @args) {
        $item = col($item);
        my ($m, $flag) = ($item =~ m/^([-]?)(.+)$/);
        next unless length $flag;

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
    my ($connection, $event, @args) = @_;

    # already registered.
    if ($connection->{type}) {
        $connection->numeric('ERR_ALREADYREGISTRED');
        return;
    }

    $connection->{ident} = $args[0];
    $connection->{real}  = $args[3];
    $connection->fire_event(reg_user => @args[0,3]);
    $connection->reg_continue('id2');
}

###########################
### DISCONNECT MESSAGES ###
###########################

# not used for registered users.
sub rcmd_quit {
    my ($connection, $event, $arg) = @_;
    my $reason = $arg // 'leaving';
    $connection->done("~ $reason");
}

sub rcmd_error {
    my ($connection, $event, @args) = @_;
    my $reason = "Received ERROR: @args";
    $connection->done($reason);
}

$mod
