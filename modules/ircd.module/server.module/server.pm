
# Copyright (c) 2009-16, Mitchell Cooper
#
# @name:            "ircd::server"
# @package:         "server"
# @description:     "represents an IRC server"
# @version:         ircd->VERSION
# @no_bless:        1
# @preserve_sym:    1
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package server;

use warnings;
use strict;
use feature 'switch';
use parent 'Evented::Object';

use modes;
use utils qw(col v conf notice);
use Scalar::Util qw(looks_like_number blessed);

our ($api, $mod, $me, $pool);

sub init {
    $mod->load_submodule('protocol') or return;
    $mod->load_submodule('linkage')  or return;
    return 1;
}

sub new {
    my ($class, %opts) = @_;

    # although currently unimportant, it is noteworthy that
    # ->new() is never called for the local server. it is
    # constructed manually before the server module is loaded.

    return bless {
        umodes   => {},
        cmodes   => {},
        users    => [],
        children => [],
        # if anything is added here, add to ircd.pm also.
        %opts
    }, $class;
}

# handle a server quit.
# does not close a connection; use $server->conn->done() for that.
#
# $reason = the actual reason to log and show to opers
# $why = the reason to send in user quit messages
# $quiet = do not send out notices
#
sub quit {
    my ($server, $reason, $why, $quiet) = @_;
    $why //= "$$server{parent}{name} $$server{name}";

    notice(server_quit =>
        $server->notice_info,
        $server->{parent}->notice_info,
        $reason
    ) unless $quiet;

    # all children must be disposed of.
    foreach my $serv ($server->children) {
        next if $serv == $server;
        $serv->quit('parent server has disconnected', $why);
    }

    # delete all of the server's users.
    my @users = $server->all_users;
    foreach my $user (@users) {
        $user->quit($why, 1);
    }

    $pool->delete_server($server) if $server->{pool};
    $server->delete_all_events();
    return 1;
}

# associate a letter with a umode name.
sub add_umode {
    my ($server, $name, $mode) = @_;
    $server->{umodes}{$name} = { letter => $mode };
    L("$$server{name} registered $mode:$name");
    return 1;
}

sub remove_umode {
    my ($server, $name) = @_;
    my $u = delete $server->{umodes}{$name} or return;
    L("$$server{name} deleted $$u{letter}:$name");
    return 1;
}

# umode letter to name.
sub umode_name {
    my ($server, $mode) = @_;
    foreach my $name (keys %{ $server->{umodes} }) {
        my $letter = $server->{umodes}{$name}{letter};
        next unless length $letter;
        return $name if $mode eq $letter;
    }
    return;
}

# umode name to letter.
sub umode_letter {
    my ($server, $name) = @_;
    return $server->{umodes}{$name}{letter};
}

# convert umodes
sub convert_umode_string {
    my ($server1, $server2, $mode_str) = @_;

    my $string = '+';                               # new (+/-)modes
    my $modes  = (split /\s+/, $mode_str, 2)[0];    # old (+/-)modes
    my $state  = 1;                                 # current state
    my $since_state;                                # changes since state change

    foreach my $letter (split //, $modes) {

        # state change.
        if ($letter eq '+' || $letter eq '-') {
            chop $string if !$since_state;
            my $new  = $letter eq '+';
            $string .= $letter if !length $string || $state != $new;
            $state   = $new;
            undef $since_state;
            next;
        }

        # translate the letter.
        my $name = $server1->umode_name($letter) or next;
        my $new  = $server2->umode_letter($name);

        # the second server does not know this mode.
        next if !length $new;

        $string .= $new;
        $since_state++;
    }

    # if we have nothing but a sign, return +.
    if (length $string == 1) {
        L("$mode_str ($$server1{name}) -> nothing at all ($$server2{name})");
        return '+';
    }

    L("$mode_str ($$server1{name}) -> $string ($$server2{name})");
    return $string;
}

# associate a letter with a cmode name.
sub add_cmode {
    my ($server, $name, $mode, $type) = @_;
    $server->{cmodes}{$name} = {
        letter => $mode,
        type   => $type
    };
    L("$$server{name} registered $mode:$name");
    return 1;
}

sub remove_cmode {
    my ($server, $name) = @_;
    my $c = delete $server->{cmodes}{$name} or return;
    L("$$server{name} deleted $$c{letter}:$name");
    return 1;
}

# cmode letter to name.
sub cmode_name {
    my ($server, $mode) = @_;
    return unless defined $mode;
    foreach my $name (keys %{ $server->{cmodes} }) {
        next unless defined $server->{cmodes}{$name}{letter};
        return $name if $mode eq $server->{cmodes}{$name}{letter};
    }
    return;
}

# cmode name to letter.
sub cmode_letter {
    my ($server, $name) = @_;
    return unless defined $name;
    return $server->{cmodes}{$name}{letter};
}

# get cmode type.
sub cmode_type {
    my ($server, $name) = @_;
    return -1 if !defined $name;
    return $server->{cmodes}{$name}{type} // -1;
}

# convert cmodes and their parameters
sub convert_cmode_string {
    my ($server1, $server2, $mode_str, $over_protocol) = @_;
    return modes->new_from_string(
        $server1,
        $mode_str,
        $over_protocol
    )->to_string($server2, $over_protocol);
}

