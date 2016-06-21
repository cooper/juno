# Copyright (c) 2009-14, Mitchell Cooper
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

    new_connection          => '%s (%d)',
    connection_terminated   => '%s (%s): %s',
    connection_invalid      => '%s: %s',

    new_user                => '%s (%s@%s) [%s] on %s',
    user_quit               => '%s (%s@%s) [%s] from %s (%s)',
    user_opered             => '%s (%s@%s) gained flags on %s: %s',
    user_killed             => '%s (%s@%s) killed by %s (%s)',
    user_nick_change        => '%s (%s@%s) is now known as %s',
    user_join               => '%s (%s@%s) joined %s',
    user_part               => '%s (%s@%s) parted %s (%s)',
    user_mask_change        => '%s switched from (%s@%s) to (%s@%s)',
    user_identifier_taken   => '%s introduced %s (%s@%s) with UID %s, which is already taken by %s (%s@%s)',
    user_saved              => '%s (%s@%s) was spared in the midst of a nick collision (was %s)',

    new_server              => '%s (%d) ircd %s, proto %s [%s] parent: %s',
    server_quit             => '%s (%d) parent %s (%s)',
    server_burst            => '%s (%s) is bursting information',
    server_endburst         => '%s (%s) finished burst, %d seconds elapsed',
    server_connect          => '%s (%s) on port %d (Attempt %d)',
    server_connect_cancel   => '%s (%s@%s) canceled auto connect for %s',
    server_connect_fail     => 'Can\'t connect to %s: %s',
    server_connect_success  => 'Connection established to %s',
    server_reintroduced     => '%s attempted to introduce %s which already exists',
    server_identifier_taken => '%s attempted to introduce %s as SID %d, which is already taken by %s',

    perl_warning            => '%s',
    exception               => '%s',
    server_warning          => '%s',
    rehash                  => '%s (%s@%s) is rehashing the server',
    rehash_fail             => 'Configuration error: %s',
    rehash_success          => 'Server configuration reloaded successfully'

);

$mod
