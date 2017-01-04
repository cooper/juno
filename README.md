# juno

Yes.  
It really is an IRC daemon.  
It's written in Perl.  

...  

You can breathe again.  
There. Very good.  

# Introduction

This is juno-ircd, a seriously modern IRC server daemon written from scratch
in the Perl programming language. Really.

> Perl is the right language for IRC. IRC is chock full of various strings and
> other what not, all of which is easily parsed by Perl, where the C IRC daemons
> jump through all kinds of hoops and have really nasty looking code (have you
> ever looked at the Undernet IRC daemon?) Whereas this is, in my opinion, very
> clean.

This software will hopefully surprise you with its novel features and
functionality. It's super easy to install and even comes with a working
configuration, so go ahead and [try it already](#installation).

Come chat with us at [irc.notroll.net #k](irc://irc.notroll.net/k) too.

## Features

There are a lot! But here are some things that make juno-ircd stand out.

You can

* Upgrade an entire network without restarting any servers.
* Check out the latest version from git via IRC, even remotely.
* Modify server configuration dynamically from IRC, even remotely.
* Link a complex network of various IRCds spanning multiple server protocols.
* Write modules for the easy-to-use and event-based module API.
* Or rather, [beg us](irc://irc.notroll.net/k) to add the features you want.

Plus, juno-ircd

* Is free and open-source.
* Is written in Perl, making it fun and easy to tinker with.
* Is extensively configurable.
* Despite that, ships with a working configuration and runs out-of-the-box.
* Consists entirely of [modules](doc/modules.md) and therefore can be as minimal
  or as bloated as you're comfortable with.
* Supports the latest [IRCv3](http://ircv3.net) standards.
* Supports multiple linking protocols, including several
  [TS6 implementations](doc/ts6.md)
  and a custom user-extensible protocol.
* Supports [Atheme](http://atheme.net),
  [PyLink](https://github.com/GLolol/PyLink) and probably other IRC services
  packages.

## Concepts

* __Eventedness__: The core unifying policy of juno-ircd is the excessive use of
events. It is the fundamental and single most important concept in mind
throughout the IRCd. Any operation that occurs can be represented as an event,
and anywhere it may seem useful for something to respond, an event exists and is
fired. This functionality is provided by
[Evented::Object](https://github.com/cooper/evented-object),
a showcase project that is the base of every class within the IRCd.

```perl
# user events.
if (my $user = $connection->user) {
    push @events, $user->events_for_message($msg);
}

# if it's a server, add the $PROTO_message events.
elsif (my $server = $connection->server) {
    my $proto = $server->{link_type};
    push @events, [ $server, "${proto}_message"        => $msg ],
                  [ $server, "${proto}_message_${cmd}" => $msg ];
    $msg->{_physical_server} = $server;
}

# fire with safe option.
my $fire = $connection->prepare(@events)->fire('safe');
```

* __Extensibility__: Through the use of events and other mechanisms,
extensibility is another important guideline around which juno is designed. It
should not be assumed that any commands, modes, prefixes, etc. are permanent or
definite. They should be changeable and replaceable, and it should be possible
for more to be added with ease.

```
[ modes: user ]

    ircop         = 'o'               # IRC operator                      (o)
    invisible     = 'i'               # invisible mode                    (i)
    ssl           = 'z'               # SSL connection                    (z)
    registered    = 'r'               # registered - Account module       (r)


[ modes: channel ]

    no_ext        = [0, 'n']          # no external channel messages      (n)
    protect_topic = [0, 't']          # only operators can set the topic  (t)
    invite_only   = [0, 'i']          # you must be invited to join       (i)
    moderated     = [0, 'm']          # only voiced and up may speak      (m)
    ban           = [3, 'b']          # channel ban                       (b)
    except        = [3, 'e']          # ban exception                     (e)
    invite_except = [3, 'I']          # invite-only exception             (I)
    access        = [3, 'A']          # Channel::Access module list mode  (A)
    limit         = [2, 'l']          # Channel user limit mode           (l)

[ prefixes ]

    owner  = ['q', '~',  2]           # channel owner                     (q)
    admin  = ['a', '&',  1]           # channel administrator             (a)
    op     = ['o', '@',  0]           # channel operator                  (o)
    halfop = ['h', '%', -1]           # channel half-operator             (h)
    voice  = ['v', '+', -2]           # voiced channel member             (v)
```

* __Modularity__: By responding to events, [modules](doc/modules.md) add new
features and functionality to the IRCd. Without them, juno is made up of
[under thirty lines](https://github.com/cooper/juno/blob/master/bin/ircd) of
Perl code. Everything else is within a module. Modules communicate and work
together to create a single functioning body whose parts can be added, removed,
and modified dynamically. This functionality is provided by the
[Evented::API::Engine](https://github.com/cooper/evented-api-engine),
a class which provides an interface for loading and managing modules while
automatically tracking their event callbacks.

![Modularity](http://i.imgur.com/EHOfEyS.png)

* __Upgradability__: The beauty of Perl's malleable symbol table makes it
practical for an entire piece of software to be upgraded or reloaded without
restarting it. With the help of the Evented::API::Engine and modularity as a
central principle, juno aims to do exactly that. With just one command, you can
jump up ten versions, all without your users disconnecting.

![Upgradability](http://i.imgur.com/LJiVAnX.png)

* __Configurability__: Very few values are hard coded. Some have default values,
but nearly everything is configurable. There's little reason to make limitations
on what can and cannot be changed. Loads of configurable options make it easy to
set the server up exactly as you please. In spite of that, the basic
configuration is minimal and easy-to-follow. This is made possible by
[Evented::Configuration](https://github.com/cooper/evented-configuration).
Real-time modification of the configuration is also feasible, thanks to
[Evented::Database](https://github.com/cooper/evented-database).

```
[ ping: user ]
    message   = 'Ping timeout'  
    frequency = 30              
    timeout   = 120         

[ listen: 0.0.0.0 ]
    port    = [6667..6669, 7000]
    sslport = [6697]
    ts6port = [7050]

[ listen: :: ]
    port    = [6667..6669, 7000]
    sslport = [6697]
    ts6port = [7050]

[ ssl ]
    cert = 'etc/ssl/cert.pem'   
    key  = 'etc/ssl/key.pem'    
```

* __Efficiency__: Processing efficiency is valued over memory friendliness. A
more responsive server is better than one that runs on very minimal resources.
Modern IRC servers like juno typically have a higher per-user load and therefore
should be prompt at fulfilling request after request. Utilizing the wonderful
[IO::Async](http://search.cpan.org/perldoc/IO::Async)
framework, juno is quite reactive.

![Efficiency](http://i.imgur.com/YpvdIYJ.png)

# Installation and operation

Most actions for starting, stopping, and managing the IRC server are committed
with the `juno` script in the root directory of the repository.

## Installation

Before installing juno, a number of Perl packages must be installed to the
system. The simplest way to install them is with the `cpanm` tool, but you can
use any CPAN client or package manager of your choice (assuming it has the
latest versions).  

To install `cpanm`, run the following command:

```bash
curl -L http://cpanmin.us | perl - --sudo App::cpanminus
```

Install the tools in a common building environment (a compiler, `make`, etc.)
Below is an example on a Debian-based distribution. Also install a few Perl
modules from the CPAN:

```bash
sudo apt-get install build-essential # or similar
cpanm --sudo IO::Async IO::Socket::IP Socket::GetAddrInfo JSON JSON::XS DBD::SQLite
```

After you've installed the appropriate Perl packages, clone the repository:

```bash
git clone --recursive https://github.com/cooper/juno.git
# OR (whichever is available on your git)
git clone --recurse-submodules https://github.com/cooper/juno.git
```

If your `git` does not support recursive cloning, or if you forgot to specify,
run `git submodule update --init` to check the submodules out.

### SSL setup

If you wish to use SSL on the server, install `libssl` and the following Perl
module:

```bash
sudo apt-get install libssl-dev
cpanm --sudo IO::Async::SSL
```

You will now need to run `./juno genssl` to generate your self-signed
SSL certificate.

In the configuration, use the `sslport` key in your `listen` block(s) to specify
the port(s) on which to listen for secure connections. If you're setting up
`connect` blocks with the `ssl` option enabled, you will also need to listen
on more port(s) using the format: `<protocol name>sslport`; e.g. `ts6sslport`.

## Configuration

juno actually comes with a working example configuration. If you want to try it
for the first time, simply copy `etc/ircd.conf.example` in to `etc/ircd.conf`.
The password for the default oper account `admin` is `k`.  

The configuration is, for the most part, self-explanitory. Anything that might
be questionable probably has a comment that explains it.

Note that, because juno ships with a configuration suitable for fiddling, the
default values in the `limit` block are rather low. A production IRC server will
likely require less strict limits on connection and client count, for example.

## Starting, stopping, etc.

These options are provided by the `juno` script.

```
usage: ./juno [action]
    start       start juno IRCd
    forcestart  attempt to start juno under any circumstances
    stop        terminate juno IRCd
    debug       start in NOFORK mode with printed output
    forever     run continuously
    foreverd    run continuously in debug mode
    rehash      rehash the server configuration file
    mkpasswd    runs the password generator
    dev         various developer actions (./juno dev help)
    help        print this information
```

* __start__: Runs the server in the background as a daemon.

* __forcestart__: Runs the server in the background, ignoring the PID file if it
appears to already be running.

* __stop__: Terminates the IRCd if it is currently running.

* __debug__: Runs the IRCd in the foreground, printing the logging output.

* __forever__: Runs the IRCd continuously in the background. In other words, if
it is stopped for any reason (such as a crash or exploit or SHUTDOWN), it will
immediately start again. Don't worry though, it will not stress out your
processor if it fails over and over.

* __foreverd__: Runs the IRCd continuously in the foreground, printing the
logging output.

* __rehash__: Notifies the currently-running server to reload its configuration
file.

* __mkpasswd__: Runs the script for generating encrypted passwords for use in
oper and connect blocks in the server configuration.

* __dev__: Includes a number of subcommand tools for developers; see
`./juno dev help`.

## Upgrading

To upgrade an existing repository, run the following commands:

```
git pull origin master
git submodule update --init
```

**OR**

Use the `UPDATE` command (provided by the Git module) to update the current
repository. It will report the version of the repository to you after checking
out.

**THEN**

Assuming the Reload module is loaded on your server, use the `RELOAD` command to
upgrade the server without restarting. This usually works. However, because
there are no stable releases, the possibility for this to fail certainly exists.

Currently, the best way to know whether the RELOAD command is safe on a
production server is to check with the developers, providing your current IRCd
version. Perhaps one day we will have stable releases that are known to upgrade
without error.

# History

juno-ircd was born a fork of [pIRCd](http://pircd.sourceforge.net) (the Perl IRC
daemon) but has since been rewritten (multiple times) from the ground up.

* [__pIRCd__](http://pircd.sourceforge.net):
Born in the 20th century and written by Jay Kominek, pIRCd is a very buggy,
poorly-coded, feature-lacking (well, compared to those now) IRC server. During
its time, it was one of only a number of IRCds featuring [SSL support](https://github.com/jkominek/pircd/blob/master/README.SSL).
Having been abandoned in 2002, pIRCd is ancient history.

* __pIRCd2__:
A PHP novice, I was convinced by someone to learn Perl. I discovered pIRCd
and spent hours trying to change something without breaking it. pIRCd2 allowed
you to use the dollar sign ($) in nicknames, adding support for users such as
[Ke$ha](https://twitter.com/KeshaRose). Truly revolutionary to IRC as a whole.

* [__juno-ircd__](https://github.com/cooper/juno1) (juno1):
A fork of pIRCd2, juno-ircd introduced a handful of new features:
[five prefixes](https://github.com/cooper/juno1/blob/ea8737edc1a221c3fd263560326a8768a4de9a62/Channel.pm#L765)
(~&@%+),
hard-coded CAP
[multi-prefix](https://github.com/cooper/juno1/blob/ea8737edc1a221c3fd263560326a8768a4de9a62/Connection.pm#L272)
support,
[channel link](https://github.com/cooper/juno1/blob/ea8737edc1a221c3fd263560326a8768a4de9a62/Channel.pm#L166)
mode (+L), internal
[logging channel](https://github.com/cooper/juno1/blob/ea8737edc1a221c3fd263560326a8768a4de9a62/LocalServer.pm#L207)
(inspired by InspIRCd), network administrator support and the corresponding
[NA:line](https://github.com/cooper/juno1/blob/master/server.conf#L22),
self-expiring temporary
[oper-override](https://github.com/cooper/juno1/blob/ea8737edc1a221c3fd263560326a8768a4de9a62/Channel.pm#L738)
mode (+O),
[channel mute](https://github.com/cooper/juno1/blob/ea8737edc1a221c3fd263560326a8768a4de9a62/Channel.pm#L729)
mode (+Z, inspired by charybdis +q),
[KLINE command](https://github.com/cooper/juno1/blob/ea8737edc1a221c3fd263560326a8768a4de9a62/User.pm#L558)
for adding K:lines from IRC,
an almost-but-never-fully working buggy
[linking protocol](https://github.com/cooper/juno1/blob/ea8737edc1a221c3fd263560326a8768a4de9a62/Server.pm#L24),
and a
[network name](https://github.com/cooper/juno1/blob/ea8737edc1a221c3fd263560326a8768a4de9a62/server.conf#L14)
(NETWORK in RPL_ISUPPORT) option. juno-ircd's name was chosen by
[Autumn](https://github.com/lacp) after the Roman goddess
[Juno](http://en.wikipedia.org/wiki/Juno_(mythology)).
Unfortunately it introduced dozens of new bugs along with its features, and it
included some of the
[ugliest code](https://github.com/cooper/juno1/blob/ea8737edc1a221c3fd263560326a8768a4de9a62/Channel.pm#L759)
in all of Perl history. An example of the
attention juno-ircd received from the
[Atheme](http://atheme.net) community:

```
[04:15pm] -Global- [Network Notice] Alice (nenolod) - We will be upgrading to "juno-ircd" in 5 seconds.
```

* [__juno__](https://github.com/cooper/juno2) (juno2):
At some point, some [IRC bullies](http://stop-irc-bullying.eu/stop/) made me
realize how horrific juno-ircd was. I decided to dramatically announce that I
would no longer be developing the project, but I could not resist for long. I
soon started from scratch, dropping the '-ircd' from the name. juno was actually
quite complete and surprisingly reliable. Unlike pIRCd and its derivatives, it
introduced an interface for modules which later became a separate project,
[API Engine](https://github.com/cooper/api-engine). It brought forth more new
features than can be mentioned, namely:
[host cloaking](https://github.com/cooper/juno2/blob/master/user.pm#L218),
[server notices](https://github.com/cooper/juno2/blob/master/utils.pm#L150),
[channel access](https://github.com/cooper/juno2/blob/master/channel.pm#L774)
mode (+A),
[GRANT](https://github.com/cooper/juno2-mods/blob/master/grant.pm) command,
[D:line](https://github.com/cooper/juno2-mods/blob/master/netban.pm),
and lots more. juno unfortunately was completely incapable of server linkage.

* [__juno3__](https://github.com/cooper/juno3):
It occurred to me one day that an IRC server incapable of linking is somewhat
impractical (as if one written in Perl were not impractical enough already). I
decided to put the past behind and say goodbye to juno2. Another complete
rewrite, juno3's showcase improvement was a dazzling
[linking protocol](https://github.com/cooper/juno/tree/master/modules/JELP).
It was even more extensible than ever before
with greatly improved
[module interfaces](https://github.com/cooper/juno/tree/master/modules/Base).
juno3 was also the first version to make use of
[IO::Async](http://search.cpan.org/perldoc/IO::Async), exponentially boosting
its speed efficiency. Although it required more memory resources than juno2, it
was prepared to take on a massive load, tested with many tens of thousands of
users. It was less buggy but also less featureful, lacking many standard IRC
functions due to my shift of focus to a reliable core.

* [__juno-mesh__](https://github.com/cooper/juno-mesh) (juno4): It was
recommended to me by [Andrew Sorensen](http://andrewsorensen.net) (AndrewX192)
that I should implement mesh server linking. It seemed that it would be easy to
implement, so I forked juno3 to create juno-mesh. In addition to mesh linking,
it introduced several new
[commands](https://github.com/cooper/juno-mesh/blob/master/mod/core_ucommands.pm)
and a new
[permission system](https://github.com/cooper/juno-mesh/blob/master/inc/channel.pm#L364)
with a method by which [additional statuses/prefixes](https://github.com/cooper/juno-mesh/blob/master/etc/ircd.conf.example#L73)
can be added.

* [__juno5__](https://github.com/cooper/juno/tree/juno5):
It turned out that mesh linking required more code and effort than intended and
introduced countless bugs that I didn't want to bother correcting. I knew that
if I started from scratch again, it would never reach the completeness of the
previous generation. Therefore, juno5 was born as yet another fork with a
[new versioning system](https://github.com/cooper/juno/commit/76d014a9665f586d88933abe884076b248255a5f).
It removed the mesh linking capability while preserving the other new features
that were introduced in juno-mesh. juno5 also reintroduced
[channel access](https://github.com/cooper/juno/blob/master/modules/Channel/Access.module/Access.pm)
(+A), this time in the form of a module.

* [__kedler__](https://github.com/cooper/juno/tree/juno6-kedler) (juno6):
Named after a Haitian computer technician, kedler was a continuation of juno5.
Its main goal was to implement the missing standard IRC functions that had never
been implemented in the third juno generation. kedler reintroduced
[hostname resolving](https://github.com/cooper/juno/tree/master/modules/Resolve.module),
a long-broken feature that
had not worked properly since juno2. kedler featured new APIs and improvements
to the
[linking protocol](https://github.com/cooper/juno/tree/master/modules/JELP).

* [__vulpia__](https://github.com/cooper/juno/tree/juno7-vulpia) (juno7):
Romanian for a female wolf, vulpia was named after the alias of a dear friend,
[Ruin](https://soundcloud.com/ruuuuuuuuuuuuin). It included several
improvements, making the IRCd more extensible than ever before. The
[Evented::API::Engine](https://github.com/cooper/evented-api-engine)
replaced the former
[API Engine](https://github.com/cooper/api-engine), allowing modules to react to
any event that occurs within juno. vulpia completed the relocation of JELP
(the linking protocol) to
[an optional module](https://github.com/cooper/juno/tree/master/modules/JELP),
opening the doors for additional linking protocols
in the future. Additionally, it established
[fantasy command](https://github.com/cooper/juno/tree/master/modules/Fantasy.module)
support; the
[Reload](https://github.com/cooper/juno/tree/master/modules/Reload.module)
module, which makes it possible to upgrade the IRCd to the latest version
without restarting or disconnecting users; and a new
[Account](https://github.com/cooper/juno/tree/master/modules/Account.module)
module, helping users to better manage nicknames and channels.

* [__kylie__](https://github.com/cooper/juno/tree/juno8-kylie) (juno8):
Named after the adored [Kyle](http://mac-mini.org), kylie introduced
several previously-missing core components including
[ident](http://en.wikipedia.org/wiki/Ident_protocol) support and channel modes:
[limit](https://github.com/cooper/juno/blob/master/modules/Channel/Limit.module/Limit.pm),
[secret](https://github.com/cooper/juno/blob/master/modules/Channel/Secret.module/Secret.pm),
and
[key](https://github.com/cooper/juno/blob/master/modules/Channel/Key.module/Key.pm).
APIs for [IRCv3](http://ircv3.org) extensions were added, leading to
[SASL](http://ircv3.org/extensions/sasl-3.1),
[multi-prefix](http://ircv3.org/extensions/multi-prefix-3.1), and
[message tag](http://ircv3.org/specification/message-tags-3.2) support. An
improved
[IRC parser](https://github.com/cooper/juno/blob/master/modules/ircd.module/message.module/message.pm)
allowed drastic code cleanup and improved efficiency. A new event-driven
[API](https://github.com/cooper/juno/blob/master/modules/Base/UserCommands.module/UserCommands.pm)
made user commands more extensible than ever before. The migration of all
non-modular packages into
[modules](https://github.com/cooper/juno/tree/master/modules/ircd.module)
significantly improved the stability and reloadability
of the IRCd.

* [__agnie__](https://github.com/cooper/juno/tree/juno9-agnie) (juno9):
Named after the beautiful and talented [Agnes](http://agnes.mac-mini.org), agnie
introduced lots of new functionality: the ability to
[manage oper flags](https://github.com/cooper/juno/blob/master/modules/Grant.module/Grant.pm)
from IRC, much-improved
[account management](https://github.com/cooper/juno/tree/master/modules/Account.module),
and
[command aliases](https://github.com/cooper/juno/blob/master/modules/Alias.module/Alias.pm)
to name a few. It opened a new door of possibility by adding partial
[TS6 protocol](https://github.com/charybdis-ircd/charybdis/blob/master/doc/technical/ts6-protocol.txt)
support, and
it even supports [Atheme](http://atheme.net) now to some extent. New
channel modes include
[invite exception](https://github.com/cooper/juno/blob/master/modules/Channel/Invite.module/Invite.pm)
(+I),
[free invite](https://github.com/cooper/juno/blob/master/modules/Channel/Invite.module/Invite.pm)
(+g),
[channel forward](https://github.com/cooper/juno/blob/master/modules/Channel/Forward.module/Forward.pm)
(+F),
[oper only channel](https://github.com/cooper/juno/tree/master/modules/Channel/OperOnly.module)
(+O),
and
[mute ban](https://github.com/cooper/juno/blob/master/modules/Channel/Mute.module/Mute.pm)
(+Z, missing since juno2); also, the
[TopicAdditions](https://github.com/cooper/juno/blob/master/modules/Channel/TopicAdditions.module/TopicAdditions.pm)
module added convenient commands to prepend or append the topic. Some missing
commands were added:
[ADMIN](https://github.com/cooper/juno/blob/juno9-agnie/modules/Core/UserCommands.module/UserCommands.pm#L1272),
[TIME](https://github.com/cooper/juno/blob/juno9-agnie/modules/Core/UserCommands.module/UserCommands.pm#L1296),
and
[USERHOST](https://github.com/cooper/juno/blob/juno9-agnie/modules/Core/UserCommands.module/UserCommands.pm#L1311);
and several commands that previously did not work remotely now do. agnie
introduced a
[new mechanism](https://github.com/cooper/juno/tree/master/modules/Ban/Ban.module/Ban.pm)
for storing and enforcing bans (functionality missing since juno2), followed by
[K-Line](https://github.com/cooper/juno/blob/master/modules/Ban/Kline.module/Kline.pm)
and
[D-Line](https://github.com/cooper/juno/blob/master/modules/Ban/Dline.module/Dline.pm)
support in the form of independent modules. In addition to the existing
[RELOAD](https://github.com/cooper/juno/blob/master/modules/Reload.module/Reload.pm)
command, agnie
includes new ways to manage servers remotely, including
[repository](https://github.com/cooper/juno/blob/master/modules/Git.module/Git.pm)
and
[configuration](https://github.com/cooper/juno/blob/master/modules/Configuration/Set.module/Set.pm)
management directly from IRC.

* [__yiria__](https://github.com/cooper/juno/tree/juno10-yiria) (juno10):
An acronym for our slogan (Yes. It really is an IRC daemon.), yiria's primary
goal was to complete the implementation of the
[TS6 protocol](https://github.com/charybdis-ircd/charybdis/blob/master/doc/technical/ts6-protocol.txt).
Doing so while retaining support for the Juno Extensible Linking
Protocol (JELP) involved efficient TS6<->JELP command conversion and vigorous
[mode translation](https://github.com/cooper/juno/blob/eab5acca7645f3d460ba0fb84de9e58c6e39e3d5/modules/ircd.module/server.module/server.pm#L185),
among other challenges. But we
pulled through, and now juno almost fully supports a variety of TS6 servers such
as [charybdis](https://github.com/charybdis-ircd/charybdis) and [elemental-ircd](https://github.com/Elemental-IRCd/elemental-ircd), as well as
many pseudoserver packages like
[Atheme](http://atheme.net) IRC Services and
[PyLink](https://github.com/GLolol/PyLink) relay software.
Adding TS6 resulted in a positive side effect: several improvements within JELP
in order to stay competitive with the newly-supported protocol. Aside from
server-to-server improvements, new noteworthy features in yiria include built-in
[DNSBL](https://github.com/cooper/juno/blob/master/modules/DNSBL.module/DNSBL.pm)
checking,
[private channels](https://github.com/cooper/juno/blob/master/modules/Channel/Secret.module/Secret.pm),
and IRCv3
[away-notify](http://ircv3.net/specs/extensions/away-notify-3.1.html) support.
As always, there were lots of bug fixes and efficiency improvements too.

* [__janet__](https://github.com/cooper/juno/tree/juno11-janet) (juno11):
Upon the release of mihret (juno12), a new versioning system was adopted.
Releases now occur at the start of the next major version (in this case,
v12.00), rather than at an arbitrary version as before. So janet and mihret are
actually the same release. See below. This new system is less confusing and
makes it easier to release patches.

* [__mihret__](https://github.com/cooper/juno/tree/juno12-mihret) (juno12):
A lot was accomplished during the short-lived development of mihret.
Several new channel features were introduced, including
IRCv3 [extended-join](http://ircv3.net/specs/extensions/extended-join-3.1.html),
[permanent channels (+P)](modules/Channel/Permanent.module/Permanent.pm),
[op moderation (+z)](modules/Channel/OpModerate.module/OpModerate.pm),
[color stripping (+c)](modules/Channel/NoColor.module/NoColor.pm),
[registered only (+r)](modules/Channel/RegisteredOnly.module/RegisteredOnly.pm),
and [SSL only (+S)](modules/Channel/SSLOnly.module/SSLOnly.pm),
all implemented as modules.
Internal support for new user modes, deafness (+D) and bot status (+B), was also
added. mihret furthered the support of external IRC services packages by
reworking the [SASL](modules/SASL/SASL.module)
module to support relaying authentication over both
server protocols. Nickname enforcement, nickname reservations, and
channel reservations are now supported as well. For the first time in its
history, juno now has a decent [hostname cloaking](modules/Cloak.module/Cloak.pm)
interface with a
[charybdis-compatible](modules/Cloak.module/Charybdis.module/Charybdis.pm)
implementation. The [netban](modules/Ban) module was
rewritten from the ground up in an objective fashion. New APIs make it very easy
to extend netban functionality from additional modules. The
[TS6 netban](modules/Ban/TS6.module/TS6.pm) implementation was mostly completed
too. A new IRCd support
interface makes it easy to add special rules for certain IRC software and also
features inheritance of properties for derivative software.
As usual, there were astounding improvements to [TS6](doc/ts6.md)
and even some enhancements to JELP.

* [__dev__](https://github.com/cooper/juno) (juno13): Yet to be named, the next
release will be based on the current git, a continuation of mihret under active
development.

# Information

Here you will find contacts, licensing, development information, etc.

## Getting help

If you need any help with setting up or configuring juno, visit us on
NoTrollPlzNet IRC at `irc.notroll.net 6667 #k`. I love new ideas, so feel free
to recommend a feature or fix here as well. In fact, I encourage you to visit me
on IRC because many parts of this software are poorly documented or not
documented at all. Sadly, most of the "documentation" lives only in my head at
the moment, but I'll gladly tell you anything you may wish to know about the
IRCd.

If you discover a reproducible bug, please
[file an issue](https://github.com/cooper/juno/issues).

## Providing help

If you are interested in assisting with the development of this software,
please visit me on IRC at `irc.notroll.net port 6667 #k`. I will be happy to
listen to your ideas and feedback, regardless of whether you are a Perl
developer.

You can also submit ideas and feature requests to the
[issue tracker](https://github.com/cooper/juno/issues).

If you are interested in writing modules for juno-ircd, please contact me on IRC
because the APIs are not yet fully documented. I will gladly give you a tour of
juno-ircd's module programming interfaces.

## Versions, changes, and plans

See INDEV for a detailed account of all changes dating back to the beginning of
juno. The newest changes are at the bottom of the file.

Check out the
[issue tracker](https://github.com/cooper/juno/issues)
for information on bugs and upcoming features.

The current version is in the VERSION file.

## Author

Mitchell Cooper, mitchell@notroll.net  

I use Unix-like systems, and much of my work is designed specifically for such.
~~I would be surprised yet pleased if someone got this software working on
Windows.~~ Actually, it seems to work on Windows now. Somewhat.

juno-ircd was my first project in Perl — ever. Luckily, it's been
through six years of constant improvement. Most of my creations in Perl are
related to IRC in some way, but I have a few other projects as well. I always
look back at things I worked on a month ago and realize how terrible they are.
That is why there are several rewrites of the same IRCd. But don't worry. I am
awfully proud of the cleanliness of the current version's codebase; it dates
back to juno3.

## License

juno-ircd version 3 and all of its derivatives (including this distribution) are
licensed under the three-clause "New" BSD license. A copy of the license should
be included with all instances of this software in the root directory.
