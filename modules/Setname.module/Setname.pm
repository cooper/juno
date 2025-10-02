# Copyright (c) 2025, Mitchell Cooper
#
# @name:            'Setname'
# @package:         'M::Setname'
# @description:     'IRCv3 setname extension'
#
# @depends.bases+   'UserCommands'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Setname;

use warnings;
use strict;
use 5.010;

use utils qw(broadcast);

our ($api, $mod, $pool, $me);

sub init {

    # register SETNAME user command.
    $mod->register_user_command_new(
        name        => 'SETNAME',
        code        => \&setname,
        description => 'change realname (gecos)',
        parameters  => ':'
    ) or return;

    # register capability.
    $mod->register_capability(
        name => 'setname'
    ) or return;

    return 1;
}

sub setname {
    my ($user, $event, $new_real) = @_;

    # same as current realname.
    return if $user->{real} eq $new_real;

    # update the realname.
    my $old_real = $user->{real};
    $user->{real} = $new_real;

    # send SETNAME to users with the capability.
    $user->send_to_channels(
        "SETNAME :$new_real",
        cap     => 'setname',
        myself  => 1
    );

    # notify the server.
    broadcast(setname => $user, $new_real);

    return 1;
}

$mod