# true if the mode takes a parameter in this state.
#
# returns:
# undef = unknown
#     0 = does not take parameter
#     1 = yes, takes parameter
#     2 = take parameter if present but still valid if not
#
sub cmode_takes_parameter {
    my ($server, $name, $state) = @_;
    my %params  = (
        MODE_NORMAL,    0,               # normal - never
        MODE_PARAM,     1,               # parameter - always
        MODE_PSET,      $state,          # parameter_set - when setting only
        MODE_LIST,      2,               # list mode - valid without
        MODE_STATUS,    1,               # status mode - always
        MODE_KEY,       $state ? 1 : 2   # key mode - always when setting,
                                            #     only if present when unsetting
    );
    return $params{ $server->{cmodes}{$name}{type} || -1 };
}

sub is_local { shift == $me }

# sub DESTROY {
#     my $server = shift;
#     L("$server destroyed");
# }

sub children {
    my $server = shift;
    my @a;
    foreach my $serv ($pool->servers) {
        next unless $serv->{parent};
        next if $serv == $server;
        push @a, $serv if $serv->{parent} == $server;
    }
    return @a;
}

# hops to server.
sub hops_to {
    my ($server1, $server2) = @_;
    my $hops = 0;
    return $hops if $server1 == $server2;
    return -1    if $server2->{parent} == $server2;
    until (!$server2 || $server2 == $server1) {
        $hops++;
        $server2 = $server2->{parent};
    }
    return $hops;
}

sub uid_to_user {
    my ($server, $uid) = @_;
    return $server->{uid_to_user}($uid) if $server->{uid_to_user};
    return $pool->lookup_user($uid);
}

sub user_to_uid {
    my ($server, $user) = @_;
    return $server->{user_to_uid}($user) if $server->{user_to_uid};
    return $user->{uid};
}

sub sid_to_server {
    my ($server, $sid) = @_;
    return $server->{sid_to_server}($sid) if $server->{sid_to_server};
    return $pool->lookup_server($sid);
}

sub server_to_sid {
    my ($server, $serv) = @_;
    return $server->{server_to_sid}($serv) if $server->{server_to_sid};
    return $serv->{sid};
}

sub set_functions {
    my ($server, %functions) = @_;
    @$server{ keys %functions } = values %functions;
}

# shortcuts

sub id       { shift->{sid}         }
sub full     { shift->{name}        }
sub name     { shift->{name}        }
sub conn     { shift->{conn}        }
sub user     { undef                }
sub users    { @{ shift->{users} }  }
sub server   { shift                }
sub parent   { shift->{parent}      }

sub all_users        {   @{ shift->{users} }                    }
sub real_users       {   grep  { !$_->{fake}                    } shift->all_users  }
sub all_local_users  {   grep  { $_->is_local                   } shift->all_users  }
sub real_local_users {   grep  { $_->is_local && !$_->{fake}    } shift->all_users  }
sub global_users     {   grep  { !$_->{fake_local}              } shift->all_users  }

############
### MINE ###
############

# handle incoming server data.
sub handle {}

# send burst to a connected server.
sub send_burst {
    my $server = shift;
    return if $server->{i_sent_burst};

    my $time = time;
    $server->{i_am_burst} = $time;

    # fire burst events.
    my $proto = $server->{link_type};
    $server->prepare(
        [ send_burst            => $time ],
        [ "send_${proto}_burst" => $time ]
    )->fire;

    delete $server->{i_am_burst};
    $server->{i_sent_burst} = time;
    return 1;
}

sub end_burst {
    my $server  = shift;
    my $time    = delete $server->{is_burst};
    my $elapsed = time - $time;
    $server->{sent_burst} = time;

    notice(server_endburst => $server->notice_info, $elapsed);

    # fire end burst events.
    my $proto = $server->{link_type};
    $server->prepare(
        [ end_burst            => $time ],
        [ "end_${proto}_burst" => $time ]
    )->fire;

    return 1;
}

# send data to all of my children.
# this actually sends it to all connected servers.
# it is only intended to be called with this server object.
sub send_children {
    my $ignore = shift;

    foreach my $server ($pool->servers) {

        # don't send to ignored
        if (defined $ignore && $server == $ignore) {
            next;
        }

        # don't try to send to non-locals
        next unless exists $server->{conn};

        # don't send to servers who haven't received my burst.
        next unless $server->{i_sent_burst};

        $server->send(@_);
    }

    return 1
}

sub sendfrom_children {
    my ($ignore, $from) = (shift, shift);
    send_children($ignore, map { ":$from $_" } @_);
    return 1;
}

# send data to MY servers.
sub send {
    my $server = shift;
    if (!$server->{conn}) {
        my $sub = (caller 1)[3];
        L("can't send data to unconnected server $$server{name}!");
        return;
    }
    $server->{conn}->send(@_);
}

# send data to a server from THIS server.
sub sendme {
    my $server = shift;
    $server->sendfrom($me->{sid}, @_);
}

# send data from a UID or SID.
sub sendfrom {
    my ($server, $from) = (shift, shift);
    $server->send(map { ":$from $_" } @_);
}

# convenient for $server->fire_command
sub fire_command {
    my $server = shift;
    return $pool->fire_command($server, @_);
}

sub notice_info {
    my $server = shift;
    return "$$server{name} ($$server{sid})";
}

# IRCd support

sub ircd_opt {
    my ($server, $key) = @_;
    my $ircd = $server->{ircd_name} or return;
    my %ircd = server::protocol::ircd_support_hash($ircd);
    return $ircd{$key};
}

# CAP shortcuts.
*has_cap = *connection::has_cap;
*add_cap = *connection::add_cap;
*remove_cap = *connection::remove_cap;

$mod
