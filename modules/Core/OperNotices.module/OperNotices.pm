# Copyright (c) 2009-16, Mitchell Cooper
#
# @name:            "Core::OperNotices"
# @version:         ircd->VERSION
# @package:         "M::Core::OperNotices"
# @description:     "the core set of oper notices"
#
# @depends.modules: "Base::OperNotices"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Core::OperNotices;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $me);

our %oper_notices = (

    # connections
    new_connection          => '%s (%d)',
    connection_terminated   => '%s (%s): %s',
    connection_invalid      => '%s: %s',

    # users
    new_user                => '%s (%s@%s) [%s] on %s',
    user_quit               => '%s (%s@%s) [%s] from %s (%s)',
    user_opered             => '%s (%s@%s) gained flags on %s: %s',
    user_deopered           => '%s (%s@%s) is no longer an IRC operator',
    user_killed             => '%s (%s@%s) killed by %s (%s)',
    user_nick_change        => '%s (%s@%s) is now known as %s',
    user_join               => '%s (%s@%s) joined %s',
    user_part               => '%s (%s@%s) parted %s (%s)',
    user_part_all           => '%s (%s@%s) parted all channels: %s',
    user_kick               => '%s (%s@%s) was kicked from %s by %s (%s)',
    user_mask_change        => '%s switched from (%s@%s) to (%s@%s)',
    user_identifier_taken   => '%s introduced %s (%s@%s) with UID %s, which is already taken by %s (%s@%s)',
    user_saved              => '%s (%s@%s) was spared in the midst of a nick collision (was %s)',
    user_logged_in          => '%s (%s@%s) is now logged in as %s',
    user_logged_out         => '%s (%s@%s) logged out (was %s)',

    # servers
    new_server              => '%s (%d) ircd %s, proto %s [%s] parent: %s',
    server_closing          => 'Received SQUIT from %s (%s); dropping link (%s)',
    server_quit             => '%s (%d) quit from parent %s (%s)',
    server_burst            => '%s (%s) is bursting information',
    server_endburst         => '%s (%s) finished burst, %d seconds elapsed',
    connect                 => '%s (%s@%s) issued CONNECT for %s to %s',
    connect_attempt         => '%s (%s) on port %d (Attempt %d)',
    connect_cancel          => '%s (%s@%s) canceled auto connect for %s',
    connect_fail            => 'Can\'t connect to %s: %s',
    connect_success         => 'Connection established to %s',
    squit                   => '%s (%s@%s) issued SQUIT for %s from %s',
    server_reintroduced     => '%s attempted to introduce %s which already exists',
    server_identifier_taken => '%s attempted to introduce %s as SID %d, which is already taken by %s',
    server_protocol_warning => '%s (%s) %s',
    server_protocol_error   => '%s (%s) %s; dropping link',

    # modes
    user_mode_unknown       => 'Attempted to set %s, but this mode is not defined on %s (%s); ignored',
    channel_mode_unknown    => 'Attempted to set %s on %s, but this mode is not defined on %s (%s); ignored',

    # miscellaneous
    perl_warning            => '%s',
    exception               => '%s',
    rehash                  => '%s (%s@%s) is rehashing the server',
    rehash_fail             => 'Configuration error: %s',
    rehash_success          => 'Server configuration reloaded successfully'

);

$mod
