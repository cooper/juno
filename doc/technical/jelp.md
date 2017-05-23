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
### AUM
### AWAY
### BURST
### CMODE
### ENDBURST
### JOIN
### KICK
### KILL
### NICK
### NOTICE
### NUM
### OPER
### PART
### PARTALL
### PING
### PRIVMSG
### QUIT
### SAVE
### SID
### SJOIN
### SNOTICE
### TOPIC
### TOPICBURST
### UID
### UMODE
### USERINFO

## Optional core commands

These commands SHOULD be implemented by servers, but failure to do so will not
substantially affect network continuity.

### FJOIN
### FLOGIN
### FNICK
### FOPER
### FPART
### FUMODE
### FUSERINFO
### INVITE
### KNOCK
### LINKS
### LOGIN
### WHOIS

## Extension commands

These commands MAY be implemented by servers but are not required. They are not
part of the core JELP protocol implementation. If any unknown command is
received, servers MAY choose to produce a warning but SHOULD NOT terminate the
uplink.
