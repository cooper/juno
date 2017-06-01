# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-Mac-mini.local
# Thu Jun 19 19:14:26 EDT 2014
# RegistrationCommands.pm
#
# @name:            'Core::RegistrationCommands'
# @package:         'M::Core::RegistrationCommands'
# @description:     'the core set of pre-registration commands'
#
# @depends.bases+   'RegistrationCommands', 'UserNumerics'
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

our %user_numerics = (
    ERR_INVALIDCAPCMD => [ 410, '%s :Invalid CAP subcommand' ]
);

sub init {

    $mod->register_registration_command(
        keys_values([qw/name code parameters after_reg/], $_)
    ) or return foreach (
    #
    # PARAMS = number of parameters
    # LATER  = true if the command should be handled even after registration
    #
    #   [ NAME      => \&sub            PARAMS  LATER
        [ PING      => sub { 1 },       undef           ],
        [ PONG      => sub { 1 },       undef           ],
        [ CAP       => \&rcmd_cap,      1,      1       ],
        [ NICK      => \&rcmd_nick,     1,              ],
        [ USER      => \&rcmd_user,     4,      1       ],
        [ QUIT      => \&rcmd_quit,     undef,          ],
        [ ERROR     => \&rcmd_error,    1,      1       ],
    );

    return 1;
}

####################
### CAPABILITIES ###
####################

# handle a CAP.
sub rcmd_cap {
    my ($conn, $event, @args) = @_;
    my $subcmd = lc shift @args;

    # handle the subcommand.
    if (my $code = __PACKAGE__->can("cap_$subcmd")) {
        return $code->($conn, $event, @args);
    }

    $conn->numeric(ERR_INVALIDCAPCMD => $subcmd);
    return;

}

# CAP LS: display the server's available caps.
sub cap_ls {
    my ($conn, $event, @args) = @_;

    # weed out disabled capabilities
    my @flags = grep { $pool->has_cap($_)->{enabled} }
        $pool->capabilities;

    # IRCv3 version
    if ($args[0] && $args[0] !~ m/\D/) {
        $conn->{cap_version} ||= $args[0];
    }

    # first LS - postpone registration.
    if (!$conn->{cap_suspend}) {
        $conn->{cap_suspend}++;
        $conn->reg_wait('cap');
    }

    # version >=302
    if (($conn->{cap_version} || 0) >= 302) {

        # cap-notify becomes enabled implicitly,
        # and when 302 is provided, it is sticky for this user
        $conn->add_cap('cap-notify');
        $conn->{cap_sticky}{'cap-notify'} = 1;

        # add values when present
        @flags = map {
            my $value = $pool->has_cap($_)->{value};
            length $value ? "$_=$value" : $_;
        } @flags;
    }

    $conn->early_reply(CAP => "LS :@flags");
}

# CAP LIST: display the client's active caps.
sub cap_list {
    my ($conn, $event, @args) = @_;
    my @flags = @{ $conn->{cap_flags} || [] };
    $conn->early_reply(CAP => "LIST :@flags");
}

# CAP REQ: client requests a capability.
sub cap_req {
    my ($conn, $event, @args) = @_;

    # postpone registration.
    if (!$conn->{cap_suspend}) {
        $conn->{cap_suspend}++;
        $conn->reg_wait('cap');
    }

    # handle each capability.
    my (@add, @remove, $nak);
    foreach my $item (map { split / / } @args) {
        $item = col($item);
        my ($m, $flag) = ($item =~ m/^([-]?)(.+)$/);
        next unless length $flag;

        # no such flag, or the capability is not enabled
        my $cap = $pool->has_cap($flag);
        if (!$cap || !$cap->{enabled}) {
            $nak++;
            last;
        }

        # in case the case is wrong
        $flag = $cap->{name};

        # requesting to remove it
        if ($m eq '-') {

            # attempted to remove a sticky flag
            if ($cap->{sticky} || $conn->{cap_sticky}{$flag}) {
                $nak++;
                last;
            }

            push @remove, $flag;
            next;
        }

        # adding
        push @add, $flag;
    }

    # sending NAK; don't change anything.
    my $cmd = 'ACK';
    if ($nak) {
        $cmd = 'NAK';
        @add = @remove = ();
    }

    $conn->add_cap(@add);
    $conn->remove_cap(@remove);
    $conn->early_reply(CAP => "$cmd :@args");
}

# CAP END: capability negotiation complete.
sub cap_end {
    my ($conn, $event) = @_;
    return if $conn->{type};
    $conn->reg_continue('cap') if delete $conn->{cap_suspend};
}

#########################
### USER REGISTRATION ###
#########################

sub rcmd_nick {
    my ($conn, $event, @args) = @_;
    my $nick = col(shift @args);

    # nick exists.
    if ($pool->nick_in_use($nick)) {
        $conn->numeric(ERR_NICKNAMEINUSE => $nick);
        return;
    }

    # invalid characters.
    if (!utils::validnick($nick)) {
        $conn->numeric(ERR_ERRONEUSNICKNAME => $nick);
        return;
    }

    # if a nick was already reserved, release it.
    my $old_nick = delete $conn->{nick};
    $pool->release_nick($old_nick) if defined $old_nick;

    # set the nick.
    $pool->reserve_nick($nick, $conn);
    $conn->{nick} = $nick;
    $conn->fire(reg_nick => $nick);
    $conn->reg_continue('id1');

}

sub rcmd_user {
    my ($conn, $event, @args) = @_;

    # already registered.
    if ($conn->{type}) {
        $conn->numeric('ERR_ALREADYREGISTRED');
        return;
    }

    $conn->{ident} = $args[0];
    $conn->{real}  = $args[3];
    $conn->fire(reg_user => @args[0,3]);
    $conn->reg_continue('id2');
}

###########################
### DISCONNECT MESSAGES ###
###########################

# not used for registered users.
sub rcmd_quit {
    my ($conn, $event, $arg) = @_;
    my $reason = $arg // 'leaving';
    $conn->done("~ $reason");
}

sub rcmd_error {
    my ($conn, $event, @args) = @_;
    my $reason = "Received ERROR: @args";
    $conn->done($reason);
}

$mod
