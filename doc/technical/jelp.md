# JELP

The Juno Extensible Linking Protocol (__JELP__) is the preferred
server linking protocol for juno-to-juno links.

As of writing, the only implementation known to exist is that of juno itself,
but future applications may choose to implement JELP for better compatibility
with juno.

This documentation is to be used as reference when implementing IRC servers and
pseudoservers.

## Format

The protocol resembles [RFC1459](https://tools.ietf.org/html/rfc1459) in that
each message represents a command with an optional source, target, and
additional parameters. The source is prefixed by a colon (`:`), as is the final
parameter if it includes whitespace.

Most messages resemble the following:
```
:<source> <command> [<parameters> ...]
```

However, a few do not require a source:
```
<command> [<parameters> ...]
```

Some also include [message tags](#message-tags).

### Line delimiters

A single message occurs per line. Empty lines are silently discarded.

The traditional line ending `\r\n` (CRLF) is replaced simply by `\n` (LF);
however for easier adoption in legacy software, `\r` MUST be ignored if present.

The traditional line length limit of 512 bytes does not apply, nor do any
limitations on the number of parameters per message. For this reason it is
especially important that only trusted servers are linked. However, servers MAY
choose to terminate an uplink if the receive queue exceeds a certain size.

### Entity identifiers

The protocol is further distinguished from RFC1459 by its use of user and server
identifiers as the source and target of commands in place of nicknames,
user masks, and server names. This idea is borrowed from other server linking
protocols such as [TS6](ts6.md); it aims to diminish the effects of name
collisions.

* __SID__ - A server identifier. This is numerical (consisting of digits 0-9).

* __UID__ - A user identifier. This consists of ASCII letters (a-z, A-Z),
prefixed by the numerical SID to which the user belongs. It is case-sensitive.

User and server identifiers in JELP are of arbitrary length but limited to
16 bytes. Servers SHOULD NOT use the prefix on UIDs to determine which server a
user belongs to. Servers MAY reuse UIDs that are no longer active should the 16
byte limit be exhausted.

### Message tags

Some messages have named parameters called tags. They occur at the start of the
message, before the source and command. The format is as follows:
```
@<name>=<value>[;<name2>=<value2> ...] :<source> <command> [<parameters> ...]
```

This is particularly useful for messages with optional parameters (as it reduces
overall message size when they are not present). More often, however, it is used
to introduce new fields without breaking compatibility with existing
implementations.

This idea is borrowed from an extension of the IRC client protocol, IRCv3.2
[message-tags](http://ircv3.net/specs/core/message-tags-3.2.html). The JELP
implementation of message tags is compatible with that specification in all
respects, except that the IRCv3 limitation of 512 bytes does not apply.

## Propagation

* _server mask_ - command is propagated based on a server mask parameter.
The command is sent to all servers with names matching the given mask
(for example `*`, `*.example.com`, `irc.example.com`). Those servers do not
have to be directly connected. Targets cannot be SIDs.

* _broadcast_ - command is sent to all servers.

* _one-to-one_ - command is only sent to the target or the
server the target is on.

* _conditional_ - propagation is dependent on command interpretation and is
described in the text. It may also be used to describe another propagation type
where the command may or may not be propagated based on its interpretation.

* _none_ - command is never sent to another server if it is received.

## Connection setup

1. __Server negotiation__ - The initiator sends the [`SERVER`](#server)
command. The receiver verifies the server name, SID, TS, peer address, and
versions. If unacceptable, the connection is dropped before password
negotiation; otherwise, the receiver replies with its own [`SERVER`](#server)
command.

2. __Password negotiation__ - If the incoming [`SERVER`](#server) passes
verification, the initiator sends [`PASS`](#pass). The receiver
verifies the password, dropping the connection if invalid. If the password
is correct, the receiver replies with its own [`PASS`](#pass) command,
followed by [`READY`](#ready).

3. __Initiator burst__ - Upon receiving [`READY`](#ready), the initiator
sends its [burst](#burst), delimited by [`BURST`](#burst-1) and
[`ENDBURST`](#endburst).

4. __Receiver burst__ - Upon receiving [`ENDBURST`](#endburst), the receiver
replies with its own [burst](#burst). [`ENDBURST`](#endburst) and
[`READY`](#ready) should be handled the same way: in either case, the server
sends its burst if it has not already.

### Burst

A server burst consists of the following:

1. Initiate the burst with [`BURST`](#burst-1)
2. Send out this server's mode mappings
   - [`AUM`](#aum) - our user modes
   - [`ACM`](#acm) - our channel modes
3. Introduce descendant servers
   - [`SID`](#sid) - child server introduction
   - [`AUM`](#aum) - add each server's user modes
   - [`ACM`](#acm) - add each server's channel modes
4. Introduce users
   - [`UID`](#uid) - user introduction
   - [`OPER`](#oper) - oper flag propagation
   - [`LOGIN`](#login) - account name propagation
   - [`AWAY`](#away) - mark user as away
5. Burst channels
   - [`SJOIN`](#sjoin) - bursts modes, membership
   - [`TOPICBURST`](#topicburst) - bursts topic
6. Extensions
   - Any extension burst commands occur here, such as [`BAN`](#ban)
7. Terminate the burst with [`ENDBURST`](#endburst)

## Modes

JELP does not have predefined mode letters. Before any mode strings are sent
out, servers MUST send the [`AUM`](#aum) and [`ACM`](#acm) commands to map mode
letters and types to their names. Servers SHOULD track the mode mappings of all
other servers on the network, even for unrecognized mode names.

Throughout this documentation, commands involving mode strings will mention a
_perspective_, which refers to the server whose mode letter mappings should be
used in the parsing of the mode string. If the perspective is a user, it refers
to the server to which the user is connected.

Below are the lists of mode names, their types, and their usual associated
letters. Servers MAY implement any or all of them, but they MUST quietly ignore
any unrecognized incoming modes.

* [User modes](../umodes.md)
* [Channel modes](../cmodes.md)

## Required core commands

These commands MUST be implemented by servers. Failure to do so will result in
network discontinuity.

### ACM

Maps channel mode letters and types to mode names.

Propagation: _broadcast_

```
:<SID> ACM <name>:<letter>:<type> [<more modes> ...]
```

* __SID__ - server these mode mappings belong to
* __name__ - mode name
* __letter__ - mode letter
* __type__ - mode type, which describes how to allocate parameters in a
  mode string. one of
  - `0` - normal mode, no parameter
  - `1` - mode with parameter always
  - `2` - mode with parameter only when setting
  - `3` - banlike list mode
  - `4` - status mode
  - `5` - channel key (special case)

### AUM

Maps user mode letters to mode names.

Propagation: _broadcast_

```
:<SID> AUM <name>:<letter> [<more modes> ...]
```

* __SID__ - server these mode mappings belong to
* __name__ - mode name
* __letter__ - mode letter

### AWAY

Marks a user as away.

Propagation: _broadcast_

```
:<UID> AWAY [:<reason>]
```

* __UID__ - user to mark as away
* __reason__ - _optional_, reason for being away. if omitted, the user is
  returning from away state.

### BURST

Sent to indicate the start of a burst.

This is used for the initial burst as well as the bursts of other descendant
servers introduced later.

The corresponding [`ENDBURST`](#endburst) terminates the burst.

Propagation: _broadcast_

```
:<SID> BURST <TS>
```

* __SID__ - server bursting
* __TS__ - current UNIX TS

### CMODE

Channel mode change.

Propagation: _conditional broadcast_

```
:<source> CMODE <channel> <TS> :<modes>
```

* __source__ - user or server committing the mode change
* __channel__ - channel to change modes on
* __TS__ - channel TS
* __modes__ - mode string, in the perspective of `<source>`

If `<TS>` is newer than the internal channel TS, drop the message and do not
propagate it.

If `<TS>` is older than the internal channel TS, accept and propagate the
incoming modes, resetting all previous channel modes and invitations.

If `<TS>` is equal to the internal channel TS, accept and propagate the incoming
modes.

Note that the entire mode string is a single parameter.

### ENDBURST

Sent to indicate the end of a burst.

Propagation: _broadcast_

```
:<SID> ENDBURST <TS>
```

* __SID__ - server whose burst has ended
* __TS__ - current UNIX TS

Upon receiving, the server should send its own [burst](#burst) if it has not
already.

### JOIN

Channel join. Used when a user joins an existing channel with no status modes.

Propagation: _broadcast_

```
:<UID> JOIN <channel> <TS>
```

* __UID__ - user joining the channel
* __channel__ - channel being joined
* __TS__ - channel TS

If `<channel>` does not exist, create it. This should not happen though.

If `<TS>` is older than the internal channel TS, reset all channel modes and
invitations.

Regardless of `<TS>`, add the user to the channel and propagate the `JOIN` with
the CURRENT channel TS.

See also [`SJOIN`](#sjoin).

### KICK

Propagates a channel kick. Removes a user from a channel.

Propagation: _broadcast_

```
:<source> KICK <channel> <target UID> :<reason>
```

* __source__ - user or server committing the kick
* __channel__ - channel to remove the target user from
* __target UID__ - user to remove
* __reason__ - kick comment

### KILL

Temporarily removes a user from the network.

Propagation: _broadcast_

```
:<source> KILL <target UID> :<reason>
```

* __source__ - user or server committing the kill
* __target UID__ - user to remove
* __reason__ - kill comment, visible as part of the user quit message

KILL is not acknowledged (it is NOT followed by QUIT), and for that reason, it
cannot be rejected. Pseudoservers whose clients cannot be killed may internally
disregard the KILL message but, in that case, must immediately reintroduce the
user to uplinks.

### NICK

Propagates a nick change.

Propagation: _broadcast_

```
:<UID> NICK <nick>
```

* __UID__ - user changing nicks
* __nick__ - new nick

Update the nick and set the nick TS to the current time.

### NOTICE

To the extent that concerns JELP, equivalent to [`PRIVMSG`](#privmsg) in all
ways other than the command name.

Propagation: _conditional_

### NUM

Sends a numeric reply to a remote user.

Propagation: _one-to-one_

```
:<SID> NUM <UID> <num> :<message>
```

* __SID__ - source server
* __UID__ - target user
* __num__ - numeric, a three-digit sequence
* __message__ - numeric message

If `<num>` starts with `0`, rewrite the first digit as `1`. This is because the
numerics in the `0XX` range are permitted only from the server the user is
connected to.

Note that `<message>` may actually contain several numeric parameters combined
into a single string. It may also contain a sentinel (in addition to the usual
one which prefixes it) at the start or later in the message. For this reason,
`<message>` should not be prefixed with a sentinel when forwarding it to the
target user.

### OPER

Propagates oper privileges.

The setting of the `ircop` user mode (+o) is used to indicate that a user has
opered-up; this command may be used to modify their permissions list.

Propagation: _broadcast_

```
:<UID> OPER [-]<flag> [<flag> ...]
```

* __UID__ - user whose privileges are to be changed
* __flag__ - any number of [oper flags](../oper_flags.md) may be added or
  removed in a single message, each as a separate parameter. those being removed
  are prefixed by `-`; those being added have no prefix.

### PART

Propagates a channel part.

Propagation: _broadcast_

```
:<UID> PART <channel> <TS> :<reason>
```

* __UID__ - user to be removed
* __channel__ - channel to remove the user from
* __TS__ - channel TS

If `<TS>` is older than the internal channel TS, reset all channel modes and
invitations.

Regardless of `<TS>`, remove the user from the channel and propagate the message
with the CURRENT channel TS.

### PARTALL

Used when a user leaves all channels.

This is initiated on the client protocol with the `JOIN 0` command.

Propagation: _broadcast_

```
:<UID> PARTALL
```

* __UID__ - user to be removed from all channels

### PASS

During [registration](#connection-setup), sends the connection password.

Propagation: _none_

```
PASS <password>
```

* __password__ - connection password in plain text

See [connection setup](#connection-setup).

### PING

Verifies uplink reachability.

Propagation: _none_

```
PING <message>
```

* __message__ - some data which will also be present in the
  corresponding [`PONG`](#pong)

### PONG

Reply for [`PING`](#ping).

Propagation: _none_

```
:<SID> PONG <message>
```

* __SID__ - server replying to the PING
* __message__ - data which was specified in the corresponding [`PING`](#ping)

### PRIVMSG

Sends a message.

Propagation: _conditional_

```
:<source> PRIVMSG <target> :<message>
```

* __source__ - user or server sending the message
* __target__ - message target, see below
* __message__ - message text

`<target>` can be any of the following:

- a user
  - Propagation: _one-to-one_
- a channel
  - Propagation: all servers with non-deaf users on the channel
- `@` followed by a status mode letter and a channel name, to message all users
  on the channel with that status or higher
  - Propagation: all servers with -D users of appropriate status
  - Example: `@o#channel` - all users on #channel with `+o` or higher
- `=` followed by a channel name, to send to channel ops only, for
  [op moderation](../modules.md#channelopmoderate)
  - Propagation: all servers with -D channel ops
- a `user@server.name` message, to send to users on a specific server. the exact
  meaning of the part before the `@` is not prescribed, except that "opers"
  allows IRC operators to send to all IRC operators on the server in an
  unspecified format. this can also be used for more secure communications to
  external services
- a message to all users on server names matching a mask (`$$` followed by mask)
  - Propagation: _broadcast_
  - Only allowed to IRC operators
- a message to all users with hostnames matching a mask (`$#` followed by mask)
  - Unimplemented
  - Propagation: _broadcast_
  - Only allowed to IRC operators

### QUIT

Propagates a user or server quit.

Propagation: _broadcast_

Form 1
```
:<UID> QUIT :<reason>
```

* __UID__ - user quitting
* __reason__ - quit comment

Form 2
```
[@from=] :<SID> QUIT :<reason>
```

* __from__ - _optional_, user that initiated the SQUIT
* __SID__ - server quitting
* __reason__ - quit comment

### READY

Sent to indicate that the initiator should send its [burst](#burst).

Propagation: _none_

```
READY
```

See [connection setup](#connection-setup).

### SAVE

Used to resolve nick collisions without casualty.

Propagation: _broadcast_

### SERVER

During [registration](#connection-setup), introduces the server.

Propagation: _none_

```
SERVER <SID> <name> <proto version> <version> <TS> :<description>
```

* __SID__ - [server ID](#entity-ids)
* __name__ - server name
* __proto version__ - JELP protocol version (checked for compatibility)
* __version__ - IRCd or package version (not checked)
* __TS__ - current UNIX TS
* __description__ - server description to show in `LINKS`, `MAP`, etc. This
  MUST be the last parameter, regardless of any additional parameters which may
  be added in between the `<TS>` and `<description>` at a later date. If the
  description starts with the sequence `(H) ` (including the trailing space),
  the server should be marked as hidden

See [connection setup](#connection-setup).

### SID

Introduces a server.

Propagation: _broadcast_

```
:<source SID> SID <SID> <TS> <name> <proto version> <version> :<description>
```

* __source SID__ - parent server
* __SID__ - [server ID](#entity-ids)
* __TS__ - current UNIX TS
* __name__ - server name
* __proto version__ - JELP protocol version (checked for compatibility)
* __version__ - IRCd or package version (not checked)
* __description__ - server description to show in `LINKS`, `MAP`, etc. This
  MUST be the last parameter, regardless of any additional parameters which may
  be added in between the `<version>` and `<description>` at a later date. If
  the description starts with the sequence `(H) ` (including the trailing
  space), the server should be marked as hidden

### SJOIN

Bursts a channel.

This command MUST be used for channel creation and during burst. It MAY be used
for existing channels as a means to grant status modes upon join.

Propagation: _broadcast_

```
:<SID> SJOIN <channel> <TS> <modes> ... :<user list>
```

* __SID__ - server bursting the channel
* __channel__ - channel being burst or created
* __TS__ - channel TS
* __modes__ - all channel modes besides statuses. each mode parameter is a
  separate parameter of the `SJOIN` command. if no modes are set, a single `+`
  must be present
* __user list__ - membership and status modes. this will always be the last
  parameter, regardless of any mode parameters before it. the format is a
  space-separated of `UID!modes`, where `modes` are the status modes that the
  user has in the channel. if a user has no modes, the `!` may be omitted

### SNOTICE

Propagates a server notice to remote opers.

Propagation: _broadcast_

```
[@from_user=] :<SID> SNOTICE <flag> :<message>
```

* __from_user__ - _optional_, user whose action resulted in this notice
* __SID__ - server producing the notice
* __flag__ - [server notice flag](../oper_notices.md)
* __message__ - notice text

### TOPIC

Propagates a channel topic change.

Propagation: _broadcast_

```
:<source> TOPIC <channel> <TS> <topic TS> :<topic text>
```

* __source__ - user or server setting the topic
* __channel__ - channel whose topic is being changed
* __TS__ - channel TS
* __topic TS__ - new topic TS
* __topic text__ - new topic text

If `<TS>` is older than the internal channel TS, reset all channel modes and
invitations.

Regardless of `<TS>`, set the topic and propagate it with the CURRENT channel
TS.

### TOPICBURST

Bursts a channel topic.

Propagation: _broadcast_

```
:<SID> TOPICBURST <channel> <TS> <set by> <topic TS> :<topic text>
```

* __SID__ - server bursting the topic
* __channel__ - channel whose topic is being burst
* __TS__ - channel TS
* __set by__ - server name or user mask that set the topic
* __topic TS__ - new topic TS
* __topic text__ - new topic text

Accept the topic and propagate if any of the following are true:
- the channel currently has no topic
- `<TS>` is older than the internal channel TS
- `<TS>` is equal to the internal channel TS and `<topic TS>` is newer than the
  internal topic TS
  
Otherwise, drop the message and do not propagate.

### UID

Introduces a user.

Propagation: _broadcast_

```
:<SID> UID <UID> <nick TS> <modes> <nick> <ident> <host> <cloak> <ip> :<realname>
```

* __SID__ - server to which the user belongs
* __UID__ - UID
* __nick TS__ - nick TS
* __modes__ - user modes in the perspective of `<SID>` (no parameters) or a
  single `+` if no modes are set
* __nick__ - nick
* __ident__ - ident/username
* __host__ - real canonical host
* __cloak__ - visible host
* __ip__ - IP address. must be prefixed with `0` if starts with `:`
* __realname__ - real name

### UMODE

Propagates a user mode change.

Propagation: _broadcast_

```
:<UID> UMODE <modes>
```

* __UID__ - user whose modes are to be changed
* __modes__ - mode string in the perspective of `<UID>` (no parameters)

### USERINFO

Propagates the changing of one or more user fields.

Propagation: _broadcast_

```
[@nick=][;nick_time=][;real_host=][;host=][;ident=][;account=] :<UID> USERINFO
```

* __nick__ - _optional_, new nick
* __nick time__ - _optional_, new nick time. MUST be present if `<nick>` is present
* __real_host__ - _optional_, new real canonical host
* __host__ - _optional_, new visible canonical host
* __ident__ - _optional_, new ident/username
* __account__ - _optional_, new account name or `*` for logout
* __UID__ - user whose fields should be changed

## Optional core commands

These commands SHOULD be implemented by servers when applicable, but failure to
do so will not substantially affect network continuity.

### ADMIN

Remote `ADMIN` request.

Propagation: _one-to-one_

### CONNECT

Remote `CONNECT`.

Propagation: _one-to-one_

### FJOIN

Forces a user to join a channel.

Propagation: _one-to-one_

### FLOGIN

Forces a user to login to an account.

Used by external services.

Propagation: _broadcast_

### FNICK

Forces a nick change.

Propagation: _one-to-one_

### FOPER

Forces an oper privilege change.

Propagation: _one-to-one_

### FPART

Forces a user to part a channel.

Propagation: _one-to-one_

### FUMODE

Forces a user mode change.

Propagation: _one-to-one_

### FUSERINFO

Forces the changing of one or more user fields.

### INFO

Remote `INFO` request.

Propagation: _one-to-one_

### INVITE

Invites a remove user to a channel.

Propagation: _one-to-one_

### KNOCK

Propagates a channel knock.

Propagation: _broadcast_

### LINKS

Remote `LINKS` request.

Propagation: _one-to-one_

### LOGIN

Propagates a user account login.

Propagation: _broadcast_

### LUSERS

Remote `LUSERS` request.

Propagation: _one-to-one_

### MOTD

Remote `MOTD` request.

Propagation: _one-to-one_

### REHASH

Remote `REHASH`.

Propagation: _one-to-one_

### TIME

Remote `TIME` request.

Propagation: _one-to-one_

### USERS

Remote `USERS` request.

Propagation: _one-to-one_

### VERSION

Remote `VERSION` request.

Propagation: _one-to-one_

### WHOIS

Remote `WHOIS` query.

Propagation: _one-to-one_

## Extension commands

These commands MAY be implemented by servers but are not required. They are not
part of the core JELP protocol implementation. If any unknown command is
received, servers MAY choose to produce a warning but SHOULD NOT terminate the
uplink.

### BAN

During burst, lists all known global ban identifiers and the times at which
they were last modified.

Propagation: _none_

### BANDEL

Propagates a global ban deletion.

Propagation: _broadcast_

### BANIDK

In response to [`BAN`](#ban) during burst, requests information for a ban the
receiving server is not familiar with.

Propagation: _none_

### BANINFO

Propagates a global ban.

Used upon adding a new ban and during burst in response to [`BANIDK`](#banidk).

Propagation: _broadcast_

### MODEREP

Reply for [`MODEREQ`](#modereq).

### MODEREQ

Initiates [MODESYNC](https://github.com/cooper/juno/issues/63).

### SASLDATA

Transmits data between a client and a remote SASL agent.

### SASLDONE

Indicates SASL completion.

### SASLHOST
### SASLMECHS
### SASLSET
### SASLSTART

Indicates SASL initiation.
