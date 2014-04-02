# vulpia-ircd version 7

Yes.  
It really is an IRC daemon.  
It's written in Perl.  
  
...  
You can breathe again.  
There. Very good.

# Introduction to juno-ircd

This IRC server daemon is written in the Perl programming language. It is based on the
code of juno-ircd version 3, a from-scratch rewrite of the former juno-ircd version 2.
Each major version of this IRCd has a specific set of goals that will be introduced.
This software is functional for the most part, but at this time, it has no 'stable'
releases. For full history of this IRCd and its predecessors, see the 'History' section
below.

## Installation

juno is designed to be used out-of-the-box. It comes with a working configuration and, up
until recently, depended only on modules that ship with Perl. However, it now requires
much of the IO::Async library and IO::Socket::IP for IPv4 and IPv6 support. After you get
everything you need installed, feel free to either fire up the IRCd for trying it out or
editing the example configuration. The configuration should be saved as etc/ircd.conf.
See the following sections for information on how to install dependencies.

### IO::Async and friends

Since version 3, juno-ircd has depended on many packages from the
[IO::Async](http://search.cpan.org/~pevans/IO-Async-0.53/lib/IO/Async.pm) library. It uses
this framework to power its sockets, timers, etc. You should fetch these packages. Some of
them may be included with the IO::Async pacakge. I'm not quite sure which ones need to be
fetched manually. Thanks to IO::Async, juno3 and its children are more efficient at
simultaneous file and socket operations than any previous version.

* IO::Async
* IO::Async::Loop::Epoll (optimization on Linux)
* IO::Socket::IP
* Socket::GetAddrInfo
* etc...

### Evented::Object and friends

Since version 5, juno-ircd has depended on many of the "Evented" packages. These are all
included as submodules.

* [Evented::Object](https://github.com/cooper/evented-object) - provides methods to fire
  and respond to events on objects.

* [Evented::Configuration](https://github.com/cooper/evented-configuration) - a
  configuration class which fires events when values are changed.

* [Evented::Database](https://github.com/cooper/evented-database) - a database based upon
  Evented::Configuration with seamless database functionality in a configuration class.

* [API Engine](https://github.com/cooper/api-engine) - an extensible API class based on the
  original APIs of juno, providing a base for juno's module interfaces.

## Fetching and updating
  
**To fetch juno for the first time**:

The easiest way to fetch juno-ircd is to use recursive options for the clone command.

```
git clone --recurse-submodules git://github.com/cooper/kedler.git
# or
git clone --recursive git://github.com/cooper/kedler.git
# (I'm not sure which was available first, so just use whichever works.)
```

If all else fails, you may need to run `git submodule update --init` after cloning.

**To update an existing copy of juno**

To update, you should pull with the `git pull` command. Then, in order to update
submodules, you may need to run `git submodule update`. If this does not work, run
`git submodule update --init`. This is usually necessary if a new submodule has been
included since your last update.

## Starting, stopping, and rehashing juno

You should never use any of juno's executable files in the 'bin' directory directly.
Instead, juno includes a start script that sets the necessary environment variables needed
to run the software.  

Start with `./juno start`. Stop with `./juno stop`. Rehash with `./juno rehash`.

# History of this software

juno-ircd started as a fork of pIRCd, the Perl IRC daemon written several years ago by Jay
Kominek. It has grown to be a bit more *practical*.  
  
* **pIRCd**: very buggy, lacking features other than traditional IRC features, poorly coded.
  during its time it was one of few IRCds that featured SSL support.

* **pIRCd2**: the same as pIRCd, except you can use dollar signs in your nicks, like Ke$ha.

* **juno-ircd** (juno1): very poorly written but has more features: five prefixes instead of two,
  multi-prefix, CAP, channel link mode, internal logging channel, network administrator
  support, oper-override mode, channel mute mode, kline command, an almost-working buggy
  linking protocol, and a network name configuration option. and that's when I realized pIRCd blows.

* **juno** (juno2): rewritten from scratch, *far* more usable than any other previous version. This
  version of juno is what I would consider to be "fully-featured." It has an easy-to-use
  module API and just about every channel mode you can think of. However, it does not
  support server linking at all.

* **juno3**: rewritten from scratch, *far* more efficient than any previous version of juno.
  capable of handling over nine thousand connections and 100,000 global users. has an even
  more capable module API than juno2. has its own custom linking protocol that is also
  very, very extensible. designed to be so customizable that almost anything can be edited
  by using a module. requires more resources than before, but is also more prepared for
  IRC networks with large loads.

* **juno-mesh** (juno4): the first version of juno which is not a from-scratch rewrite.
  it is forked from juno3 and aims to implement mesh server linking.

* **juno5**: juno5 is a fork of juno4 (itself a fork of juno3). it includes the new
  features introduced in juno4, but it does not support mesh server linkage.

* **kedler-ircd** (juno6): a continuation of juno5 and major leap
  from previous versions. it introduces many features no
  earlier version had. as well as implementing the core set of IRC commands and modes,
  kedler features an event-driven core, making it even more extensibe than juno3. kedler
  also implements new APIs for all of its new features. it attempts to move JELP out of
  the core of juno, eventually making it possible to implement other linking protocols
  through the use of modules.

* **vulpia-ircd** (juno7): tagged vulpia-ircd, is a continuation of kedler and is
  currently under active development.

## Naming conventions or lack thereof

When juno2 was in development, it was named "juno" where juno1 was named "juno-ircd" as it
always had been. When juno3 was born, juno-ircd and juno were renamed to juno1 and juno2
to avoid confusion. Versions were written as version.major.minor.commit, such as 3.2.1.1
(or juno3 2.1 commit 1).

However, I decided one day that it would be fun to add even more
confusion by adopting a new versioning system that increments at a faster rate. Now, each
commit increments the version by a tenth. For example, the last commit of kedler (juno6)
is 6.99, and the first commit of vulpia (juno7) is simply 7.

## What is juno-ircd?

juno-ircd is a fully-featured, modular, and usable IRC daemon written in Perl. It is aimed
to be highly extensible and customizable. At the same time it is efficient and usable.  

Here is a list of goals that juno-ircd aims to meet:

* being extensible and flexible.
* being customizable in every visibly possible way.
* compatibility with some standards and hopefully most clients.
* seamless multi-server IRC networks.
* the ability to update most features without restarting.
* the ability to
* being bugless. (it can never be true, but it can be a goal)
* being written in Perl!

Here's a list of concepts around which juno is not designed:

* compatibility with non-unix-like systems.
* low memory usage is not valued over operation efficiency.
* replicating functionality of the original ircd or ircds branched from it.
* implementing inspircd's "every command is a module" ideology.
* supporting IRC clients from 1912.
* non-English-understanding server administrators.
* linking with other IRC software... (yet?)
* being a compiled executable.

## From juno2 to juno3, what's new?

* a very extensible linking protocol
* more efficiency in operations
* the ability to host over 9,000 users
* an even more extensible API
* more customization
* a better configuration format
* even more modularity
* more RFC compliancy
* more IRCv3 implementations
* less buggy!
* more features in general
* the ability to update core features without restarting

# More information

Here you will find contact information, licensing, development information, etc. 

## Getting help

If you need any help with setting up/configuring juno, visit us on NoTrollPlzNet IRC at
`irc.notroll.net port 6667 #k`. I love new ideas, so feel free to recommend a feature or
fix here as well. In fact, I encourage you to visit me on IRC because I understand that
many parts of this software are poorly documented. Unfortunately, most of the
"documentation" lives only in my head at the moment, so please feel free to ask me
anything you may wish to know.

## Helping me out

If you are interested in assisting with the development of this software, please visit me
on IRC at `irc.notroll.net port 6667 #k`. I am willing to hear your ideas whether
or not you are a developer.  

If you are interested in writing modules for juno-ircd, please
contact me on IRC. Unfortunately, the APIs are not yet fully documented. I will gladly
give you a tour of juno-ircd's several programming interfaces.

### Versions, changes, and plans

See INDEV for a changelog and TODO list. It has been extended throughout all versions of
this software starting with juno-ircd (juno1). The newest changes are at the bottom.
The current version is in the VERSION file.
Planned features are in the GOALS file.

## About the author

Mitchell Cooper, mitchell@notroll.net  

I use Unix-like systems, and much of my work is designed specifically for such.
I would be surprised yet pleased if someone got this software working on Windows. If the
Xcode project isn't a good enough indication, I currently use OS X to develop this software.
I don't think it's appropriate for Perl, but I have not yet found a great OS X editor.

I live in the middle of nowhere and prefer the dark chicken meat over white meat. I'll
drink a Coke if there's no better option, but I'd take a Sunkist, Pepsi or Dr. Pepper first.
I don't watch much television, but when I do, it's usually news networks, C-SPAN, and night shows.
  
I repair computers and visit people's homes to help with their electronic troubles.
I've designed websites for local entities in the area. I collect computers and have
gradually removed items from my home to make more room for them. Some of my friends have
tagged me a "computer hoarder."

I always feel that I'm too busy to do anything and therefore accomplish almost nothing. I
am a lazy procrastinator but work well under the pressure of time limits. During my
"free time," I ride a motorized bike for hours even further into the middle of nowhere
without reason. I garden during the summer: Asparagus and onions are my favorite.

juno-ircd was my first project in Perl -- ever.
Most of my creations in Perl are related to IRC in some way, but I have other projects as
well. I always look back at things I worked on a month ago and realize how terrible they
are. That is why there are several rewrites of the same IRCd. I am, however, quite proud
of the cleanliness of the current version.

## License information

juno-ircd version 3 and all of its derivatives are licensed under the three-clause
"New" BSD license. A copy of this license should be included with all instances of this
software source, either in the root directory or in the 'doc' directory.

