# JELP

The Juno Extensible Linking Protocol (__JELP__) is the preferred
server linking protocol for juno-to-juno links. As of writing, the only known
implementation to exist is that of juno itself, but future applications may
choose to implement JELP for better compatibility with juno.

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
identifiers as the source of commands in place of user masks and server names.
This idea is borrowed from other server linking protocols such as [TS6](ts6.md);
it aims to diminish the effects of name collisions.

* __SID__ - A server identifier. This is numerical (consisting of digits 0-9).

* __UID__ - A user identifier. This consists of ASCII letters (a-z, A-Z),
prefixed by the numerical SID to which the user belongs. It is case-sensitive.

Unlike in other linking protocols, user and server identifiers in JELP are of
arbitrary length but limited to 16 bytes. Servers SHOULD NOT use the prefix on
UIDs to determine which server a user belongs to.

### Message tags

Some messages have named parameters called tags. The format is as follows:
```
@<name>=<value>[;<name2>=<value2> ...] :<source> <command> [<parameters> ...]
```

This is particularly useful for messages with optional parameters (as it reduces
overall message size when they are not present). More often, however, it is used
to introduce new data without breaking compatibility with existing
implementations.

This idea is borrowed from an extension of the IRC client protocol, IRCv3.2
[message-tags](http://ircv3.net/specs/core/message-tags-3.2.html). The JELP
implementation of message tags is compatible with that specification in all
respects, except that the IRCv3 limitation of 512 bytes does not apply.

## Connection setup

## Modes

JELP does not have predefined mode letters. Before any mode strings are sent
out, servers MUST send the [`AUM`](#aum) and [`ACM`](#acm) commands to map mode
letters and types to their names. Servers SHOULD track the mode mappings of all
other servers on the network, even for unrecognized mode names.

Throughout this documentation, commands involving mode strings will mention a
_perspective_, which refers to the server whose mode letter mappings should be
used in the parsing of the mode string.

Below are the lists of mode names, their types, and their usual associated
letters. Servers MAY implement any or all of them but MUST quietly ignore any
incoming modes they do not recognize.

* [User modes](../umodes.md)
* [Channel modes](../cmodes.md)

## Required core commands

These commands MUST be implemented by servers. Failure to do so may result in
network discontinuity.

### ACM

Maps channel mode letters and types to mode names.

### AUM

Maps user mode letters to mode names.

### AWAY

Marks a user as away.

### BURST

Sent to indicate the start of a burst.

### CMODE

Channel mode change.

### ENDBURST

Sent to indicate the end of a burst.

### JOIN

Channel join. Used when a user joins an existing channel with no status modes.

See also [`SJOIN`](#sjoin).

### KICK

Propagates a channel kick. Removes a user from a channel.

### KILL

Temporarily removes a user from the network.

### NICK

Propagates a nick change.

### NOTICE

Like [`PRIVMSG`](#privmsg).

### NUM

Sends a numeric reply to a remote user.

### OPER

Propagates oper privileges.

The setting of the `ircop` user mode (+o) is used to indicate that a user has
opered-up; this command may be used to modify their permissions list.

### PART

Propagates a channel part.

### PARTALL

Used when a user leaves all channels.

This is initiated on the client protocol with the `JOIN 0` command.

### PING

Verifies uplink reachability.

### PONG

Reply for [`PING`](#ping).

### PRIVMSG

Sends a message to a remote target.

### QUIT

Propagates a user quit.

### SAVE

Used to resolve nick collisions without casualty.

### SID

Introduces a server.

### SJOIN

Bursts a channel.

This command MUST be used for channel creation and during burst. It MAY be used
for existing channels as a means to grant status modes upon join.

### SNOTICE

Propagates a server notice to remote opers.

### TOPIC

Propagates a channel topic change.

### TOPICBURST

Bursts a channel topic.

### UID

Introduces a user.

### UMODE

Propagates a user mode change.

### USERINFO

Propagates the changing of one or more user fields.


## Optional core commands

These commands SHOULD be implemented by servers when applicable, but failure to
do so will not substantially affect network continuity.

### ADMIN

Remote `ADMIN` request.

### CONNECT

Remote `CONNECT`.

### FJOIN

Forces a user to join a channel.

### FLOGIN

Forces a user to login to an account.

Used by external services.

### FNICK

Forces a nick change.

### FOPER

Forces an oper privilege change.

### FPART

Forces a user to part a channel.

### FUMODE

Forces a user mode change.

### FUSERINFO

Forces the changing of one or more user fields.

### INFO

Remote `INFO` request.

### INVITE

Invites a remove user to a channel.

### KNOCK

Propagates a channel knock.

### LINKS

Remote `LINKS` request.

### LOGIN

Propagates a user account login.

### LUSERS

Remote `LUSERS` request.

### MOTD

Remote `MOTD` request.

### REHASH

Remote `REHASH`.

### TIME

Remote `TIME` request.

### USERS

Remote `USERS` request.

### VERSION

Remote `VERSION` request.

### WHOIS

Remote `WHOIS` query.

## Extension commands

These commands MAY be implemented by servers but are not required. They are not
part of the core JELP protocol implementation. If any unknown command is
received, servers MAY choose to produce a warning but SHOULD NOT terminate the
uplink.

### BAN

During burst, lists all known global ban identifiers and the times at which
they were last modified.

### BANDEL

Propagates a global ban deletion.

### BANIDK

In response to [`BAN`](#ban) during burst, requests information for a ban the
receiving server is not familiar with.

### BANINFO

Propagates a global ban.

Used upon adding a new ban and during burst in response to [`BANIDK`](#banidk).

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
