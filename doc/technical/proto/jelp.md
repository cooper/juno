# JELP

The Juno Extensible Linking Protocol (__JELP__) is the preferred
server linking protocol for juno-to-juno links.

As of writing, the only implementation known to exist is that of juno itself,
but future applications may choose to implement JELP for better compatibility
with juno.

This document is to be used as reference when implementing IRC servers and
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
have to be directly connected.

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
   - [`MLOCK`](#mlock) - bursts mode lock
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

* [User modes](../../umodes.md)
* [Channel modes](../../cmodes.md)

## Required core commands

These commands MUST be implemented by servers. Failure to do so will result in
network discontinuity.

### ACM

Maps channel mode letters and types to mode names.

[Propagation](#propagation): _broadcast_

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

[Propagation](#propagation): _broadcast_

```
:<SID> AUM <name>:<letter> [<more modes> ...]
```

* __SID__ - server these mode mappings belong to
* __name__ - mode name
* __letter__ - mode letter

### AWAY

Marks a user as away.

[Propagation](#propagation): _broadcast_

```
:<UID> AWAY [:<reason>]
```

* __UID__ - user to mark as away
* __reason__ - _optional_, reason for being away. if omitted, the user is
  returning from away state

### BURST

Sent to indicate the start of a burst.

This is used for the initial burst as well as the bursts of other descendant
servers introduced later.

The corresponding [`ENDBURST`](#endburst) terminates the burst.

[Propagation](#propagation): _broadcast_

```
:<SID> BURST <TS>
```

* __SID__ - server bursting
* __TS__ - current UNIX TS

### CMODE

Channel mode change.

[Propagation](#propagation): _conditional broadcast_

```
:<source> CMODE <channel> <TS> <perspective> <modes> [<parameters> ...]
```

* __source__ - user or server committing the mode change
* __channel__ - channel to change modes on
* __TS__ - channel TS
* __perspective__ - mode perspective server
* __modes__ - mode changes. each mode parameter is a
  separate parameter of the command

If `<TS>` is newer than the internal channel TS, drop the message and do not
propagate it.

Otherwise, accept and propagate the incoming modes.

### ENDBURST

Sent to indicate the end of a burst.

[Propagation](#propagation): _broadcast_

```
:<SID> ENDBURST <TS>
```

* __SID__ - server whose burst has ended
* __TS__ - current UNIX TS

Upon receiving, the server should send its own [burst](#burst) if it has not
already.

### JOIN

Channel join. Used when a user joins an existing channel with no status modes.

[Propagation](#propagation): _broadcast_

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

[Propagation](#propagation): _broadcast_

```
:<source> KICK <channel> <target UID> :<reason>
```

* __source__ - user or server committing the kick
* __channel__ - channel to remove the target user from
* __target UID__ - user to remove
* __reason__ - kick comment

### KILL

Temporarily removes a user from the network.

[Propagation](#propagation): _broadcast_

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

[Propagation](#propagation): _broadcast_

```
:<UID> NICK <nick> <nick TS>
```

* __UID__ - user changing nicks
* __nick__ - new nick
* __nick TS__ - new nick TS

### NOTICE

To the extent that concerns JELP, equivalent to [`PRIVMSG`](#privmsg) in all
ways other than the command name.

[Propagation](#propagation): _conditional_

### NUM

Sends a numeric reply to a remote user.

[Propagation](#propagation): _one-to-one_

```
:<SID> NUM <UID> <num> :<message>
```

* __SID__ - source server
* __UID__ - target user (determines propagation)
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

[Propagation](#propagation): _broadcast_

```
:<UID> OPER [-]<flag> [<flag> ...]
```

* __UID__ - user whose privileges are to be changed
* __flag__ - any number of [oper flags](../../oper_flags.md) may be added or
  removed in a single message, each as a separate parameter. those being removed
  are prefixed by `-`; those being added have no prefix

### PART

Propagates a channel part.

[Propagation](#propagation): _broadcast_

```
:<UID> PART <channel> :<reason>
```

* __UID__ - user to be removed
* __channel__ - channel to remove the user from

### PARTALL

Used when a user leaves all channels.

This is initiated on the client protocol with the `JOIN 0` command.

[Propagation](#propagation): _broadcast_

```
:<UID> PARTALL
```

* __UID__ - user to be removed from all channels

### PASS

During [registration](#connection-setup), sends the connection password.

[Propagation](#propagation): _none_

```
PASS <password>
```

* __password__ - connection password in plain text

See [connection setup](#connection-setup).

### PING

Verifies uplink reachability.

[Propagation](#propagation): _none_

```
PING <message>
```

* __message__ - some data which will also be present in the
  corresponding [`PONG`](#pong)

### PONG

Reply for [`PING`](#ping).

[Propagation](#propagation): _none_

```
:<SID> PONG <message>
```

* __SID__ - server replying to the PING
* __message__ - data which was specified in the corresponding [`PING`](#ping)

### PRIVMSG

Sends a message.

[Propagation](#propagation): _conditional_

```
:<source> PRIVMSG <target> :<message>
```

* __source__ - user or server sending the message
* __target__ - message target, see below
* __message__ - message text

`<target>` can be any of the following:

- a user
  - [Propagation](#propagation): _one-to-one_
- a channel
  - [Propagation](#propagation): all servers with non-deaf users on the channel
- `@` followed by a status mode letter and a channel name, to message all users
  on the channel with that status or higher
  - [Propagation](#propagation): all servers with -D users of appropriate status
  - Example: `@o#channel` - all users on #channel with `+o` or higher
- `=` followed by a channel name, to send to channel ops only, for
  [op moderation](../../modules.md#channelopmoderate)
  - [Propagation](#propagation): all servers with -D channel ops
- a `user@server.name` message, to send to users on a specific server. the exact
  meaning of the part before the `@` is not prescribed, except that "opers"
  allows IRC operators to send to all IRC operators on the server in an
  unspecified format. this can also be used for more secure communications to
  external services
- a message to all users on server names matching a mask (`$$` followed by mask)
  - [Propagation](#propagation): _broadcast_
  - Only allowed to IRC operators
- a message to all users with hostnames matching a mask (`$#` followed by mask)
  - Unimplemented
  - [Propagation](#propagation): _broadcast_
  - Only allowed to IRC operators

### QUIT

Propagates a user or server quit.

[Propagation](#propagation): _broadcast_

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

[Propagation](#propagation): _none_

```
READY
```

See [connection setup](#connection-setup).

### SAVE

Used to resolve nick collisions without casualty.

[Propagation](#propagation): _broadcast_

```
:<SID> SAVE <UID> <nick TS>
```

* __SID__ - server saving the user
* __UID__ - user to be saved
* __nick TS__ - user's nick TS, as known by the saving server

If the user target already has their UID as their nick or `<nick TS>` does not
match the internal nick TS, drop the message and do not propagate.

Otherwise, change the user's nickname to their UID, set their nick TS to 100,
and propagate the message.

### SERVER

During [registration](#connection-setup), introduces the server.

[Propagation](#propagation): _none_

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

[Propagation](#propagation): _broadcast_

```
:<source SID> SID <SID> <name> <proto version> <version> <TS> :<description>
```

* __source SID__ - parent server
* __SID__ - [server ID](#entity-ids)
* __name__ - server name
* __proto version__ - JELP protocol version (checked for compatibility)
* __version__ - IRCd or package version (not checked)
* __TS__ - current UNIX TS
* __description__ - server description to show in `LINKS`, `MAP`, etc. This
  MUST be the last parameter, regardless of any additional parameters which may
  be added in between the `<TS>` and `<description>` at a later date. If
  the description starts with the sequence `(H) ` (including the trailing
  space), the server should be marked as hidden

### SJOIN

Bursts a channel.

This command MUST be used for channel creation and during burst. It MAY be used
for existing channels as a means to grant status modes upon join.

[Propagation](#propagation): _broadcast_

```
:<SID> SJOIN <channel> <TS> <modes> [<parameters> ...] :<user list>
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

If the channel does not exist, create it.

Otherwise:

If `<TS>` is older than the internal channel TS, clear all modes and invites,
accept new modes and statuses, and forward as-is.

If `<TS>` is equal to the current internal channel TS, accept new modes and
statuses and forward as-is.

If `<TS>` is newer than the current internal channel TS, disregard modes and
statuses and forward the message without them.

In any case, add the listed users to the channel.

### SNOTICE

Propagates a server notice to remote opers.

[Propagation](#propagation): _broadcast_

```
[@from_user=] :<SID> SNOTICE <flag> :<message>
```

* __from_user__ - _optional_, user whose action resulted in this notice
* __SID__ - server producing the notice
* __flag__ - [server notice flag](../../oper_notices.md)
* __message__ - notice text

### TOPIC

Propagates a channel topic change.

[Propagation](#propagation): _broadcast_

```
:<source> TOPIC <channel> <TS> <topic TS> :<topic text>
```

* __source__ - user or server setting the topic
* __channel__ - channel whose topic is being changed
* __TS__ - channel TS
* __topic TS__ - new topic TS
* __topic text__ - new topic text

Regardless of `<TS>`, set the topic and propagate it with the CURRENT channel
TS.

### TOPICBURST

Bursts a channel topic.

[Propagation](#propagation): _broadcast_

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

[Propagation](#propagation): _broadcast_

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

[Propagation](#propagation): _broadcast_

```
:<UID> UMODE <modes>
```

* __UID__ - user whose modes are to be changed
* __modes__ - modes in the perspective of `<UID>` (no parameters)

### USERINFO

Propagates the changing of one or more user fields.

[Propagation](#propagation): _broadcast_

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

[Propagation](#propagation): _one-to-one_

```
:<UID> ADMIN <server>
```

* __UID__ - user making the request
* __server__ - server name or `$`-prefixed SID (determines propagation)

### CONNECT

Remote `CONNECT`.

[Propagation](#propagation): _one-to-one_

```
:<source> CONNECT <mask> <server>
```

* __source__ - user or server initiating the CONNECT
* __mask__ - parameter for CONNECT command. this may be an absolute server name
  or a mask matching zero or more servers
* __server__ - server name or `$`-prefixed SID (determines propagation)

### FJOIN

Forces a user to join a channel.

[Propagation](#propagation): _one-to-one_

```
:<SID> FJOIN <UID> <channel> [<TS>]
```

* __SID__ - server committing the force join
* __UID__ - user to force to join (determines propagation)
* __channel__ - channel to force the user to join
* __TS__ - _optional_, channel TS

If `<TS>` is provided, the channel must exist, and the internal channel TS
must match the provided one. If this is not the case, drop the message. The
server must handle the request as though it were a normal JOIN message from the
client, taking bans and other restrictions into account.

If `<TS>` is omitted, the join should be forced regardless of whether the
channel is preexisting or has restrictions to prevent the user from joining.

In either case, if the join was successful, the server must acknowledge the
join with either [`SJOIN`](#sjoin) (if the channel was just created) or
[`JOIN`](#join) (otherwise).

### FLOGIN

Forces a user to login to an account.

Used by external services.

[Propagation](#propagation): _broadcast_

```
:<SID> FLOGIN <UID> <account>
```

* __SID__ - server forcing the login
* __UID__ - user to force to login
* __account__ - name of the account

Unlike other force commands, `FLOGIN` cannot fail and therefore does not need to
be acknowledged.

### FNICK

Forces a nick change.

[Propagation](#propagation): _one-to-one_

```
:<SID> FNICK <UID> <new nick> <new nick TS> <old nick TS>
```

* __SID__ - server forcing the nick change
* __UID__ - user whose nick should be changed (determines propagation)
* __new nick__ - new nick
* __new nick TS__ - new nick TS
* __old nick TS__ - old nick TS

If `<old nick TS>` is not equal to the internal nick TS, drop the message.

Otherwise, if the new nick is already in use by an unregistered connection,
cancel registration and drop that connection.

If the new nick is already in use by a user, kill the user.

Update the nick and nick TS and acknowledge the change by broadcasting a
[`NICK`](#nick) message to all servers including the one which issued `FNICK`.

### FOPER

Forces an oper privilege change.

[Propagation](#propagation): _one-to-one_

```
:<SID> FOPER <UID> [-]<flag> [<flag> ...]
```

* __SID__ - server forcing the privilege change
* __UID__ - user whose privileges will be changed (determines propagation)
* __flag__ - any number of [oper flags](../../oper_flags.md) may be added or
  removed in a single message, each as a separate parameter. those being removed
  are prefixed by `-`; those being added have
  
Update the flags and acknowledge the change by broadcasting an
[`OPER`](#oper) message to all servers including the one which issued `FOPER`.
  
### FPART

Forces a user to part a channel.

[Propagation](#propagation): _one-to-one_

```
:<SID> FPART <UID> <channel> <TS> [:<reason>]
```

* __SID__ - server forcing the user to part
* __UID__ - user to force to part (determines propagation)
* __TS__ - channel TS
* __reason__ - _optional_, part reason

Commit the mode change and acknowledge it by broadcasting a
[`PART`](#part) message to all servers including the one which issued `FPART`.

### FUMODE

Forces a user mode change.

[Propagation](#propagation): _one-to-one_

```
:<SID> FUMODE <UID> <modes>
```

* __SID__ - server forcing the mode change
* __UID__ - user whose modes should be changed (determines propagation)
* __modes__ - modes in the perspective of `<UID>` (no parameters)

Remove the user from the channel and acknowledge the change by broadcasting a
[`UMODE`](#umode) message to all servers including the one which issued
`FUMODE`.

### FUSERINFO

Forces the changing of one or more user fields.

Propagation: _one-to-one_

See [`USERINFO`](#userinfo) for fields.

The receiver may accept or reject any of the changes. Acknowledge those which
were accepted with a [`USERINFO`](#userinfo) message broadcast to all servers
including the one which issued `FUSERINFO`.

### INFO

Remote `INFO` request.

[Propagation](#propagation): _one-to-one_

```
@for= :<UID> INFO
```

* __for__ - server target (determines propagation)
* __UID__ - user committing the request

### INVITE

Invites a remove user to a channel.

[Propagation](#propagation): _one-to-one_

```
:<UID> INVITE <target UID> <channel>
```

* __UID__ - user offering the invitation
* __target UID__ - user to be invited (determines propagation)
* __channel__ - channel to which the user should be invited

`<channel>` does not necessarily have to exist, but servers MAY silently discard
invitations to nonexistent channels to prevent spam.

### KNOCK

Propagates a channel knock.

[Propagation](#propagation): _broadcast_

```
:<UID> KNOCK <channel>
```

* __UID__ - user knocking
* __channel__ - channel to knock on

### LINKS

Remote `LINKS` request.

[Propagation](#propagation): _one-to-one_

```
@for= :<UID> LINKS
```

* __for__ - server target (determines propagation)
* __UID__ - user committing the request

### LOGIN

Propagates a user account login.

[Propagation](#propagation): _broadcast_

```
:<UID> LOGIN <account info>
```

* __UID__ - user to login
* __account info__ - comma-separated account info. the format is unspecified
  except that the first field is always the account name

Currently, `<account info>` is only the account name. In previous built-in
account mechanisms, other data was also sent. For compatibility in case a future
account mechanism makes use of other fields, the account name should be
extracted as the sequence terminated by either `,` or the end of the string.

### LUSERS

Remote `LUSERS` request.

[Propagation](#propagation): _one-to-one_

```
@for= :<UID> LUSERS
```

* __for__ - server target (determines propagation)
* __UID__ - user committing the request

### MLOCK

Sets a channel mode lock.

```
:<source> MLOCK <channel> <TS> <modes> [<parameters> ...]
```

* __source__ - user or server committing the mode lock
* __channel__ - channel to lock the modes on
* __TS__ - channel TS
* __modes__ - _optional_, modes to lock. each mode parameter is a separate
parameter of the command. for status modes, the parameter should be the mask
which is locked. for all other modes with parameters, the parameter value does
not matter but must be present. `*` is used as a filler

If `<TS>` is newer than the internal channel TS, drop the message and do not
propagate it.

Otherwise, if `<modes>` is omitted, unset the current mode lock and propagate
the message with the current channel TS.

Otherwise, set the mode lock locally and propagate the message with the current
channel TS and the mode string exactly as it was received.

### MOTD

Remote `MOTD` request.

[Propagation](#propagation): _one-to-one_

```
:<UID> MOTD <server>
```

* __UID__ - user committing the request
* __server__ - server name or `$`-prefixed SID (determines propagation)

### REHASH

Remote `REHASH`.

[Propagation](#propagation): _server mask_

```
:<UID> REHASH <mask>
```

* __UID__ - user committing the request
* __mask__ - server mask target. all matching servers will respond
  (determines propagation)

### TIME

Remote `TIME` request.

[Propagation](#propagation): _one-to-one_

```
:<UID> TIME <server>
```

* __UID__ - user committing the request
* __server__ - server name or `$`-prefixed SID (determines propagation)

### USERS

Remote `USERS` request.

[Propagation](#propagation): _one-to-one_

```
@for= :<UID> USERS
```

* __for__ - server target (determines propagation)
* __UID__ - user committing the request

### VERSION

Remote `VERSION` request.

[Propagation](#propagation): _one-to-one_

```
:<UID> VERSION <server>
```

* __UID__ - user committing the request
* __server__ - server name or `$`-prefixed SID (determines propagation)

### WHOIS

Remote `WHOIS` query.

[Propagation](#propagation): _one-to-one_

```
@for= :<UID> WHOIS <target UID>
```

* __for__ - server target (determines propagation)
* __UID__ - user committing the request
* __target UID__ - user whose information is being requested

## Extension commands

These commands MAY be implemented by servers but are not required. They are not
part of the core JELP protocol implementation. If any unknown command is
received, servers MAY choose to produce a warning but SHOULD NOT terminate the
uplink.

### BAN

During burst, lists all known global ban identifiers and the times at which
they were last modified.

[Propagation](#propagation): _none_

### BANDEL

Propagates a global ban deletion.

[Propagation](#propagation): _broadcast_

### BANIDK

In response to [`BAN`](#ban) during burst, requests information for a ban the
receiving server is not familiar with.

[Propagation](#propagation): _none_

### BANINFO

Propagates a global ban.

Used upon adding a new ban and during burst in response to [`BANIDK`](#banidk).

[Propagation](#propagation): _broadcast_

### MODEREP
### MODEREQ

Used for [MODESYNC](https://github.com/cooper/juno/issues/63).

### SASLDATA
### SASLDONE
### SASLHOST
### SASLMECHS
### SASLSET
### SASLSTART

Used for SASL authentication.
