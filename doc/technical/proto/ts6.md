# TS6

This is a description of the TS6 server linking protocol and
[our implementation](#implementation) of it. For less technical
info on how to use TS6 with juno, see [this document](../../ts6.md).

Based on
[`ts6-protocol.txt`](https://github.com/charybdis-ircd/charybdis/blob/release/3.5/doc/technical/ts6-protocol.txt)
from the charybdis technical documentation. Written by Jilles Tjoelker.

* [Glossary](#glossary)
* [Propagation](#propagation)
* [Connection setup](#connection-setup)
* [Modes](#modes)
* [Commands](#commands)
* [Implementation](#implementation)
* [Server capabilities](#server-capabilities)
  * [Required](#required)
  * [Supported](#supported)
* [Mode definitions and IRCd\-specific options](#mode-definitions-and-ircd-specific-options)
* [Mode translation](#mode-translation)
  * [Omission of unknown modes](#omission-of-unknown-modes)
  * [Status message targets](#status-message-targets)
* [SID, UID conversion](#sid-uid-conversion)
* [K\-Lines, D\-Lines, etc\.](#k-lines-d-lines-etc)
  * [Durations](#durations)
  * [Command preference](#command-preference)
* [SASL](#sasl-1)

## Glossary

* __SID__ - a server's unique ID. It is configured in each server and consists of
a digit and two alphanumerics. Sending SIDs with lowercase letters is
questionable.

* __UID__ - a client's unique ID. It consists of the server's SID and six
alphanumerics (so it is nine characters long). The first of the alphanumerics
should be a letter, numbers are legal but reserved for future use.

* __hunted__ - a parameter type used for various remote requests. From local users,
nicknames and server names are accepted, possibly with wildcards; from servers,
UIDs/SIDs (sending names or even wildcards is deprecated). This is done with
the function hunt_server(). Any rate limiting should be done locally.

* __duration__ - a parameter type used for ban durations. It is a duration in seconds.
A value of 0 means a permanent ban.

* __IP addresses__ - IP addresses are converted to text in the usual way, including
'::' shortening in IPv6, with the exception that a zero is prepended to any
IP address that starts with a colon.

* __propagation__ - to which other servers the command is sent.
see [propagation](#propagation).

* __services server__ - server mentioned in a service{} block. There are no services
servers on EFnet.

* __service__ - client with umode +S. This implies that it is on a services server.

## Propagation

For all commands with a _hunted_ parameter, the propagation is determined by
that, and not otherwise specified.

For all commands with a target server mask parameter, the propagation is
determined by that, and not otherwise specified. The command is sent to all
servers with names matching the given mask (for example '\*', '\*.example.com',
'irc.example.com'). Those servers do not have to be directly connected.
Targets cannot be SIDs.

Propagation _broadcast_ means the command is sent to all servers.

Propagation _one-to-one_ means the command is only sent to the target or the
server the target is on.

Propagation _none_ means the command is never sent to another server if it is
received.

For some other commands, the propagation depends on the parameters and is
described in text.

## Connection setup

The initiator sends the `PASS`, `CAPAB` and `SERVER` messages. Upon receiving the
`SERVER`, the listener will check the information, and if it is valid, it will
send its own `PASS`, `CAPAB` and `SERVER` messages, followed by `SVINFO` and the burst.
Upon receiving the `SERVER`, the initiator will send SVINFO and the burst. If
ziplinks are used, `SVINFO` is the first compressed message.

The burst consists of `SID` and `SERVER` messages for all known servers, `BAN`
messages for all propagated bans, `UID` or `EUID` messages for all known users
(possibly followed by `ENCAP REALHOST`, `ENCAP LOGIN` and/or `AWAY`) and `SJOIN`
messages for all known channels (possibly followed by `BMASK` and/or `TB`).

## Modes

user modes:

    +D (deaf: does not receive channel messages)
    +S (network service) (only settable on burst from a services server)
    +a (appears as server administrator)
    +i (invisible, see rfc1459)
    +o (IRC operator, see rfc1459)
    +w (wallops, see rfc1459) (always propagated for historical reasons)
    (charybdis TS6)
    +Q/+R/+g/+l/+s/+z (only locally effective)
    +Z (ssl user) (only settable on burst)
    possibly more added by modules

channel modes:

    statuses
    +o (prefix @) (ops)
    +v (prefix +) (voice)
    type A
    +b (ban)
    +e (ban exception) (capab: EX)
    +I (invite exception) (capab: IE)
    type B
    +k (key: password required to join, <= 23 ascii chars, no `:` or `,` or whitespace)
    type C
    +l (limit: maximum number of members before further joins are disallowed)
    type D
    +m (moderated)
    +n (no external messages)
    +p (private: does not appear in `WHOIS` to non-members, no `KNOCK` allowed)
    +r (only registered users may join) (only if a services server exists) (capab: SERVICES)
    +s (secret)
    +t (only chanops may change topic)
    (charybdis TS6)
    type A
    +q (quiet)
    type C
    +f (forward: channel name <= 30 chars)
    +j (join throttle: N:T with integer N and T)
    type D
    +F (free target for +f)
    +L (large ban list)
    +P (permanent: does not disappear when empty)
    +Q (ignore forwards to this)
    +c (strip colours)
    +g (allow any member to `INVITE`)
    +z (send messages blocked by +m to chanops)

## Commands

General format: much like rfc1459.

Maximum parameters for a command: 15 (this does not include the prefix
and command name).

### Numerics
    source: server
    parameters: target, any...

The command name should be three decimal ASCII digits.

Propagates a "numeric" command reply, such as from a remote WHOIS request.

If the first digit is 0 (indicating a reply about the local connection), it
should be changed to 1 before propagation or sending to a user.

Numerics to the local server may be sent to opers.

To avoid infinite loops, servers should not send any replies to numerics.

The target can be:
- a client
  - propagation: one-to-one
- a channel name
  - propagation: all servers with -D users on the channel

Numerics to channels are broken in some older servers.

### ADMIN
    source: user
    parameters: hunted

Remote ADMIN request.

### AWAY
    source: user
    propagation: broadcast
    parameters: opt. away reason

If the away reason is empty or not present, mark the user as not away.
Otherwise, mark the user as away.

Changing away reason from one non-empty string to another non-empty string
may not be propagated.

### BAN
    charybdis TS6
    capab: BAN
    source: any
    propagation: broadcast (restricted)
    parameters: type, user mask, host mask, creation TS, duration, lifetime, oper, reason

Propagates a network wide ban.

The type is K for K:lines, R for resvs and X for X:lines; other types are
reserved. The user mask field is only used for K:lines; for resvs and X:lines
the field is ignored in input and sent as an asterisk.

The creation TS indicates when this ban was last modified. An incoming ban MUST
be ignored and not propagated if the creation TS is older than the creation TS
of the current ban. If the ban is identical, it SHOULD NOT be propagated to
avoid unnecessary network traffic. (Two changes to bans that set the TS to the
same value may cause desynchronization.)

The duration is 0 for an unban and relative to the creation TS for a ban.
When the duration has passed, the ban is no longer active but it may still
be necessary to remember it.

The lifetime is relative to the creation TS and indicates for how long this
ban needs to be remembered and propagated. This MUST be at least the duration.
Initially, it is usually set the same as the duration but when the ban is
modified later, it SHOULD be set such that the modified ban is remembered at
least as long as the original ban. This ensures that the original ban does not
revive via split servers. This requirement is only a SHOULD to allow for
implementations that only inject bans and do not remember any; implementations
that remember and propagate bans MUST set the lifetime appropriately.

The oper field indicates the oper that originally set the ban. If this message
is the initial propagation of a change, it SHOULD be sent as * (an asterisk).

The reason field indicates the reason for the ban. Any part after a | (vertical
bar) MUST NOT be shown to normal users. The rest of the field and the creation
TS and duration MAY be shown to normal users.

### BMASK
    source: server
    propagation: broadcast
    parameters: channelTS, channel, type, space separated masks

If the channelTS in the message is greater (newer) than the current TS of
the channel, drop the message and do not propagate it.

Type is the mode letter of a ban-like mode. In efnet TS6 this is 'b', 'e' or
'I'. In charybdis TS6 additionally 'q' is possible.

Add all the masks to the given list of the channel.

All ban-like modes must be bursted using this command, not using MODE or TMODE.

### CAPAB
    source: unregistered server
    propagation: none
    parameters: space separated capability list

Sends capabilities of the server. This must include `QS` and `ENCAP`, and for
charybdis TS6 also `EX` and `IE`. It is also strongly recommended to include `EX`,
`CHW`, `IE` and `KNOCK`, and for charybdis TS6 also `SAVE` and `EUID`. For use with
services, `SERVICES` and `RSFNC` are strongly recommended.

The capabilities may depend on the configuration for the server they are sent
to.

### CHGHOST
    charybdis TS6
    source: any
    propagation: broadcast
    parameters: client, new hostname

Changes the visible hostname of a client.

Opers are notified unless the source is a server or a service.

### SETNAME
    IRCv3 setname
    source: user
    propagation: broadcast
    parameters: new realname

Changes the realname (gecos) of a user.

Only clients with the `setname` capability will see this message.

### CONNECT
    source: any
    parameters: server to connect to, port, hunted

Remote connect request. A server WALLOPS should be sent by the receiving
server.

The port can be 0 for the default port.

### DLINE
    charybdis TS6
    encap only
    source: user
    parameters: duration, mask, reason

Sets a D:line (IP ban checked directly after accepting connection).

The mask must be an IP address or CIDR mask.

### ENCAP
    source: any
    parameters: target server mask, subcommand, opt. parameters...

Sends a command to matching servers. Propagation is independent of
understanding the subcommand.

Subcommands are listed elsewhere with "encap only".

### ERROR
    source: server or unregistered server
    propagation: none
    parameters: error message

Reports a (usually fatal) error with the connection.

Error messages may contain IP addresses and have a negative effect on server
IP hiding.

### ETB
    capab: EOPMOD
    source: any
    propagation: broadcast
    parameters: channelTS, channel, topicTS, topic setter, opt. extensions, topic

Propagates a channel topic change or propagates a channel topic as part of a
burst.

If the channel had no topic yet, the channelTS in the message is lower (older)
than the current TS of the channel, or the channelTSes are equal and the
topicTS in the message is newer than the topicTS of the current topic on the
channel, set the topic with topicTS and topic setter, and propagate the
message. Otherwise ignore the message and do not propagate it.

Unlike a TB message, an ETB message can change the topicTS without changing
the topic text. In this case, the message should be propagated to servers but
local users should not be notified.

Services can send a channelTS of 0 to force restoring an older topic (unless
the channel's TS is 0). Therefore, the channelTS should be propagated as given
and should not be replaced by the current TS of the channel.

An ETB message with a newer channelTS can still set a topic on a channel
without topic. This corresponds to SJOIN not clearing the topic when lowering
TS on a channel.

If ETB comes from a user, it can be propagated to non-EOPMOD servers using
TOPIC, TB or a combination of TOPIC to clear the topic and TB to set a new
topic with topicTS. However, this can be somewhat noisy. On the other hand, if
ETB comes from a server, there is no way to force setting a newer topicTS. It
is possible to set the topic text but the incorrect topicTS may lead to desync
later on.

This document does not document the optional extensions between topic setter
and topic.

### ETRACE
    encap only
    encap target: single server
    source: oper
    parameters: client

Remote ETRACE information request.

### EUID
    charybdis TS6
    capab: EUID
    source: server
    parameters: nickname, hopcount, nickTS, umodes, username, visible hostname, IP address, UID, real hostname, account name, gecos
    propagation: broadcast

Introduces a client. The client is on the source server of this command.

The IP address MUST be '0' (a zero) if the true address is not sent such as
because of a spoof. Otherwise, and if there is no dynamic spoof (i.e. the
visible and real hostname are equal), the IP address MAY be shown to normal
users.

The account name is '\*' if the user is not logged in with services.

Nick TS rules apply.

EUID is similar to UID but includes the ENCAP REALHOST and ENCAP LOGIN
information.

### GCAP
    encap only
    encap target: *
    source: server
    parameters: space separated capability list

Capability list of remote server.

### GLINE
    efnet TS6
    capab: GLN
    source: user
    parameters: user mask, host mask, reason
    propagation: broadcast

Propagates a G:line vote. Once votes from three different opers (based on
user@host mask) on three different servers have arrived, trigger the G:line.
Pending G:lines expire after some time, usually ten minutes. Triggered G:lines
expire after a configured time which may differ across servers.

Requests from server connections must be propagated, unless they are found to
be syntactically invalid (e.g. '!' in user mask). Therefore, disabling glines
must not affect propagation, and too wide glines, double votes and glines that
already exist locally must still be propagated.

Of course, servers are free to reject gline requests from their own operators.

### GUNGLINE
    efnet TS6
    encap only
    encap target: *
    source: user
    parameters: user mask, host mask, reason
    propagation: broadcast

Propagates a G:line removal vote. Once three votes have arrived (as with
G:lines), remove the G:line. Pending G:lines removals expire after some time,
usually ten minutes.

Pending G:line removals do not interact with pending G:lines. Triggering a
G:line does not affect a pending G:line removal. Triggering a G:line removal
does not affect a pending G:line.

### INFO
    source: user
    parameters: hunted

Remote INFO request.

### INVITE
    source: user
    parameters: target user, channel, opt. channelTS
    propagation: one-to-one

Invites a user to a channel.

If the channelTS is greater (newer) than the current TS of the channel, drop
the message.

Not sending the channelTS parameter is deprecated.

### JOIN
    1.
    source: user
    parameters: '0' (one ASCII zero)
    propagation: broadcast

Parts the source user from all channels.

    2.
    source: user
    parameters: channelTS, channel, '+' (a plus sign)
    propagation: broadcast

Joins the source user to the given channel. If the channel does not exist yet,
it is created with the given channelTS and no modes. If the channel already
exists and has a greater (newer) TS, wipe all simple modes and statuses and
change the TS, notifying local users of this but not servers (note that
ban-like modes remain intact; invites may or may not be cleared).

A JOIN is propagated with the new TS of the channel.

### JUPE
    capab: JUPE
    source: any
    propagation: broadcast (restricted)
    parameters: target server mask, add or delete, server name, oper, reason

Adds or removes a jupe for a server.  If the server is presently connected,
it MUST be SQUIT by the server's uplink when the jupe is applied.

The oper field indicates the oper that originally set the jupe. If this message
is the initial propagation of a removal, it SHOULD be sent as * (an asterisk).

The reason field indicates the reason for the jupe.  It SHOULD be displayed
as the linking error message to the juped server if it tries to reconnect.

### KICK
    source: any
    parameters: channel, target user, opt. reason
    propagation: broadcast

Kicks the target user from the given channel.

Unless the channel's TS is 0, no check is done whether the source user has ops.

Not sending the reason parameter is questionable.

### KILL
    source: any
    parameters: target user, path
    propagation: broadcast

Removes the user from the network.

The format of the path parameter is some sort of description of the source of
the kill followed by a space and a parenthesized reason. To avoid overflow,
it is recommended not to add anything to the path.

### KLINE
    1.
    encap only
    source: user
    parameters: duration, user mask, host mask, reason

Sets a K:line (ban on user@host).

    2.
    capab: KLN
    source: user
    parameters: target server mask, duration, user mask, host mask, reason

As form 1, deprecated.

### KNOCK
    capab: KNOCK
    source: user
    parameters: channel
    propagation: broadcast

Requests an invite to a channel that is locked somehow (+ikl). Notifies all
operators of the channel. (In charybdis, on +g channels all members are
notified.)

This is broadcast so that each server can store when KNOCK was used last on
a channel.

### LINKS
    source: user
    parameters: hunted, server mask

Remote LINKS request. The server mask limits which servers are listed.

### LOCOPS
    1.
    encap only
    source: user
    parameters: text

Sends a message to operators (with umode +l set). This is intended to be
used for strict subsets of the network.

    2.
    capab: CLUSTER
    source: user
    parameters: target server mask, text

As form 1, deprecated.

### LOGIN
    encap only
    source: user
    parameters: account name

In a burst, states that the source user is logged in as the account.

### LUSERS
    source: user
    parameters: server mask, hunted

Remote LUSERS request. Most servers ignore the server mask, treating it as '\*'.

### MLOCK
    charybdis TS6
    source: services server
    parameters: channelTS, channel, mode letters
    propagation: broadcast (restricted)

Propagates a channel mode lock change.

If the channelTS is greater (newer) than the current TS of the channel, drop
the message.

The final parameter is a list of mode letters that may not be changed by local
users. This applies to setting or unsetting simple modes, and changing or
removing mode parameters.

An MLOCK message with no modes disables the MLOCK, therefore the MLOCK message
always contains the literal MLOCK for simplicity.

### MODE
    1.
    source: user
    parameters: client, umode changes
    propagation: broadcast

Propagates a user mode change. The client parameter must refer to the same user
as the source.

Not all umodes are propagated to other servers.

    2.
    source: any
    parameters: channel, cmode changes, opt. cmode parameters...

Propagates a channel mode change.

This is deprecated because the channelTS is not included. If it is received,
it should be propagated as TMODE.

### MOTD
    source: user
    parameters: hunted

Remote MOTD request.

### NICK
    1.
    source: user
    parameters: new nickname, new nickTS
    propagation: broadcast

Propagates a nick change.

    2.
    source: server
    parameters: nickname, hopcount, nickTS, umodes, username, hostname, server, gecos

Historic TS5 user introduction. The user is on the server indicated by the
server parameter; the source server is meaningless (local link).

### NICKDELAY
    charybdis TS6
    encap only
    encap target: *
    source: services server
    parameters: duration, nickname

If duration is greater than 0, makes the given nickname unavailable for that
time.

If duration is 0, removes a nick delay entry for the given nickname.

There may or may not be a client with the given nickname; this does not affect
the operation.

### NOTICE
    source: any
    parameters: msgtarget, message

As PRIVMSG, except NOTICE messages are sent out, server sources are permitted
and most error messages are suppressed.

Servers may not send '$$', '$#' and opers@server notices. Older servers may
not allow servers to send to specific statuses on a channel.

### OPERSPY
    encap only
    encap target: *
    source: user
    parameters: command name, parameters

Reports operspy usage.

### OPERWALL
    source: user
    parameters: message
    propagation: broadcast

Sends a message to operators (with umode +z set).

### PART
    source: user
    parameters: comma separated channel list, message

Parts the source user from the given channels.

### PASS
    source: unregistered server
    parameters: password, 'TS', TS version, SID

Sends the server link password, TS version and SID.

### PING
    source: any
    parameters: origin, opt. destination server

Sends a PING to the destination server, which will reply with a PONG. If the
destination server parameter is not present, the server receiving the message
must reply.

The origin field is not used in the server protocol. It is sent as the name
(not UID/SID) of the source.

Remote PINGs are used for end-of-burst detection, therefore all servers must
implement them.

### PONG
    source: server
    parameters: origin, destination

Routes a PONG back to the destination that originally sent the PING.

### PRIVMSG
    source: user
    parameters: msgtarget, message

Sends a normal message (PRIVMSG) to the given target.

The target can be:
- a client
  - propagation: one-to-one
- a channel name
  - propagation: all servers with -D users on the channel
  - cmode +m/+n should be checked everywhere, bans should not be checked
    remotely
- a status character ('@'/'+') followed by a channel name, to send to users
  with that status or higher only.
  - capab: CHW
  - propagation: all servers with -D users with appropriate status
- '=' followed by a channel name, to send to chanops only, for cmode +z.
  - capab: CHW and EOPMOD
  - propagation: all servers with -D chanops
- a user@server message, to send to users on a specific server. The exact
  meaning of the part before the '@' is not prescribed, except that "opers"
  allows IRC operators to send to all IRC operators on the server in an
  unspecified format.
  - propagation: one-to-one
- a message to all users on server names matching a mask ('$$' followed by mask)
  - propagation: broadcast
  - Only allowed to IRC operators.
- a message to all users with hostnames matching a mask ('$#' followed by mask).
  Note that this is often implemented poorly.
  - Unimplemented
  - propagation: broadcast
  - Only allowed to IRC operators.

In charybdis TS6, services may send to any channel and to statuses on any
channel.

### PRIVS
    charybdis TS6
    encap only
    encap target: single server
    source: oper
    parameters: client

Remote PRIVS information request.

### QUIT
    source: user
    parameters: comment

Propagates quitting of a client. No QUIT should be sent for a client that
has been removed as result of a KILL message.

### REALHOST
    charybdis TS6
    encap only
    encap target: *
    source: user
    parameters: real hostname

In a burst, propagates the real host of a dynamically-spoofed user.

### REHASH
    charybdis TS6
    encap only
    source: user
    parameters: opt. rehash type

Remote `REHASH` request. If the rehash type is omitted, it is equivalent to
a regular `REHASH`, otherwise it is equivalent to `REHASH <rehash type>`.

### RESV
    1.
    encap only
    source: user
    parameters: duration, mask, reason

Sets a RESV, making a nickname mask or exact channel unavailable.

    2.
    capab: CLUSTER
    source: user
    parameters: target server mask, duration, mask, reason

As form 1, deprecated.

### RSFNC
    encap only
    capab: RSFNC
    encap target: single server
    source: services server
    parameters: target user, new nickname, new nickTS, old nickTS

Forces a nickname change and propagates it.

The command is ignored if the nick TS of the user is not equal to the old
nickTS parameter. If the new nickname already exists (and is not the target
user), it is killed first.

### SASL
    charybdis TS6
    encap only
    1.
    encap target: *
    source: server
    parameters: source uid, '\*', 'S', sasl mechanism name

Requests that a SASL agent (a service) initiate the authentication process.
The source uid is that of an unregistered client. This is why it is not sent
as the prefix.

    2.
    encap target: single server
    source: server
    parameters: source uid, target uid, mode, data

Part of a SASL authentication exchange. The mode is 'C' to send some data
(base64 encoded), or 'D' to end the exchange (data indicates type of
termination: 'A' for abort, 'F' for authentication failure, 'S' for
authentication success).

### SAVE
    capab: SAVE
    source: server
    propagation: broadcast
    parameters: target uid, TS

Resolve a nick collision by changing a nickname to the UID.

The server should verify that the UID belongs to a registered user, the user
does not already have their UID as their nick and the TS matches the user's
nickTS. If not, drop the message.

SAVE should be propagated as a regular NICK change to links without SAVE capab.
present.

### SERVER
    1.
    source: unregistered server
    parameters: server name, hopcount, server description

Registers the connection as a server. PASS and CAPAB must have been sent
before, SVINFO should be sent afterwards.

If there is no such server configured or authentication failed, the connection
should be dropped.

This is propagated as a SID message.

    2.
    source: server
    propagation: broadcast
    parameters: server name, hopcount, server description

Introduces a new TS5 server, directly connected to the source of this command.
This is only used for jupes as TS5 servers may do little else than existing.

### SID
    source: server
    propagation: broadcast
    parameters: server name, hopcount, sid, server description

Introduces a new server, directly connected to the source of this command.

### SIGNON
    source: user
    propagation: broadcast
    parameters: new nickname, new username, new visible hostname, new nickTS, new login name

Broadcasts a change of several user parameters at once.

Currently only sent after an SVSLOGIN.

### SJOIN
    source: server
    propagation: broadcast
    parameters: channelTS, channel, simple modes, opt. mode parameters..., nicklist

Broadcasts a channel creation or bursts a channel.

The nicklist consists of users joining the channel, with status prefixes for
their status ('@+', '@', '+' or ''), for example:
'@+1JJAAAAAB +2JJAAAA4C 1JJAAAADS'. All users must be behind the source server
so it is not possible to use this message to force users to join a channel.

The interpretation depends on the channelTS and the current TS of the channel.
If either is 0, set the channel's TS to 0 and accept all modes. Otherwise, if
the incoming channelTS is greater (newer), ignore the incoming simple modes
and statuses and join and propagate just the users. If the incoming channelTS
is lower (older), wipe all modes and change the TS, notifying local users of
this but not servers (invites may be cleared). In the latter case, kick on
split riding may happen: if the key (+k) differs or the incoming simple modes
include +i, kick all local users, sending KICK messages to servers.

An SJOIN is propagated with the new TS and modes of the channel. The statuses
are propagated if and only if they were accepted.

SJOIN must be used to propagate channel creation and in netbursts. For regular
users joining channels, JOIN must be used. Pseudoservers may use SJOIN to join
a user with ops.

### SNOTE
    charybdis TS6
    encap only
    source: server
    parameters: snomask letter, text

Sends the text as a server notice from the source server to opers with the
given snomask set.

### SQUIT
    parameters: target server, comment

Removes the target server and all servers and users behind it from the network.

If the target server is the receiving server or the local link this came from,
this is an announcement that the link is being closed.

Otherwise, if the target server is locally connected, the server should send
a WALLOPS announcing the SQUIT.

### STATS
    source: user
    parameters: stats letter, hunted

Remote STATS request. Privileges are checked on the server executing the
actual request.

### SU
    encap only
    encap target: *
    source: services server
    parameters: target user, new login name (optional)

If the new login name is not present or empty, mark the target user as not
logged in, otherwise mark the target user as logged in as the given account.

### SVINFO
    source: server
    propagation: none
    parameters: current TS version, minimum TS version, '0', current time

Verifies TS protocol compatibility and clock. If anything is not in order,
the link is dropped.

The current TS version is the highest version supported by the source server
and the minimum TS version is the lowest version supported.

The current time is sent as a TS in the usual way.

### SVSLOGIN
    charybdis TS6
    encap only
    encap target: single server
    source: services server
    parameters: target, new nick, new username, new visible hostname, new login name

Sent after successful SASL authentication.

The target is a UID, typically an unregistered one.

Any of the "new" parameters can be '\*' to leave the corresponding field
unchanged. The new login name can be '0' to log the user out.

If the UID is registered on the network, a SIGNON with the changes will be
broadcast, otherwise the changes will be stored, to be used when registration
completes.

### TB
    capab: TB
    source: server
    propagation: broadcast
    parameters: channel, topicTS, opt. topic setter, topic

Propagates a channel topic as part of a burst.

If the channel had no topic yet or the topicTS in the message is older than
the topicTS of the current topic on the channel and the topics differ, set
the topic with topicTS and topic setter, and propagate the message. Otherwise
ignore the message and do not propagate it.

If the topic setter is not present, use a server name instead.

### TIME
    source: user
    parameters: hunted

Remote TIME request.

### TMODE
    source: any
    parameters: channelTS, channel, cmode changes, opt. cmode parameters...

Propagates a channel mode change.

If the channelTS is greater (newer) than the current TS of the channel, drop
the message.

On input, only the limit on parameters per line restricts how many cmode
parameters can be present. Apart from this, arbitrary modes shall be
processed. Redundant modes may be dropped. For example, +n-n may be applied and
propagated as +n-n, -n or (if the channel was already -n) nothing, but not as
+n.

The parameter for mode -k (removing a key) shall be ignored.

On output, at most ten cmode parameters should be sent; if there are more,
multiple TMODE messages should be sent.

### TOPIC
    source: user
    propagation: broadcast
    parameters: channel, topic

Propagates a channel topic change. The server may verify that the source has
ops in the channel.

The topicTS shall be set to the current time and the topic setter shall be
set indicating the source user. Note that this means that the topicTS of a
topic set with TOPIC is not necessarily consistent across the network.

### TRACE
    source: user
    1.
    parameters: hunted

Performs a trace to the target, sending 200 numerics from each server passing
the message on. The target server sends a description of the target followed
by a 262 numeric.

TRACE, STATS l and STATS L are the only commands using hunt_server that use the
hunted parameter for more than just determining which server the command
should be executed on.

    2.
    parameters: target name, hunted

Executes a trace command on the target server. No 200 numerics are sent.
The target name is a name, not a UID, and should be on the target server.

### UID
    source: server
    propagation: broadcast
    parameters: nickname, hopcount, nickTS, umodes, username, visible hostname, IP address, UID, gecos
    propagation: broadcast

Introduces a client. The client is on the source server of this command.

The IP address MUST be '0' (a zero) if the true address is not sent such as
because of a spoof. Otherwise, and if there is no dynamic spoof (ENCAP
REALHOST, charybdis TS6 only), the IP address MAY be shown to normal users.

Nick TS rules apply.

### UNDLINE
    charybdis TS6
    encap only
    source: user
    parameters: mask

Removes a D:line (IP ban checked directly after accepting connection).

The mask must be an IP address or CIDR mask.

### UNKLINE
    1.
    encap only
    source: user
    parameters: user mask, host mask

Removes a K:line (ban on user@host).

    2.
    capab: UNKLN
    source: user
    parameters: target server mask, user mask, host mask

As form 1, deprecated.

### UNRESV
    1.
    encap only
    source: user
    parameters: mask

Removes a RESV.

    2.
    capab: CLUSTER
    source: user
    parameters: target server mask, mask

As form 1, deprecated.

### UNXLINE
    1.
    encap only
    source: user
    parameters: mask

Removes an X:line (ban on realname).

    2.
    capab: CLUSTER
    source: user
    parameters: target server mask, mask

As form 1, deprecated.

### USERS
    source: user
    parameters: hunted

Remote USERS request.

### VERSION
    source: any
    parameters: hunted

Remote VERSION request.

### WALLOPS
    1.
    source: user
    parameters: message
    propagation: broadcast

In efnet TS6, sends a message to operators (with umode +z set). This is a
deprecated equivalent to OPERWALL.

In charybdis TS6, sends a message to local users with umode +w set (or possibly
another indication that WALLOPS messages should be sent), including non-opers.

    2.
    source: server
    parameters: message
    propagation: broadcast

Sends a message to local users with umode +w set (or possibly another
indication that WALLOPS messages should be sent).

In efnet TS6 this may include non-opers, in charybdis TS6 this may only be
sent to opers.

### WHOIS
    source: user
    parameters: hunted, target nick

Remote WHOIS request.

### WHOWAS
    source: user
    parameters: nickname, limit, hunted

Remote WHOWAS request. Not implemented in all servers.

Different from a local WHOWAS request, the limit is mandatory and servers should
apply a maximum to it.

### XLINE
    1.
    encap only
    source: user
    parameters: duration, mask, reason

Sets an X:line (ban on realname).

    2.
    capab: CLUSTER
    source: user
    parameters: target server mask, duration, mask, reason

As form 1, deprecated.

End of TS6 protocol specification.

# Implementation

This section makes note of noteworthy specifics of juno's implementation of the
protocol.

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
    ban     = [3, 'b']
    except  = [3, 'e']

[ ircd: charybdis ]
    extends = 'ratbox'
    nicklen = 32

[ ircd_cmodes: charybdis ]
    quiet   = [3, 'q']
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

### Omission of unknown modes

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

### Status message targets

PRIVMSGs and NOTICEs can be directed to channel members with a certain status or
higher with the `<prefix><channel>` syntax, such as `@#channel` or `+#channel`.
To ensure that members on TS-based servers that do not have some status modes
still receive these, juno translates them to the "nearest" status which is less
than or equal to the original one. For example, `&#channel`
(a message to protected members) will become `@#channel` on charybdis since it
does not support admins.

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

## K-Lines, D-Lines, etc.

[Ban::TS6](https://github.com/cooper/juno/blob/master/modules/Ban/Ban.module/TS6.module)
provides the TS6 server ban implementation. It is loaded automatically when TS6
and Ban are both loaded.

juno bans are global, but on TS-based servers, bans are generally local-only
(unless using services, cluster, or some other extension). In order to keep a
mixed juno/TS6 network secure, juno will do its best to globally propagate all
bans.

Bans are sent to TS6 servers on burst. Because certain ban commands only support
a user source, a ban agent bot may be introduced to set the bans and then exit.

### Durations

The duration sent to TS6 servers is variable based on the difference between the
expiration time and the duration, since we cannot propagate an expiration time.
The TS6 server will ignore any bans which already exist for the given mask,
which is perfect for our purposes. An exception to this is the newer BAN command
which does allow propagation of expiry times and is used when available.

A limitation of the BAN command is that it does not support global permanent
bans. In such a case, juno will use the maximum ban duration supported by
charybdis which, at the time of writing, is 364 days. After a year passes and
the ban expires, it will be revived the next time the servers link.

### Command preference

Ban::TS6 uses the charybdis-style `BAN` command when possible. Legacy commands
are used when this is unavailable. Below are the commands used for each type
of ban in order of preference.

* __KLINE__: `BAN K` (BAN capab), `KLINE`/`UNKLINE` (KLN and UNKLN capabs),
  `ENCAP KLINE`/`ENCAP UNKLINE`
* __RESV__: `BAN R` (BAN capab), `RESV`/`UNRESV` (CLUSTER capab),
  `ENCAP RESV`/`ENCAP UNRESV`
* __NICKDELAY__: `ENCAP NICKDELAY` (EUID capab), `RESV` (CLUSTER capab),
  `ENCAP RESV`
* __DLINE__: `ENCAP DLINE`

Note that, because some server bans are local-only, the TS6 server may
not burst its own bans to juno (such as D-Lines, or even K-Lines if the BAN
capability is not available). However, ban commands are handled such that AKILLs
(which have target `*`) will be effective across an entire mixed charybdis/juno
network. AKILL is considered the most reliable way to ensure global ban
propagation.

See issue [#32](https://github.com/cooper/juno/issues/32)
for more information about the TS6 ban implementation.

## SASL

juno supports SASL authentication over TS6 using the `ENCAP` SASL mechanism.
This is useful for authenticating to services packages linked via TS6. See issue
[#9](https://github.com/cooper/juno/issues/9) for details.
