# Copyright (c) 2014, mitchellcooper
#
# Created on Mitchells-Mac-mini.local
# Fri Aug  8 22:47:08 EDT 2014
# Incoming.pm
#
# @name:            'TS6::Incoming'
# @package:         'M::TS6::Incoming'
# @description:     'basic set of TS6 command handlers'
#
# @depends.modules: 'TS6::Base'
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::TS6::Incoming;

use warnings;
use strict;
use 5.010;

use utils qw(uid_from_ts6);

our ($api, $mod, $pool);

our %ts6_incoming_commands = (
    EUID => {
                   # :sid EUID      nick hopcount nick_ts umodes ident cloak ip  uid host act :realname
        params  => '-source(server) *    *        ts      *      *     *     *   *   *    *   :rest',
        code    => \&uid,
        forward => 1
    },
);

# EUID
#
# charybdis TS6
#
# capab         EUID
# source:       server
# parameters:   nickname, hopcount, nickTS, umodes, username, visible hostname,
#               IP address, UID, real hostname, account name, gecos
# propagation:  broadcast
#
# ts6-protocol.txt:315
#
sub euid {
    my ($server, $event, $source_serv, @rest) = @_;
    my %u = (
        source   => $server->{sid},     # SID of the server who told us about him
        location => $server             # nearest server we have a physical link to
    );
    $u{$_} = shift @rest foreach qw(
        nick ts6_dummy nick_time umodes ident
        cloak ip ts6_uid host account_name real
    );
    my ($mode_str, undef) = (delete $u{modes}, delete $u{ts6_dummy});
    
    $u{time} = $u{nick_time};                   # for compatibility
    $u{host} = $u{cloak} if $u{host} eq '*';    # host equal to visible
    $u{uid}  = uid_from_ts6($u{ts6_uid});       # convert to juno UID

    # uid collision?
    if ($pool->lookup_user($u{uid})) {
        # can't tolerate this.
        # the server is bugged/mentally unstable.
        L("duplicate UID $u{uid}; dropping $$server{name}");
        $server->conn->done('UID collision') if $server->conn;
    }

    # nick collision!
    my $used = $pool->lookup_user_nick($u{nick});
    if ($used) {
        # TODO: this.
        return;
    }

    # create a new user with the given modes.
    my $user = $pool->new_user(%u);
    $user->handle_mode_string($mode_str, 1);

    return 1;

}

$mod
