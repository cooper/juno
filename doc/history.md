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
[linking protocol](technical/proto/jelp.md).
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
to the [linking protocol](technical/proto/jelp.md).

* [__vulpia__](https://github.com/cooper/juno/tree/juno7-vulpia) (juno7):
Romanian for a female wolf, vulpia was named after the alias of a dear friend,
[Ruin](https://github.com/RuinIsProbablyTaken). It included several
improvements, making the IRCd more extensible than ever before. The
[Evented::API::Engine](https://github.com/cooper/evented-api-engine)
replaced the former
[API Engine](https://github.com/cooper/api-engine), allowing modules to react to
any event that occurs within juno. vulpia completed the relocation of
[JELP](technical/proto/jelp.md) (the linking protocol) to
[an optional module](https://github.com/cooper/juno/tree/master/modules/JELP),
opening the doors for additional linking protocols
in the future. Additionally, it established
[fantasy command](modules.md#channelfantasy)
support; the
[Reload](https://github.com/cooper/juno/tree/master/modules/Reload.module)
module, which makes it possible to upgrade the IRCd to the latest version
without restarting or disconnecting users; and a new
[Account](https://github.com/cooper/juno/tree/juno7-vulpia/modules/Account.module)
module, helping users to better manage nicknames and channels.

* [__kylie__](https://github.com/cooper/juno/tree/juno8-kylie) (juno8):
Named after the adored [Kyle](http://mac-mini.org), kylie introduced
several previously-missing core components including
[ident](http://en.wikipedia.org/wiki/Ident_protocol) support and channel modes:
[limit](modules.md#channellimit),
[secret](modules.md#channelsecret),
and
[key](modules.md#channelkey).
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
[manage oper flags](modules.md#grant) from IRC, much-improved
[account management](https://github.com/cooper/juno/tree/juno9-agnie/modules/Account.module),
and [command aliases](modules.md#alias)
to name a few. It opened a new door of possibility by adding partial
[TS6 protocol](ts6.md) support, and it even supports
[Atheme](http://atheme.net) now to some extent. New channel modes include
[invite exception](modules.md#channelinvite) (+I),
[free invite](modules.md#channelinvite) (+g),
[channel forward](modules.md#channelforward) (+F),
[oper only channel](modules.md#channeloperonly) (+O), and
[mute ban](modules.md#channelmute) (+Z, missing since juno2); also, the
[TopicAdditions](modules.md#channeltopicadditions)
module added convenient commands to prepend or append the topic. Some missing
commands were added: ADMIN, TIME, USERHOST; and several commands that previously
did not work remotely now do. agnie introduced a
[new mechanism](modules.md#ban)
for storing and enforcing bans (functionality missing since juno2), followed by
[K-Line](modules.md#bankline) and [D-Line](modules.md#bandline)
support in the form of independent modules. In addition to the existing
[RELOAD](modules.md#Reload) command, agnie
includes new ways to manage servers remotely, including
[repository](modules.md#git) and
[configuration](modules.md#configurationset) management directly from IRC.

* [__yiria__](https://github.com/cooper/juno/tree/juno10-yiria) (juno10):
An acronym for our slogan (Yes. It really is an IRC daemon.), yiria's primary
goal was to complete the implementation of the
[TS6 protocol](ts6.md).
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
[DNSBL](modules.md#dnsbl) checking,
[private channels](modules.md#channelsecret), and IRCv3
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
[permanent channels](modules.md#channelpermanent) (+P),
[op moderation](modules.md#channelopmoderate) (+z),
[color stripping](modules.md#channelnocolor) (+c),
[registered only](modules.md#channelregisteredonly) (+r),
and [SSL only](modules.md#channelsslonly) (+S), all implemented as modules.
Internal support for new user modes, deafness (+D) and bot status (+B), was also
added. mihret furthered the support of external IRC services packages by
reworking the [SASL](https://github.com/cooper/juno/blob/master/modules/SASL/SASL.module)
module to support relaying authentication over both
server protocols. Nickname enforcement, nickname reservations, and
channel reservations are now supported as well. For the first time in its
history, juno now has a decent [hostname cloaking](modules.md#cloak)
interface with a
[charybdis-compatible](https://github.com/cooper/juno/blob/master/modules/Cloak.module/Charybdis.module/Charybdis.pm)
implementation. The [netban](https://github.com/cooper/juno/blob/master/modules/Ban) module was
rewritten from the ground up in an objective fashion. New APIs make it very easy
to extend netban functionality from additional modules. The
[TS6 netban](https://github.com/cooper/juno/blob/master/modules/Ban/Ban.module/TS6.module/TS6.pm) implementation was mostly
completed too. A new IRCd support
interface makes it easy to add special rules for certain IRC software and also
features inheritance of properties for derivative software.
As usual, there were astounding improvements to [TS6](ts6.md)
and even some enhancements to [JELP](technical/proto/jelp.md).

* [__ava__](https://github.com/cooper/juno/tree/juno13-ava) (juno13):
Several new IRCv3 features were added, particularly the improved IRCv3.2
[capability negotiation](http://ircv3.net/specs/core/capability-negotiation-3.2.html),
[cap-notify](http://ircv3.net/specs/extensions/cap-notify-3.2.html),
[userhost-in-names](http://ircv3.net/specs/extensions/userhost-in-names-3.2.html),
[SASL reauthentication](http://ircv3.net/specs/extensions/sasl-3.2.html),
and the [MONITOR](http://ircv3.net/specs/core/monitor-3.2.html)
client notification system. Additional new channel features include
[WHOX](http://faerion.sourceforge.net/doc/irc/whox.var) support,
KNOCKing, join throttle mode (+j), no forward-mode (+Q), and the long-planned
[MODESYNC](https://github.com/cooper/juno/issues/63)
mechanism, which helps maintain network-wide channel mode synchrony even when
some modes are not enabled on all servers. The built-in DNS blacklist checker
now supports IPv6 blacklists and has improved caching helping to decrease the
effects of malicious attacks. Further work on TS6 and JELP includes improved ban
propagation and more S2S security measures.

* [__dev__](https://github.com/cooper/juno) (juno14): Yet to be named, the next
release will be based on the current git, a continuation of ava under active
development.
