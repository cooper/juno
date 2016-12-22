# Modules

This is a (hopefully) complete list of the official modules packaged with the
juno-ircd repository. juno consists of
[under 30 lines](https://github.com/cooper/juno/blob/master/bin/ircd)
of standalone code. The
entire remainder consists of reloadable modules, all but one of which are
optional.

## Essentials

This category includes the barebones of the IRC server.

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

__Bases__ are modules which provide programming interfaces for adding commands,
modes, and other features. While they are not technically part of the Core
module namespace, each is a dependency of at least one core module.

* __Base::Capabilities__ - IRCv3 capability support.
* __Base::ChannelModes__ - channel mode support.
* __Base::Matchers__ - user mask matching support.
* __Base::OperNotices__ - server notice registration support.
* __Base::RegistrationCommands__ - registration command support.
* __Base::UserCommands__ - user command support.
* __Base::UserNumerics__ - numeric registration support.

## Basics

This category includes almost-essential modules.

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

This category includes modules providing optional channel features.

### Channel::Access

__Channel::Access__ provides a channel access list mode (+A). This is
particularly useful in the absence of an external service package. It also
provides built-in `UP` and `DOWN` commands.

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
    up
    down
    topicprepend
    topicappend
    mode
    eval
    lolcat
```

This list is in `default.conf` which should not be edited by users. To enable
or disable specific fantasy commands, add your own `[channels: fantasy]` block
to `ircd.conf`. Use the form `command = off` to explicitly disable a
fantasy command.

### Channel::Forward

__Channel::Forward__ provides a channel forward mode (+F). This allows
chanops to specify another channel to where users will be forwarded upon
failure to join the original channel.

In order to set a channel as the forward target of another, you must be an
op in _both_ channels. This prevents unwanted overflow.

Scenarios where one may be forwarded to another channel are when the channel
limit has been reached, the user is banned, or the channel is invite-only while
the user does not have a pending invitation.

### Channel::Invite

__Channel::Invite__ adds invite only (+i), free invite (+g), and invite
exception (+I) channel modes. It also adds the INVITE user command.

If a channel is marked as invite-only, users cannot join without an invitation
initiated by the INVITE command. An exception to this is if a mask matching the
user is in the invite exception list.

In order to use the INVITE command, a user has to have basic status in a channel
(typically halfop or higher). If free invite is enabled, however, any user can
use the INVITE command.

### Channel::Key

__Channel::Key__ adds channel keyword (+k) support.

When a channel keyword is set, users cannot join without providing the keyword
as a parameter to the JOIN command.

### Channel::Limit

__Channel::Limit__ adds channel user limit (+l) support.

When a limit is set, users cannot join if the channel is at capacity.

### Channel::ModeSync

__Channel::ModeSync__ offers improved channel mode synchronization.

Because mode
handling functionality is provided by modules, the IRCd cannot queue modes for
modules that might be loaded in the future. MODESYNC solves this problem by
providing a means of negotiation when new channel modes are dynamically
introduced to a server.

This module will seamlessly keep channel modes in sync globally upon the loading
and unloading of modules which add additional modes. It also adds the MODESYNC
user command which can be used to force a mode synchronization in the case of a
desync.

See [issue #63](https://github.com/cooper/juno/issues/63) for more information
on MODESYNC.

### Channel::Mute

__Channel::Mute__ adds a muteban channel mode (+Z).

Mutebans do not prevent users from joining the channel, but they do stop them
from sending PRIVMSGs and NOTICEs to the channel. Like normal bans, mutebans
can be overridden with voice or higher status.

### Channel::NoColor

__Channel::NoColor__ adds a channel mode which strips messages of mIRC color
codes (+c).

PRIVMSG and NOTICE messages containing mIRC color codes are not blocked when
this mode is enabled. Instead, the text is sent unformatted to other users in
the channel.

### Channel::OperOnly

__Channel::OperOnly__ adds a channel mode to prevent normal users from joining
channels marked as oper-only (+O). Channels marked as oper-only can only be
joined by IRC operators.

This mode can only be set by IRC operators.

### Channel::OpModerate

__Channel::OpModerate__ adds a channel mode which, if enabled, allows channel
operators to see PRIVMSG and NOTICE messages which would have otherwise been
blocked (+z).

This applies to mutebans, regular bans, channel moderation, and any other
condition which may have prevented a user from messaging the channel. When
this mode is enabled, the user sending the blocked message will NOT receive
an error reply to notify them that their message was blocked.

Only channel operators see the messages which would have been blocked. Other
users in the channel still cannot.

### Channel::Permanent

__Channel::Permanent__ provides a channel mode to mark channels as permanent
(+P).

If this mode is enabled, the channel and all of its metadata will be retained
even after the last user leaves. Normally channels are fully disposed of when
their names list becomes empty, but this mode prevents that from happening.

This mode can only be set by IRC operators with the
[`set_permanent`](oper_flags.md#set_permanent) flag.

### Channel::RegisteredOnly

__Channel::RegisteredOnly__ adds a channel mode to prevent unregistered users
from joining a channel marked as registered-only (+r).

This may be useful as an alternative to invite-only (+i) to prevent spambots
from entering the channel while still allowing verified users to join.

Users may be marked as registered by logging into IRC services. Without some
form of IRC services in use, this mode is probably useless.

### Channel::Secret

__Channel::Secret__ provides two channel modes for making channels more obscure:
secret (+s) and private (+p).

While these modes are similar, they do have minor differences. Both prevent
the channel from appearing in the LIST and NAMES commands for users which are
not in the channel being queried. However, only secret hides the channel from
WHOIS queries. Finally, private channels cannot be KNOCKed on, while secret ones
can.

|         | Show in LIST? | Show in NAMES? | Show in WHOIS? | Allow KNOCK? |
|---------|---------------|----------------|----------------|--------------|
| Secret  | No            | No             | No             | Yes          |
| Private | No            | No             | Yes            | No           |

See [issue #34](https://github.com/cooper/juno/issues/34) for more info.

### Channel::SSLOnly

__Channel::SSLOnly__ adds a channel mode which prevents users that did not
connect to the IRC server via a secure protocol from joining channels marked
as SSL-only (+z).

This may be considered useful if the contents of the channel are confidential
and you paranoid about raw network traffic sniffing. Note however that most IRC
networks use self-signed certificates which require users to set their clients
to not care to verify certificate authenticity. This would allow for
man-in-the-middle attacks.

### Channel::TopicAdditions

__Channel::TopicAdditions__ provides two user commands,
TOPICPREPEND and TOPICAPPEND, which make it easier to add new segments to the
channel topic.

These commands are offered by some external services packages, so the module is
often not useful when other services are present. It was created back when
juno did not support external services packages and relied on internal account
management in conjunction with the Channel::Access module.

The TOPICPREPEND command adds a new segment to the beginning of the topic.
Likewise, TOPICAPPEND adds a new segment to the end of the topic.

## Global ban support

This category includes modules providing or extending juno's network-wide
ban support.

### Ban

The __Ban__ module itself does not provide any type of ban. However, it provides
the common framework used for all global network bans. This includes the
programming interfaces for registering ban types, dealing with ban propagation,
expiring bans, and more.

The current Ban implementation is a major improvement over previous ones. It
allows modules to very easily add new types of bans with only a few lines of
code. Bans are represented by Ban::Info objects.

This module does provide one user command, BANS, which lists all global bans
or bans of the specified type. Its use requires the
[`list_bans`](oper_flags.md#list_bans) flag.

### Ban::Dline

__Ban::Dline__ adds global D-Line support.

D-Lines are a type of kill ban enforced on connections as soon as they are
established. Unlike K-Lines, D-Lines can be enforced before the hostname
and ident resolution processes are complete.

D-Lines are applied to IP address masks. They can be complete IP addresses or
partial addresses with POSIX-style wildcards; e.g. `123.456.789.*`.

Ban::Dline adds the DLINE and UNDLINE commands, both which require the
[`dline`](oper_flags.md#dline) oper flag.

### Ban::Kline

__Ban::Kline__ adds global K-Line support.

K-Lines are a type of kill ban enforced on users upon registration.

K-Lines are applied to `user@host` masks. They can be complete masks or
partial masks with POSIX-style wildcards; e.g. `*@microsoft.com`.

Ban::Kline adds the KLINE and UNKLINE commands, both which require the
[`kline`](oper_flags.md#kline) oper flag.

### Ban::Resv

__Ban::Resv__ adds global channel and nickname reservation support.

Unlike other ban types, reserves do not prevent connections to the server.
Instead, they are used to prohibit nicknames or channel names. Reserve masks
can be complete channel names or nicknames, or they can contain POSIX-style
wildcards; e.g. `bill*` or `#*sex*`.

Ban::Resv adds the RESV and UNRESV commands, both which require the
[`resv`](oper_flags.md#resv) oper flag.

## Server management

This category includes modules that make it easier for server administrators to
manage an IRC server or network.

### Configuration::Set

__Configuration::Set__ allows IRC operators to view and modify the server
configuration directly from IRC.

The CONFGET command 

### Eval

### Git

### Grant

### Modules

### Reload

## Extras

This category includes modules that are not enabled in the default
configuration because they may not appeal to the typical user.

### DNSBL

### LOLCAT