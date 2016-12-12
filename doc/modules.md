# Modules

## Basics

### ircd

The __ircd__ module does not have to be explicitly loaded from the
configuration. It is the one and only module which is loaded directly from the
executable `bin/ircd`.

This module contains the barebones of the IRC server. It does not provide any
commands or modes but only the most basic object structures and
socket/data transmission code.

__Submodules__ (all of which are automatically loaded)
* __channel__ - channel object and basic channel operations.
* __connection__ - connection object.
* __message__ - an object which represents an IRC message.
* __pool__ - singleton object which manages all IRC objects.
* __server__ - object representing an IRC server.
* __user__ - object representing an IRC user.
* __utils__ - useful utility functions used throughout the IRCd.

### Core

The set of Core modules includes all of the essential commands, modes, and
other features needed for the most basic configuration of an IRC server.

The primary __Core__ module itself does not provide any functionality. However,
it depends on several other core modules, providing a convenient way to load all
of these essential modules at once.

* __Core::ChannelModes__ - provides RFC/most basic channel modes.
* __Core::Matchers__ - provides basic RFC hostmask matching functionality.
* __Core::OperNotices__ - includes essential server notice formats.
* __Core::RegistrationCommands__ - essential user registration commands.
* __Core::UserCommands__ - essential user commands.
* __Core::UserModes__ - provides RFC/most basic user modes.
* __Core::UserNumerics__ - essential user numerics.

### Resolve

The __Resolve__ module provides asynchronous hostname resolving using the
system's buit-in resolving mechanisms.

### Ident

The __Ident__ module implements a client of the Ident protocol within the
IRC server. Upon the connection of a user, the server will attempt to identify
the user.

### Cloak

The __Cloak__ module provides a programming interface for user host cloaking.
Each cloaking implementation is a submodule of the main Cloak module. Currently
only one implementation exists: Cloak::Charybdis. This submodule provides a
[charybdis](https://github.com/charybdis-ircd/charybdis)-compatible cloaking
schema.

As submodules cannot be loaded directly, a configuration option will determine
the preferred cloaking schema as new implementations become available. Currently
the Cloak module is hard-coded to load Cloak::Charybdis, so no configuration is
needed beyond enabling the Cloak module.

### Alias

The __Alias__ module provides user command aliases. The module reads from the
`[aliases]` configuration block and registers user commands for each of them.

In these definitions, parameters are represented by `$N` (the Nth parameter)
and `$N-` (the Nth parameter and all which follow it).

Below is an excerpt of the default alias configuration.

```
[ aliases ]

    nickserv  = 'PRIVMSG NickServ $1-'
    chanserv  = 'PRIVMSG ChanServ $1-'
    operserv  = 'PRIVMSG OperServ $1-'
    botserv   = 'PRIVMSG BotServ $1-'
    groupserv = 'PRIVMSG GroupServ $1-'

    ns = 'PRIVMSG NickServ $1-'
    cs = 'PRIVMSG ChanServ $1-'
    os = 'PRIVMSG OperServ $1-'
    bs = 'PRIVMSG BotServ $1-'
    gs = 'PRIVMSG GroupServ $1-'
```

### SASL

The SASL module provides SASL authentication support through external services.

Each server-to-server protocol SASL implementation exists in the form of a
submodule.

__Submodules__ (loaded automatically as needed)
* __SASL::JELP__ - provides the JELP SASL implementation.
* __SASL::TS6__ - provides the TS6 SASL implementation.

### JELP

The set of JELP modules comprise the Juno Extensible Linking protocol
implementation. This is the preferred protocol to be used when linking juno-ircd
to other instances of juno-ircd.

The primary __JELP__ module itself does not provide any functionality. However,
it depends on several other modules, providing a convenient way to load the
entire JELP implementation at once.

* __JELP::Base__ - provides the programming interfaces for registering JELP
  commands. This is a dependency of all modules which transmit data via JELP.
* __JELP::Incoming__ - provides handlers for the standard set of JELP commands.
* __JELP::Outgoing__ - provides outgoing command constructors for the standard
  set of JELP commands.
* __JELP::Registration__ - provides essential JELP registration commands.

### TS6

The set of TS6 modules comprise the TS6 linking protocol implementation. These
modules allow juno-ircd to establish connections with IRC servers and running
different software, as well as many IRC services packages.

When linking juno-ircd to other instances of juno-ircd, the Juno Extensible
Linking Protocol (JELP) is preferred over TS6.

The primary __TS6__ module itself does not provide any functionality. However,
it depends on several other modules, providing a convenient way to load the
entire TS6 implementation at once.

juno-ircd's TS6 implementation is [thoroughly documented](ts6.md).

* __TS6::Base__ - provides the programming interfaces for registering TS6
  commands. This is a dependency of all modules which transmit data via TS6.
* __TS6::Incoming__ - provides handlers for the standard set of TS6 commands.
* __TS6::Outgoing__ - provides outgoing command constructors for the standard
  set of TS6 commands.
* __TS6::Registration__ - provides essential TS6 registration commands.
* __TS6::Utils__ - includes a number of utilities used throughout the TS6
  implementation, particularly for the translation of internal identifiers to
  those in the TS format.

## Channel features

### Channel::Access

__Channel::Access__ provides a channel access list mode (default +A). This is
particularly useful in the absence of an external service package.

To automatically set mode `o` on any user matching the mask `*!*@google.com`
```
MODE #googleplex +A o:*!*@google.com
```

To view the channel access list
```
MODE #googleplex A
```

There is no requirement that masks in the access list are in the standard IRC
POSIX-like format. They can also include any extmasks or other user matchers
provided by modules. For example the following example utilitzes the `$r`
extmask to auto-owner any users logged into the services account `mitch`.

```
MODE #k +A q:$r:mitch
```

### Channel::Fantasy

__Channel::Fantasy__ allows channel-related user commands to be used as fantasy
commands. Fantasy commands are sent as normal PRIVMSGs to the channel prefixed
with the exclamation point (`!`).

```
<mad> !kick GL
* GL (GLolol@overdrivenetworks.com) has been kicked from #k by mad
<mad> !part
* mad (mitch@test) has left #k
```

Fantasy support is enabled and disabled on a per-command basis with the
`[channels: fantasy]` configuration block. The default set of commands which
support fantasy are as follows:

```
[ channels: fantasy ]

    kick
    topic
    part
    names
    modelist
    up                                          # any of these fantasy commands can be
    down                                        # disabled from the normal conf with:
    topicprepend                                # [ channels: fantasy ]
    topicappend                                 #      <command> = off
    mode
    eval
    lolcat
```

This list is in `default.conf` which should not be edited by users. To enable
or disable specific fantasy commands, add your own `[channels: fantasy]` block
to `ircd.conf`. Use the form `command = off` to explicitly disable a
fantasy command.

### Channel::Forward

### Channel::Invite

### Channel::Key

### Channel::Limit

### Channel::ModeSync

### Channel::Mute

### Channel::NoColor

### Channel::OperOnly

### Channel::OpModerate

### Channel::Permanent

### Channel::RegisteredOnly

### Channel::Secret

### Channel::SSLOnly

### Channel::TopicAdditions

## Global ban support

### Ban

### Ban::Dline

### Ban::Kline

### Ban::Resv

## Bases

### Base::Capabilities

### Base::ChannelModes

### Base::Matchers

### Base::OperNotices

### Base::RegistrationCommands

### Base::UserCommands

### Base::UserNumerics

## Server management

### Configuration::Set

### Eval

### Git

### Grant

### Modules

### Reload

###

## Extras

### DNSBL

### LOLCAT
