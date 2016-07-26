# TS6 support

This is a summary of juno's
[implementation](https://github.com/cooper/juno/tree/master/modules/TS6) of the
TS6 protocol. This protocol module can be used to link juno with a
[variety](#supported-software) of IRC servers and other software. While it is
also possible to link juno servers via TS6, the native Extensible Linking
Protocol is strongly preferred for such.

## Listening for TS6

The current implementation requires dedicated ports for TS6 links. This is
because it is far too complicated to try to distinguish between different server
protocols, particularly when each is provided in the form of an optional module.

This is only necessary if you intend to accept connections from TS6 servers. If
juno will be initiating the connection (such as with CONNECT or autoconnect),
you do not have to listen for TS6.

In your `listen` blocks, add `ts6port` and/or `ts6sslport` options. Values are
the same as `port`; lists and ranges are accepted.

## Server capabilities

juno supports server capability negotiation. However, it falls back to older
commands when the new ones are unavailable, retaining support for ancient
servers.

### Required

juno will terminate a connection during registration if it does not receive a
`CAPAB` message or if any of these tokens are missing from it:

* `ENCAP` - enhanced command routing
* `QS` - quit storm
* `EX` - ban exceptions (+e)
* `IE` - invite exceptions (+I)

### Supported

In addition to the above, juno supports the following capabilities:

* `EUID` - extended user introduction
* `TB` - topic burst with added information
* `EOB` - end of burst token
* `SERVICES` - ratbox services extensions (umode +S and cmode +r)
* `SAVE` - resolution of nick collisions without killing
* `SAVETS_100` - silences warnings about nickTS inconsistency (ratbox)
* `RSFNC` - force nick change, used for services nick enforcement
* `BAN` - charybdis-style global ban propagation
  (with [Ban](https://github.com/cooper/juno/tree/master/modules/Ban))
* `KLN` - remote K-Lines
  (with [Ban](https://github.com/cooper/juno/tree/master/modules/Ban))
* `UKLN` - remote removal of K-Lines
  (with [Ban](https://github.com/cooper/juno/tree/master/modules/Ban))

## Mode definitions and IRCd-specific options

In juno's native linking protocol, user and channel modes are negotiated during
the initial burst. Because this is not possible in TS6, mode definitions for
various TS-based IRCds were added to the
[default configuration](https://github.com/cooper/juno/blob/master/etc/default.conf).
It is also possible to add additional IRCd support through the main
configuration. See issue [#110](https://github.com/cooper/juno/issues/110) for
info about config-based IRCd support.

```
[ ircd: ratbox ]
    nicklen = 16

[ ircd_cmodes: ratbox ]
    ban = [3, 'b']
    except = [3, 'e']

[ ircd: charybdis ]
    extends = 'ratbox'
    nicklen  = 32

[ ircd_cmodes: charybdis ]
    quiet = [3, 'q']
```

## Mode translation

juno deals with all modes internally by name, never by letter. This makes it
easy to apply modes from different server perspectives and then forward them
with differing letters and parameters across the network.

It works by extracting named modes from a string in a certain perspective,
applying them, and then forwarding newly-constructed mode strings in other
perspectives. Low-level mode handling also automatically converts UIDs and
other variable parameters when necessary.
See issue [#101](https://github.com/cooper/juno/issues/101) for more info.

```perl

# Given a TS6 mode string and a TS6 server
my $ts6_server;
my $some_ts6_mode_string = '+qo 000AAAABG 000AAAABG';

# get the modes by their names in an arrayref
my $modes = $ts6_server->cmodes_from_string($some_ts6_mode_string);

# commit the modes without translating the mode string!
$channel->do_modes_local($source, $modes, 1, 1, 1);
```

Modes which are missing on a destination server are simply omitted from the
resulting messages. juno used to map status modes like +q (owner) and +a (admin)
to +o (op), but in issue [#7](https://github.com/cooper/juno/issues/7), we
decided that this was not necessary and would actually result in channel
security issues (such as users protected by +q or +a being kicked by users with
only +o on a TS-based server). Both external services packages and juno's
built-in channel access feature set +o along with any higher status mode.

```
[TS6::Outgoing] convert_cmode_string(): +qo 0a 0a (k.notroll.net) -> +o 000AAAAAA (charybdis.notroll.net)
```

## SID, UID conversion

juno's internal SIDs are 0-9 and UIDs are a-z. In TS6, SIDs can contain letters,
and the system used for numbering UIDs differs from juno. While juno IDs have
variable length, TS-based servers always use three characters for SIDs and nine
characters for UIDs.

```perl
sub obj_from_ts6 {
    my $id = shift;
    if (length $id == 3) { return $pool->lookup_server(sid_from_ts6($id)) }
    if (length $id == 9) { return $pool->lookup_user  (uid_from_ts6($id)) }
    return;
}
```

TS6 SIDs containing letters are transformed into nine-digit numeric strings
based on the corresponding ASCII values. SIDs containing only digits are
unchanged. In the other direction, juno SIDs which are less than three digits in
length are prefixed with one or two zeros.

The downfall is that juno SIDs with more than three digits are not supported
when using TS6. This should be okay though, as long as your network includes
less than one thousand servers running juno.

```perl
sub sid_from_ts6 {
    my $sid = shift;
    if ($sid =~ m/[A-Z]/) {
        return join('', map { sprintf '%03d', ord } split //, $sid) + 0;
    }
    return $sid + 0;
}
```

Both juno and TS-based servers construct UIDs by mending the SID for the server
the user is on with a string of characters that is associated with an integer.
This makes the conversion easy: simply determine which Nth TS6 ID it is and spit
out the Nth juno ID and vice versa.

```perl
sub uid_from_ts6 {
    my $uid = shift;
    my ($sid, $id) = ($uid =~ m/^([0-9A-Z]{3})([0-9A-Z]{6})$/);
    return sid_from_ts6($sid).uid_u_from_ts6($id);
}
```

See
[the code](https://github.com/cooper/juno/blob/master/modules/TS6/Utils.module/Utils.pm)
for more info.

## K-Lines, D-Lines

[Ban::TS](https://github.com/cooper/juno/blob/master/modules/Ban/Ban.module/TS6.module)
provides the TS6 server ban implementation. It is loaded automatically when TS6
and Ban are both loaded.

juno bans are global, but on TS-based servers, bans are generally local-only
(unless using services, cluster, or some other extension). In order to keep a
mixed juno/TS6 network secure, juno will do its best to globally propagate all
bans.

Bans are sent to TS6 servers on burst. Because certain ban commands only support
a user source, a ban agent bot may be introduced to set the bans and then exit.

The duration sent to TS6 servers is variable based on the difference between the
expiration time and the duration, since we cannot propagate an expiration time.
The TS6 server will ignore any bans which already exist for the given mask,
which is perfect for our purposes. An exception to this is the newer BAN command
which does allow propagation of expiry times and is used when available.

Ban::TS6 uses the charybdis-style BAN command when possible. Alternatively KLINE
and INCLINE may be used when the KLN and UKLN capabilities are available.
Otherwise, it uses ENCAP KLINE and ENCAP UNKLINE. DLINEs always use ENCAP and
therefore always require a ban agent during burst.

Note that, because some charybdis server bans are local-only, the TS6 server may
not burst its own bans (such as D-Lines, or even K-Lines if the BAN capability
is not available). However, ban commands are handled such that AKILLs (which
have target `*`) will be effective across an entire mixed charybdis/juno
network. AKILL is considered the most reliable way to ensure global ban propagation.

See issue [#32](https://github.com/cooper/juno/issues/32)
for more information about the TS6 ban implementation.

## SASL

juno supports SASL authentication over TS6 using the ENCAP SASL mechanism. This
is useful for authenticating to services packages linked via TS6. See issue
[#9](https://github.com/cooper/juno/issues/9) for details.

# Supported software

This is a list of IRC servers and packages that have been tested and seem to
work well with juno TS6.

## Services

### atheme

Provides nickname and channel registration, plus a lot of other stuff.

Specify the `ircd = 'atheme'` option in the `connect` block.

Compile and install the
[provided protocol module](https://github.com/cooper/juno/blob/master/extra/atheme/juno.c).

Be sure to configure atheme to load modules that are associated with your status
mode configuration. On the default +qaohv configuration, you will want
`chanserv/owner`, `chanserv/protect`, and `chanserv/halfop`.

The provided protocol module supports +qaohv, so if you want to disable certain
statuses then you can use atheme's protocol mixin modules.

A known bug is that the QUIET command provided by `chanserv/quiet` does not work
on juno due to it having a hard-coded letter `q` for quiets.

### PyLink

A services framework which features a multi-network IRC relay.

Specify the `ircd = 'elemental'` option in the `connect` block. PyLink works
with juno by pretending to be elemental-ircd. It seems to work quite well.

Use PyLink's `ts6` protocol module and enable the `use_elemental_modes` option.
Also enable `use_owner`, `use_admin`, and `use_halfop` if appropriate.

## IRC servers

### charybdis

Specify the `ircd = 'charybdis'` option in the `connect` block.

#### Nick length
Make sure that your configured nick length is consistent with the one you
compiled charybdis with; otherwise, users with longer nicks will be killed
as soon as they are propagated.

#### Ban propagation

You definitely want to have this enabled in your charybdis configuration:

```
use_propagated_bans = yes;
```

Also make sure that your `shared` block matches juno uplinks. As of writing, the
one in the default configuration matches all servers:

```
shared {
	oper = "*@*", "*";
	flags = all, rehash;
};
```

#### Remote oper notices
If you want to see remote server notices from charybdis, be sure to enable
the juno oper notice flags associated with each desired snomask letter.
However, since juno notice flags are very verbose and fine-tunable, you can get
most information from local notices.

### ratbox

Specify the `ircd = 'ratbox'` option in the `connect` block.

#### Nick length
Make sure that your configured nick length is consistent with the one you
compiled ratbox with; otherwise, users with longer nicks will be killed
as soon as they are propagated. RATBOX HAS A VERY LOW DEFAULT NICK LENGTH.

#### Ban propagation

Adding `cluster` and `shared` blocks to your ratbox configuration is strongly
recommended due to the fact that it lacks the `BAN` capability.
This will effectively make all K-Lines, nick reserves, etc. which originated
on ratbox global, just as they would be if they were set on juno.

```
cluster {
	name = "*";
	flags = all;
};

shared {
	oper = "*@*", "*";
	flags = all;
};
```
