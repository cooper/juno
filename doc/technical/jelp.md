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
(for example '\*', '\*.example.com', 'irc.example.com'). Those servers do not
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
:<SID> BURST <ts>
```

* __SID__ - server bursting
* __ts__ - current UNIX timestamp

### CMODE

Channel mode change.

Propagation: _conditional broadcast_

```
:<source> CMODE <channel> <ts> :<modes>
```

* __source__ - UID or SID commiting the mode change
* __channel__ - channel to change modes on
* __ts__ - channel timestamp
* __modes__ - mode string, in the perspective of `<source>`

If `<ts>` is newer than the internal timestamp, drop the message and do not
propagate it.

If `<ts>` is older than the internal timestamp, accept and propagate the
incoming modes, resetting all previous channel modes and invitations.

If `<ts>` is equal to the internal timestamp, accept and propagate the incoming
modes.

Note that the entire mode string is a single parameter.

### ENDBURST

Sent to indicate the end of a burst.

Propagation: _broadcast_

```
:<SID> ENDBURST <ts>
```

* __SID__ - server whose burst has ended
* __ts__ - current UNIX timestamp

Upon receiving, the server should send its own [burst](#burst) if it has not
already.

### JOIN

Channel join. Used when a user joins an existing channel with no status modes.

Propagation: _broadcast_

```
:<UID> JOIN <channel> <ts>
```

* __UID__ - user joining the channel
* __channel__ - channel being joined
* __ts__ - channel timestamp

If `<channel>` does not exist, create it. This should not happen though.

If `<ts>` is older than the internal timestamp, reset all channel modes and
invitations.

Regardless of `<ts>`, add the user to the channel and propagate it.

See also [`SJOIN`](#sjoin).

### KICK

Propagates a channel kick. Removes a user from a channel.

Propagation: _broadcast_

### KILL

Temporarily removes a user from the network.

Propagation: _broadcast_

### NICK

Propagates a nick change.

Propagation: _broadcast_

### NOTICE

Like [`PRIVMSG`](#privmsg).

Propagation: _conditional_

### NUM

Sends a numeric reply to a remote user.

Propagation: _one-to-one_

### OPER

Propagates oper privileges.

The setting of the `ircop` user mode (+o) is used to indicate that a user has
opered-up; this command may be used to modify their permissions list.

Propagation: _broadcast_

### PART

Propagates a channel part.

Propagation: _broadcast_

### PARTALL

Used when a user leaves all channels.

This is initiated on the client protocol with the `JOIN 0` command.

Propagation: _broadcast_

### PASS

During [registration](#connection-setup), sends the connection password.

Propagation: _none_

### PING

Verifies uplink reachability.

Propagation: _none_

### PONG

Reply for [`PING`](#ping).

Propagation: _none_

### PRIVMSG

Sends a message to a remote target.

Propagation: _conditional_

### QUIT

Propagates a user quit.

Propagation: _broadcast_

### READY

Sent to indicate that the initiator should send its [burst](#burst).

Propagation: _none_

### SAVE

Used to resolve nick collisions without casualty.

Propagation: _broadcast_

### SERVER

During [registration](#connection-setup), introduces the server.

Propagation: _none_

### SID

Introduces a server.

Propagation: _broadcast_

### SJOIN

Bursts a channel.

This command MUST be used for channel creation and during burst. It MAY be used
for existing channels as a means to grant status modes upon join.

Propagation: _broadcast_

### SNOTICE

Propagates a server notice to remote opers.

Propagation: _broadcast_

### TOPIC

Propagates a channel topic change.

Propagation: _broadcast_

### TOPICBURST

Bursts a channel topic.

Propagation: _broadcast_

### UID

Introduces a user.

Propagation: _broadcast_

### UMODE

Propagates a user mode change.

Propagation: _broadcast_

### USERINFO

Propagates the changing of one or more user fields.

Propagation: _broadcast_

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
