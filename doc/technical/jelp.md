# JELP

The __J__uno __E__xtensible __L__inking __P__rotocol (__JELP__) is the preferred
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

### Line endings

The traditional line ending `\r\n` (CRLF) is replaced simply by `\n` (LF);
however for easier adoption in legacy software, `\r` MUST be ignored if present.

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
@<name>=<value>;[<name2>=<value2> ...] :<source> <command> [<parameters> ...]
```

This is particularly useful for messages with optional parameters (as it reduces
overall message size when they are not present). More often, however, it is used
to introduce new data without breaking compatibility with existing
implementations.

This idea is borrowed from an extension of the IRC client protocol, IRCv3.2
[message-tags](http://ircv3.net/specs/core/message-tags-3.2.html). The JELP
implementation of message tags is compatible with that specification in all
respects.

## Connection setup

## Modes

## Core commands

## Extension commands

These commands MAY be implemented
