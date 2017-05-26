# TS6 support

This document details how to use juno with software implementing the
[TS6 linking protocol](technical/proto/ts6.md).

The TS6 protocol module can be used to link juno with a
[variety](#supported-software) of IRC servers and other software. While
it is also possible to link juno servers via TS6, the native
[Extensible Linking Protocol](technical/proto/jelp.md) is strongly preferred for such.

## Listening for TS6

The current implementation requires dedicated ports for TS6 links. This is
because it is far too complicated to try to distinguish between different server
protocols, particularly when each is provided in the form of an optional module.

This is only necessary if you intend to accept connections from TS6 servers. If
juno will be initiating the connection (such as with CONNECT or autoconnect),
you do not have to listen for TS6.

In your `listen` blocks, add `ts6port` and/or `ts6sslport` options. Values are
the same as `port`; lists and ranges are accepted.

In your `connect` blocks for TS6 uplinks, you must also specify the `ircd`
option from the list of supported software below.

# Supported software

This is a list of IRC servers and packages that have been tested and seem to
work well with juno TS6. Other software may also be supported using
[custom mode mappings and options](technical/proto/ts6.md#mode-definitions-and-ircd-specific-options).

## atheme

Provides nickname and channel registration, plus a lot of other stuff.

Specify the `ircd = 'atheme'` option in the `connect` block.

Compile and install the
[provided protocol module](https://github.com/cooper/juno/blob/master/extra/atheme/juno.c).

Be sure to configure atheme to load modules that are associated with your status
mode configuration. On the default +qaohv configuration, you will want
`chanserv/owner`, `chanserv/protect`, and `chanserv/halfop`.

The provided protocol module supports +qaohv, so if you want to disable certain
statuses then you can use atheme's protocol mixin modules.

### Known issues

The QUIET command provided by `chanserv/quiet` does not work on juno due to it
having a hard-coded letter `q` for quiets.

## PyLink

A services framework which features a multi-network IRC relay.

Specify the `ircd = 'elemental'` option in the `connect` block. PyLink works
with juno by pretending to be elemental-ircd. It seems to work quite well.

Use PyLink's `ts6` protocol module and enable the `use_elemental_modes` option.
Also enable `use_owner`, `use_admin`, and `use_halfop` if appropriate.

## charybdis

Specify the `ircd = 'charybdis'` option in the `connect` block.

### Nick length

Make sure that your configured nick length is consistent with the one you
compiled charybdis with; otherwise, users with longer nicks will be killed
as soon as they are propagated.

### Ban propagation

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

### Remote oper notices

If you want to see remote server notices from charybdis, be sure to enable
the juno oper notice flags associated with each desired snomask letter.
However, since juno notice flags are very verbose and fine-tunable, you can get
most information from local notices.

## ratbox

Specify the `ircd = 'ratbox'` option in the `connect` block.

### Nick length

Make sure that your configured nick length is consistent with the one you
compiled ratbox with; otherwise, users with longer nicks will be killed
as soon as they are propagated. RATBOX HAS A VERY LOW DEFAULT NICK LENGTH.

### Ban propagation

Adding `cluster` and `shared` blocks to your ratbox configuration is strongly
recommended due to the fact that it lacks a global ban mechanism.
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

### Known issues

* __Hostname limitations__: ratbox has hostname length limits stricter than
other servers, so hostnames may be truncated. Also, it does not support
forward slashes (`/`) in hosts, so they are rewritten as dots (`.`).

* __NICKDELAY__: ratbox does not support a nick delay command, which is used by
services to prevent users from switching back to a nickname immediately after
services forced them to a "Guest" nick. When linking ratbox to services,
[`RESV`](technical/proto/ts6.md#resv) is used instead, but if ratbox reaches services
indirectly via juno, it cannot understand the encapsulated
[`NICKDELAY`](techincal/ts6.md#nickdelay) command that would normally be
forwarded to it. To resolve this, juno rewrites `NICKDELAY` as `RESV` and
attempts to find NickServ using the `services:nickserv` config option, using it
as the source of the `RESV` command. See issue
[#137]( https://github.com/cooper/juno/issues/137).

* __Cloaking__: ratbox does not have hostname cloaking and does not handle the
REALHOST command. The result is that, on ratbox servers, users with hidden hosts
will show their cloak as their real host, but their underlying IP address can
easily be exposed to any user with a simple `WHOIS` command. There are plans to
add an option to spoof the IP address field so that this is not possible.
