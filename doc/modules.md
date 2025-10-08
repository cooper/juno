# Modules

This is a complete list of the official modules packaged with the
juno repository. juno consists of
[under 30 lines](https://github.com/cooper/juno/blob/master/bin/ircd)
of standalone code. The
entire remainder consists of reloadable modules, all but [one](#ircd) of which
are optional.

Module                                              | Provides
---------------------------                         | ----------------------------
[ircd](#ircd)                                       | IRC objects and socket management
[Core](#core)                                       | Core IRC client protocol
[Resolve](#resolve)                                 | Hostname resolution
[Ident](#ident)                                     | Ident resolution
[Cloak](#cloak)                                     | Hostname cloaking
[Alias](#alias)                                     | Command aliases
[SASL](#sasl)                                       | Simple Authentication and Security Layer
[JELP](#jelp)                                       | Juno Extensible Linking Protocol
[TS6](#ts6)                                         | TS6 server linking protocol
[Channel::Access](#channelaccess)                   | Built-in channel access list (+A)
[Channel::Fantasy](#channelfantasy)                 | Channel fantasy commands
[Channel::Forward](#channelforward)                 | Channel forwarding (+f, +F, +Q)
[Channel::Invite](#channelinvite)                   | Channel invitations (`INVITE`, +i, +I, +g)
[Channel::JoinThrottle](#channeljoin)               | Channel join throttle (+j)
[Channel::Key](#channelkey)                         | Channel keyword (+k)
[Channel::Knock](#channelknock)                     | Channel knocking (`KNOCK`)
[Channel::LargeList](#channellargelist)             | Channel list mode limit increase (+L)
[Channel::Limit](#channellimit)                     | Channel user limit (+l)
[Channel::ModeSync](#channelmodesync)               | Channel mode synchronization (`MODESYNC`)
[Channel::Mute](#channelmute)                       | Channel mutes (+Z)
[Channel::NoColor](#channelnocolor)                 | Channel message color stripping (+c)
[Channel::OperOnly](#channeloperonly)               | Channel oper-only restriction (+O)
[Channel::OpModerate](#channelopmoderate)           | Channel op moderation (+z)
[Channel::Permanent](#channelpermanent)             | Channel permanence (+P)
[Channel::RegisteredOnly](#channelregisteredonly)   | Channel registered only restriction (+r)
[Channel::Secret](#channelsecret)                   | Channel secret and private (+s, +p)
[Channel::SSLOnly](#channelsslonly)                 | Channel SSL-only restriction (+S)
[Channel::TopicAdditions](#channeltopicadditions)   | Channel topic extras (`TOPICPREPEND`, `TOPICAPPEND`)
[Ban](#ban)                                         | Global netban interface (`BANS`)
[Ban::Dline](#bandline)                             | D-Lines: bans on IP addresses (`DLINE`, `UNDLINE`)
[Ban::Kline](#bankline)                             | K-Lines: bans on user masks (`KLINE`, `UNKLINE`)
[Ban::Resv](#banresv)                               | Reserves: bans on nickname masks and channels (`RESV`, `UNRESV`)
[Configuration::Set](#configurationset)             | Manage configuration from IRC (`CONFGET`, `CONFSET`)
[Eval](#eval)                                       | Evaluate Perl code from IRC (`EVAL`)
[Git](#git)                                         | Manage Git repository from IRC (`UPDATE`, `CHECKOUT`)
[Grant](#grant)                                     | Manage oper privileges from IRC (`GRANT`, `UNGRANT`)
[Modules](#modules-1)                               | Manage modules from IRC (`MODLOAD`, `MODUNLOAD`, `MODRELOAD`, `MODULES`)
[Monitor](#monitor)                                 | Client availability notifications (`MONITOR`)
[Reload](#reload)                                   | Reload the entire server code from IRC (`RELOAD`)
[Setname](#setname)                                 | IRCv3 SETNAME extension (`SETNAME`)
[DNSBL](#dnsbl)                                     | Built-in DNS blacklist checking
[LOLCAT](#lolcat)                                   | SPEEK LIEK A LOLCATZ (`LOLCAT`)
[Utf8Only](#utf8only)                               | Enforces UTF-8 encoding on the network

# Essentials

This category includes the barebones of the IRC server.

## ircd

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

## Core

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
module namespace, most are dependencies of at least one core module.

* __Base::AddUser__ - virtual user interface.
* __Base::Capabilities__ - IRCv3 capability support.
* __Base::ChannelModes__ - channel mode support.
* __Base::Matchers__ - user mask matching support.
* __Base::OperNotices__ - server notice registration support.
* __Base::RegistrationCommands__ - registration command support.
* __Base::UserCommands__ - user command support.
* __Base::UserNumerics__ - numeric registration support.

# Basics

This category includes almost-essential modules.

## Resolve

The __Resolve__ module provides asynchronous hostname resolving using the
system's buit-in resolving mechanisms.

## Ident

The __Ident__ module implements a client of the Ident protocol within the
IRC server. Upon the connection of a user, the server will attempt to identify
the user.

## Cloak

The __Cloak__ module provides a programming interface for user host cloaking.
Each cloaking implementation is a submodule of the main Cloak module. Currently
only one implementation exists: Cloak::Charybdis. This submodule provides a
[charybdis](https://github.com/charybdis-ircd/charybdis)-compatible cloaking
schema.

As submodules cannot be loaded directly, a configuration option will determine
the preferred cloaking schema as new implementations become available. Currently
the Cloak module is hard-coded to load Cloak::Charybdis, so no configuration is
needed beyond enabling the Cloak module.

## Alias

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

## SASL

The **SASL** module provides Simple Authentication and Security Layer
support through external services.

Each server-to-server protocol SASL implementation exists in the form of a
submodule.

__Submodules__ (loaded automatically as needed)
* __SASL::JELP__ - provides the JELP SASL implementation.
* __SASL::TS6__ - provides the TS6 SASL implementation.

Clients authenticate via SASL using the **`AUTHENTICATE`** command. This
command is only available to clients that have enabled the `sasl` capability.

```
AUTHENTICATE <mechanism>
```
```
AUTHENTICATE <data>
```
* __mechanism__ - the authentication method to be used.
* __data__ - some data to transmit to the SASL agent.

Example session:
```
S: :k.notroll.net NOTICE * :*** Looking up your hostname...
S: :k.notroll.net NOTICE * :*** Checking ident...
S: :k.notroll.net NOTICE * :*** Couldn't resolve your hostname
S: :k.notroll.net NOTICE * :*** No ident response
C: CAP LS 302
C: NICK mitch
C: USER mitch * * :mitch
S: :k.notroll.net CAP * LS :away-notify chghost sasl userhost-in-names
C: CAP REQ :sasl
S: :k.notroll.net CAP * ACK :sasl
C: AUTHENTICATE PLAIN
S: AUTHENTICATE +
C: AUTHENTICATE amlsbGVzAGppbGxlcwBzZXNhbWU=
S: :k.notroll.net 900 mitch mitch!mitch@notroll.net mitch :You are now logged in as mitch
S: :k.notroll.net 903 mitch :SASL authentication successful
C: CAP END
S: :k.notroll.net 001 mitch :Welcome to the NoTrollPLzNet IRC Network mitch
```

[SASL reauthentication](http://ircv3.net/specs/extensions/sasl-3.2.html#sasl-reauthentication)
is also supported.

## JELP

The set of __JELP__ modules comprise the Juno Extensible Linking protocol
implementation. This is the preferred protocol to be used when linking juno
to other instances of juno.

The primary JELP module itself does not provide any functionality. However,
it depends on several other modules, providing a convenient way to load the
entire JELP implementation at once.

* __JELP::Base__ - provides the programming interfaces for registering JELP
  commands. This is a dependency of all modules which transmit data via JELP.
* __JELP::Incoming__ - provides handlers for the standard set of JELP commands.
* __JELP::Outgoing__ - provides outgoing command constructors for the standard
  set of JELP commands.
* __JELP::Registration__ - provides essential JELP registration commands.

## TS6

The set of TS6 modules comprise the TS6 linking protocol implementation. These
modules allow juno to establish connections with IRC servers running
different software, as well as many IRC services packages.

When linking juno to other instances of juno, the Juno Extensible
Linking Protocol (JELP) is preferred over TS6.

The primary __TS6__ module itself does not provide any functionality. However,
it depends on several other modules, providing a convenient way to load the
entire TS6 implementation at once.

juno's TS6 implementation is [thoroughly documented](ts6.md).

* __TS6::Base__ - provides the programming interfaces for registering TS6
  commands. This is a dependency of all modules which transmit data via TS6.
* __TS6::Incoming__ - provides handlers for the standard set of TS6 commands.
* __TS6::Outgoing__ - provides outgoing command constructors for the standard
  set of TS6 commands.
* __TS6::Registration__ - provides essential TS6 registration commands.
* __TS6::Utils__ - includes a number of utilities used throughout the TS6
  implementation, particularly for the translation of internal identifiers to
  those in the TS format.

# Channel features

This category includes modules providing optional channel features.

## Channel::Access

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
provided by modules. For example the following example utilizes the `$r`
extmask to auto-owner any users logged into the services account `mitch`.

```
MODE #k +A q:$r:mitch
```

**`UP`** grants you all the permissions that apply to you
```
UP <channel>
```
* __channel__: the channel to apply your status modes in.

**`DOWN`** removes all of your channel privileges.
```
DOWN <channel>
```
* __channel__: the channel where your status modes will be removed.

## Channel::Fantasy

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

## Channel::Forward

__Channel::Forward__ provides a channel forward mode (+f). This allows
chanops to specify another channel to where users will be forwarded upon
failure to join the original channel.


In order to set a channel as the forward target of another, you must be an
op in _both_ channels. This prevents unwanted overflow.

The free forward mode (+F) allows non-ops to set the channel as a forward
target of another channel. The no forward mode (+Q) disallows forwarding
to the channel regardless of any other factors.

Scenarios where one may be forwarded to another channel are when the channel
limit has been reached, the user is banned, or the channel is invite-only while
the user does not have a pending invitation.

## Channel::Invite

__Channel::Invite__ adds invite only (+i), free invite (+g), and invite
exception (+I) channel modes. It also adds the **INVITE** user command.

```
INVITE <nick> <channel>
```
* __nick__ - the nickname of the user you wish to invite.
* __channel__ - the channel to which the user will be invited.

If a channel is marked as invite-only, users cannot join without an invitation
initiated by the INVITE command. An exception to this is if a mask matching the
user is in the invite exception list.

In order to use the INVITE command, a user has to have basic status in a channel
(typically halfop or higher). If free invite is enabled, however, any user can
use the INVITE command.

Note that, in addition to politely asking a user to join, invitations can also
override certain restrictions which could have otherwise prevented a user from
joining such as user limit (+l), keyword (+k), and join throttle (+j).

## Channel::JoinThrottle

__Channel::JoinThrottle__ adds a channel join rate limit (+j).

The format for the mode is `joins:period` or `joins:period:locktime`.
* __joins__: the max number of joins that can occur in _period_ seconds.
* __period__: the amount of time, in seconds, in which _joins_ joins can occur.
* __locktime__: _optional_, how long, in seconds, to lock the channel when
  the throttle is activated. defaults to 60 seconds.

Example which locks the channel for one minute if more than 5 joins occur
within a ten-second time lapse.
```
MODE #k +j 5:10
```

Example which locks the channel for 30 seconds if more than 3 joins occur
within a five-second time lapse.
```
MODE #k +j 3:5:30
```

## Channel::Key

__Channel::Key__ adds channel keyword (+k) support.

When a channel keyword is set, users cannot join without providing the keyword
as a parameter to the `JOIN` command.

```
JOIN <channel> [<keyword>]
```

An invitation to the channel permits the user to join without the keyword.

## Channel::Knock

__Channel::Knock__ allows users to "knock" on restricted channels. This
notifies chanops that the user would appreciate an invitation.

The **KNOCK** command can be used on channels with any of these modes:
invite only (+i), keyword (+k), user limit (+l). However, if the channel is
private (+p), knocking is never permitted.
```
KNOCK <channel>
```
* __channel__ - the channel you would like an invitation to.


## Channel::LargeList

__Channel::LargeList__ adds support for large lists (+L).

It increases the maximum number of entries for list modes to the value set by
[`channels:max_list_entries_large`](config.md#channel-options).

This mode can only be set by IRC operators with the
[`set_large_banlist`](oper_flags.md#set_large_banlist) flag.

## Channel::Limit

__Channel::Limit__ adds channel user limit (+l) support.

When a limit is set, users cannot join if the channel is at capacity. An
invitation to the channel can override this.

## Channel::ModeSync

__Channel::ModeSync__ offers improved channel mode synchronization.

Because mode
handling functionality is provided by modules, the IRCd cannot queue modes for
modules that might be loaded in the future. MODESYNC solves this problem by
providing a means of negotiation when new channel modes are dynamically
introduced to a server.

This module will seamlessly keep channel modes in sync globally upon the loading
and unloading of modules which add additional modes.

The module also adds the **MODESYNC** user command which can be used to force a
mode synchronization in the rare case of a desync. This requires the `modesync`
oper flag.
```
MODESYNC <channel>
```
* __channel__ - the channel where a desync was spotted.

See [issue #63](https://github.com/cooper/juno/issues/63) for more information
on MODESYNC.

## Channel::Mute

__Channel::Mute__ adds a muteban channel mode (+Z).

Mutebans do not prevent users from joining the channel, but they do stop them
from sending PRIVMSGs and NOTICEs to the channel. Like normal bans, mutebans
can be overridden with voice or higher status.

To add a mask to the mute list
```
MODE #apple +Z bill!*@microsoft.com
```

To view the channel mute list
```
MODE #apple Z
```

## Channel::NoColor

__Channel::NoColor__ adds a channel mode which strips messages of mIRC color
codes (+c).

PRIVMSG and NOTICE messages containing mIRC color codes are not blocked when
this mode is enabled. Instead, the text is sent unformatted to other users in
the channel.

## Channel::OperOnly

__Channel::OperOnly__ adds a channel mode to prevent normal users from joining
channels marked as oper-only (+O). Channels marked as oper-only can only be
joined by IRC operators.

Moreover, this mode can only be set by IRC operators.

## Channel::OpModerate

__Channel::OpModerate__ adds a channel mode which, if enabled, allows channel
operators to see PRIVMSG and NOTICE messages which would have otherwise been
blocked (+z).

This applies to mutebans, regular bans, channel moderation, and almost any other
condition which may have prevented a user from messaging the channel. When
this mode is enabled, the user sending the blocked message will NOT receive
an error reply to notify them that their message was blocked.

Only channel operators see the messages which would have been blocked. Other
users in the channel still cannot.

## Channel::Permanent

__Channel::Permanent__ provides a channel mode to mark channels as permanent
(+P).

If this mode is enabled, the channel and all of its metadata will be retained
even after the last user leaves. Normally channels are fully disposed of when
their names list becomes empty, but this mode prevents that from happening.

This mode can only be set by IRC operators with the
[`set_permanent`](oper_flags.md#set_permanent) flag.

## Channel::RegisteredOnly

__Channel::RegisteredOnly__ adds a channel mode to prevent unregistered users
from joining a channel marked as registered-only (+r).

This may be useful as an alternative to invite-only (+i) to prevent spambots
from entering the channel while still allowing verified users to join. As such,
an invitation allows unregistered users to join.

Users may be marked as registered by logging into IRC services. Without some
form of IRC services in use, this mode is probably useless.

## Channel::Secret

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

## Channel::SSLOnly

__Channel::SSLOnly__ adds a channel mode which prevents users that did not
connect to the IRC server via a secure protocol from joining channels marked
as SSL-only (+z).

This may be considered useful if the contents of the channel are confidential
and you paranoid about raw network traffic sniffing. Note however that most IRC
networks use self-signed certificates which require users to set their clients
to not care to verify certificate authenticity. This would allow for
man-in-the-middle attacks.

## Channel::TopicAdditions

__Channel::TopicAdditions__ provides two user commands,
TOPICPREPEND and TOPICAPPEND, which make it easier to add new segments to the
channel topic.

These commands are offered by some external services packages, so the module is
often not useful when other services are present. It was created back when
juno did not support external services packages and relied on internal account
management in conjunction with the Channel::Access module.

**`TOPICPREPEND`** adds a new segment to the beginning of the topic.
```
TOPICPREPEND <channel> :<text>
```
* __channel__ - the channel whose topic will be updated.
* __text__ - the text which will be prepended to the existing topic.

Likewise, **`TOPICAPPEND`** adds a new segment to the end of the topic.
```
TOPICAPPEND <channel> :<text>
```
* __channel__ - the channel whose topic will be updated.
* __text__ - the text which will be appended to the existing topic.

# Global ban support

This category includes modules providing or extending juno's network-wide
ban support.

## Ban

The __Ban__ module itself does not provide any type of ban. However, it provides
the common framework used for all global network bans. This includes the
programming interfaces for registering ban types, dealing with ban propagation,
expiring bans, and more.

The current Ban implementation is a major improvement over previous ones. It
allows modules to very easily add new types of bans with only a few lines of
code. Bans are represented by Ban::Info objects.

This module does provide one user command, **`BANS`**, which lists all global
bans or bans of the specified type. Its use requires the
[`list_bans`](oper_flags.md#list_bans) flag.

## Ban::Dline

__Ban::Dline__ adds global D-Line support.

D-Lines are a type of kill ban enforced on connections as soon as they are
established. Unlike K-Lines, D-Lines can be enforced before the hostname
and ident resolution processes are complete.

D-Lines are applied to IP address masks. They can be complete IP addresses or
partial addresses with POSIX-style wildcards; e.g. `123.456.789.*`.

Ban::Dline adds the DLINE and UNDLINE commands, both which require the
[`dline`](oper_flags.md#dline) oper flag.

**`DLINE`** adds a D-Line.
```
DLINE <duration> <ip> <reason>
```
* __ip__ - the IP address to deny connections from. wildcards accepted.
* __duration__ - how long until the ban expires. `0` for permanent.
* __reason__ - a comment to display to users that justifies the ban.

**`UNDLINE`** removes a D-Line.
```
UNDLINE <ip>
```
* __ip__ - the IP address or mask to unban.

## Ban::Kline

__Ban::Kline__ adds global K-Line support.

K-Lines are a type of kill ban enforced on users upon registration.

K-Lines are applied to `user@host` masks. They can be complete masks or
partial masks with POSIX-style wildcards; e.g. `*@microsoft.com`.

Ban::Kline adds the KLINE and UNKLINE commands, both which require the
[`kline`](oper_flags.md#kline) oper flag.

**`KLINE`** adds a K-Line.
```
KLINE <duration> <mask> <reason>
```
* __mask__ - the `user@host` mask to deny users from. wildcards accepted.
* __duration__ - how long until the ban expires. `0` for permanent.
* __reason__ - a comment to display to users that justifies the ban.

**`UNKLINE`** removes a K-Line.
```
UNKLINE <mask>
```
* __mask__ - the `user@host` mask to unban.

## Ban::Resv

__Ban::Resv__ adds global channel and nickname reservation support.

Unlike other ban types, reserves do not prevent connections to the server.
Instead, they are used to prohibit nicknames or channel names. Reserves can be
applied to complete channel names or nickname masks; e.g. `bill*` or `#sex`.

Ban::Resv adds the RESV and UNRESV commands, both which require the
[`resv`](oper_flags.md#resv) oper flag.

**`RESV`** adds a reserve.
```
RESV <duration> <mask> <reason>
```
* __mask__ - an absolute channel name or nickname mask to reserve. wildcards are
  accepted for nickname masks only.
* __duration__ - how long until the reserve expires. `0` for permanent.
* __reason__ - a comment that justifies the reserve.

**`UNRESV`** removes a reserve.
```
UNRESV <mask>
```
* __mask__ - an absolute channel name or nickname mask to unreserve. wildcards
  are accepted for nickname masks only.

# Server management

This category includes modules that make it easier for server administrators to
manage an IRC server or network.

## Configuration::Set

__Configuration::Set__ allows IRC operators to view and modify the server
configuration directly from IRC.

Each configuration option can located using the form:
* `block_type/block_name/key`       (for named blocks)
* `block_type/key`                  (for unnamed blocks)

Values are encoded in these formats:
* __Number__ - `0`
* __String__ - `"it's some text"`
* __List__ - `[ 1, 2, "text" ]`
* __Map__ - `{ "key": "value", "other": "another" }`
* __Boolean__ - `on` or `off`
* __Null__ - `undef`

**`CONFGET`** fetches and displays the current configuration value at a
specified location. Requires the `confget` oper flag.
```
CONFGET <server_mask> <location>
```
* __server_mask__ - an absolute server name or server name mask with wildcards.
  all matching servers will respond to the request.
* __location__ - the location of the desired configuration value. see above.

**`CONFSET`** overwrites the current configuration value at the specified
location. Requires the `confset` oper flag.
```
CONFSET <server_mask> <location> <value>
```
* __server_mask__ - an absolute server name or server name mask with wildcards.
  all matching servers will respond to the request.
* __location__ - the location of the desired configuration value. see above.
* __value__ - the desired value in Evented::Configuration format. see above.

The responses to both of these commands will display the value at the given
location. For remote servers, the server name will appear after the value, so
that you know which server the reply belongs to.

## Eval

Provides the **`EVAL`** command, which allows you to evaluate some Perl code.
```
EVAL [<channel>] <code>
```
* __channel__ - _optional_, a channel to where the results should be sent. if
  omitted, the user receives the results as server notices. note that the
  fantasy command can be used within channels.
* __code__ - some Perl code to evaluate.

This module should not be loaded on a production server. It shouldn't even
be loaded on a test server if you don't know what you're doing.

The `EVAL` command does not require an oper flag. Instead, the name of the
accepted opers must appear in `etc/evalers.conf`, one per line.

It is also possible to evaluate multiple lines of code using `BLOCK..END`:
```
10:33:18 PM <~mitch> !eval BLOCK
10:33:48 PM <~mitch> !eval if (3 > 2) {
10:33:53 PM <~mitch> !eval    "yes"
10:33:55 PM <~mitch> !eval }
10:33:56 PM <~mitch> !eval END
10:33:57 PM Result: yes
```

**Convenience functions**
* `nick()`: returns the user associated with the provided nickname.
* `serv()`: returns all servers whose names match the provided mask.
* `chan()`: returns the channel associated with the provided channel name.
* `Dump()`: returns the Data::Dumper output for the provided arg
  (Maxdepth = 1).

## Git

Provides two commands for managing the IRCd git repository:
`UPDATE` and `CHECKOUT`.

**`UPDATE`** runs `git pull` and `git submodule update`. This updates the local
repository from the remote. Requires the `update` oper flag.
```
UPDATE [<server_mask>]
```
* __server_mask__ - _optional_, an absolute server name or server name mask with
  wildcards. all matching servers will respond to the request. defaults to
  the local server.

**`CHECKOUT`** runs `git checkout` in order to switch between branches and such.
This is particularly useful when upgrading from one stable release to the next.
Requires the `checkout` oper flag.
```
CHECKOUT [<server_mask>] <branch/tag/commit>
```
* __server_mask__ - _optional_, an absolute server name or server name mask with
  wildcards. all matching servers will respond to the request. defaults to
  the local server.
* __branch/tag/commit__ - what you wish to check out; e.g. `juno12-mihret`.

## Grant

Allows the dynamic addition and removal of oper permissions directly from IRC.

**`GRANT`** applies privileges to a user. Note that, if the target user
is remote, the remote server may choose to silently reject the grant request,
depending on the uplink privileges. Requires the `grant` oper flag.
```
GRANT <nick> <flag> [<flag> ...]
```
* __nick__ - the nickname of the target user.
* __flag__ - an oper flag to be granted. any number of flags can be provided in
  a space-separated list.

**`UNGRANT`** does the opposite. Requires the `grant` oper flag.
```
UNGRANT <nick> <flag> [<flag> ...]
```
* __nick__ the nickname of the target user.
* __flag__ - an oper flag to be revoked. any number of flags can be provided in
  a space-separated list.

Note that by giving an oper the `grant` flag, you are essentially giving him
complete and total control over the IRC server, as he could easily grant
himself all oper flags.

## Modules

**Modules** allows the dynamic loading and unloading of server modules
directly from IRC.

**`MODLOAD`** attempts to load a module. Requires the `modules` oper flag.
```
MODLOAD <mod_name>
```
* __mod_name__ - the name of the module to be loaded.

**`MODUNLOAD`** attempts to unload a module. Requires the `modules` oper flag.
```
MODUNLOAD <mod_name>
```
* __mod_name__ - the name of the module to be unloaded.

**`MODRELOAD`** attempts to reload a module. Requires the `modules` oper flag.
```
MODRELOAD <mod_name>
```
* __mod_name__ - the name of the module to be reloaded.

**`MODULES`** lists information about the loaded server modules. This command
is available to all users.
```
MODULES
```
Example response
```
10:53:54 PM   SASL 7.1
10:53:54 PM       Provides SASL authentication
10:53:54 PM       REGISTRATION COMMANDS
10:53:54 PM           AUTHENTICATE
10:53:54 PM       CAPABILITIES
10:53:54 PM           sasl
10:53:54 PM       USER NUMERICS
10:53:54 PM           ERR_SASLABORTED, ERR_SASLALREADY, ERR_SASLFAIL
10:53:54 PM           ERR_SASLTOOLONG, RPL_SASLMECHS, RPL_SASLSUCCESS
```

## Monitor

**Monitor** provides a mechanism by which users can subscribe to client
availability notifications. Its intention is to replace the legacy `ISON` query.
This implementation complies with the
[IRCv3.2 monitor specification](http://ircv3.net/specs/core/monitor-3.2.html).

The module adds one command, MONITOR, which itself has a number of subcommands.

**`MONITOR +`** adds one or more nicknames to the monitor list.
```
MONITOR + <nick>[,<nick2> ...]
```
* __nick__ - the nickname to watch for. multiple nicknames can be provided at
  once, separated by commas.

**`MONITOR -`** removes one or more nicknames from your monitor list.
```
MONITOR - <nick>[,<nick2> ...]
```
* __nick__ - the nickname to stop watching for. multiple nicknames can be
  provided at once, separated by commas.

**`MONITOR L`** displays the current monitor list.
```
MONITOR L
```

**`MONITOR C`** clears the current monitor list.
```
MONITOR C
```

**`MONITOR S`** resynchronizes the current monitor list with the client.
```
MONITOR S
```

## Reload

**Reload** allows you to reload the entire IRCd code without restarting the
server or dropping any connections. It is often used in conjunction with
`UPDATE` and/or `CHECKOUT` provided by the [Git](#git) module.

There is always *some* risk when using **`RELOAD`**. However, it is usually
successful, especially when you have checked out a stable release. The command
is useful both for test servers on devel branches and on production servers that
have checked out stable releases. Requires the `reload` oper flag.
```
RELOAD [<verbosity>] [<server_mask>]
```

* __verbosity__ - _optional_, verbosity flag.
  'v' for verbose or 'd' for debug. note that debug output is extremely lengthy.
* __server_mask__ - _optional_, an absolute server name or server name mask with
  wildcards. all matching servers will respond to the request. defaults to
  the local server.

It is also possible to check out a past version and perform a downgrade. This
may be useful as a temporary solution to revert back to a version before a
significant bug was introduced.

# Extras

This category includes non-essential modules that may not appeal to all users.

## Setname

**Setname** provides the IRCv3 SETNAME extension, allowing users to change their
real name (GECOS) after connecting.

**`SETNAME`** allows a user to change their real name.
```
SETNAME :<new real name>
```
* __new real name__ - the new real name to set.

The SETNAME command requires the `setname` capability to be enabled. When a user
changes their real name, all other users with the `setname` capability enabled
will be notified of the change.

This extension follows the [IRCv3 setname specification](https://ircv3.net/specs/extensions/setname).

## DNSBL

**DNSBL** provides built-in blacklist checking. It supports both IPv4 and IPv6.

You can have any number of blacklists in your configuration. They are configured
in the following format:
```
[ dnsbl: EFnetRBL ]

    host     = "rbl.efnetrbl.org"
    ipv4     = on
    ipv6     = off
    timeout  = 3
    duration = '1d'
    reason   = "Your host is listed on EFnet RBL. See http://efnetrbl.org/?i=%ip"
```

* __host__ - the hostname of the blacklist. the reversed incoming connection
  address will be prepended to it before performing a DNS query.
* __ipv4__ - _optional_, true if the blacklist supports IPv4.
* __ipv6__ - _optional_, true if the blacklist supports IPv6.
* __timeout__ - _optional_, number of seconds before giving up each query related
  to this blacklist. higher numbers are more effective but may slow the
  registration proccess, especially if the blacklist is at a high load. defaults
  to three seconds.
* __duration__ - _optional_, how long to remember offending IP addresses. if not
  provided, DNSBL caching is disabled.
* __reason__ - _optional_, a human-readable reason for terminating offending
  connections. all instances of `%ip` are replaced with the IP address.

## LOLCAT

**LOLCAT** ALLOWS YOO T SPEKK LIKES AN LOLCATZ.

TEH **`LOLCAT`** COMMAN CAN BE USED TO SEN TRANSLAYTED MESSUJ 2 CHANNEL.
```
LOLCAT <CHANNEL> <MESSUJ>
```

TEH TRANSLAYTED MESSUJ WILL ALSO BE ECHOD BACK 2 TEH SOURCE USR.

## Utf8Only

**Utf8Only** enforces UTF-8 encoding on the network by validating all incoming
messages from clients. Enabling it is preferred for modern IRC clients.

When this module is loaded, all incoming messages are validated to ensure they
contain valid UTF-8. If a message contains invalid UTF-8, it will be modified
to remove or replace the invalid sequences, and the client will receive a warning
notification.

The module adds `UTF8ONLY` to the server's `RPL_ISUPPORT` tokens to indicate that
UTF-8 encoding is enforced on the network.

This helps maintain consistent character encoding across the network and prevents
encoding-related display issues.
