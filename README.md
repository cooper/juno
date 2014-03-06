# kedler-ircd version 6

Yes.  
It really is an IRC daemon.  
It's written in Perl.  
  
...  
You can breathe again.  
There. Very good.  
  
# introduction to kedler-ircd

This IRC server daemon is written in the Perl programming language. It is based on the
code of juno-ircd version 3, a from-scratch rewrite of the former juno-ircd version 2.
Each major version of this IRCd has a specific set of major goals that will be introduced.
This software is functional for the most part, but at this time, it has no 'stable'
releases. For full history of this IRCd and its predecessors, see the 'history' section
below. See the 'what is kedler-ircd?' section to find out what's new in this release.

## what is kedler-ircd?

kedler is juno-ircd version 6, which is a continuation of juno-ircd version 5, itself a
fork of juno-ircd 4 without mesh linking. it aims to implement most (hopefully all) of the
commands, modes, etc. specified in the standard set of IRC functionalities. it also has
many improved APIs. kedler also aims to be more event-driven than any other version of
juno, making it even more extensible through modules. on top of these changes, the core of
kedler is much cleaner and more uniform than any past version. see GOALS for a full list
of features planned for implementation in this version of juno-ircd.  

unlike all other major versions of juno-ircd, kedler is not a fork of a former version. it
is simply the continuation and rebranding of juno-ircd version 5. You will not find juno5
in another repository. This is the juno5 repository. If you wish to update an existing
copy of juno5, you can do so by changing the `.git/config` file to use the 'kedler'
repository rather than the 'juno5' repository. Then, simply `git pull`.

## what is vulpia-ircd?

vulpia is juno-ircd version 7, a continuation of kedler.

## installation

juno is designed to be used out-of-the-box. It comes with a working configuration and, up
until recently, depended only on modules that ship with Perl. However, it now requires
much of the IO::Async library and IO::Socket::IP for IPv4 and IPv6 support. After you get
everything you need installed, feel free to either fire up the IRCd for trying it out or
editing the example configuration. The configuration should be saved as etc/ircd.conf.  
    
Before you start, there are a few things you should know, however. 
  
### IO::Async framework

Since version 3, juno-ircd has depended on many packages from the [IO::Async](http://search.cpan.org/~pevans/IO-Async-0.53/lib/IO/Async.pm) library. It uses this framework to power its sockets, timers, etc. You
should fetch these packages. Some of them may be included with the IO::Async pacakge.
I'm not quite sure which ones need to be fetched manually.  
Thanks to IO::Async, juno3 and its children are more efficient than any version was 
before.

* IO::Async
* IO::Async::Loop (probably included IO::Async)
* IO::Async::Loop::Epoll (optimization on Linux)
* IO::Async::Timer (probably included)
* IO::Async::Stream (?)
* IO::Async::Protocol::LineStream (?)
* IO::Async::Protocol::Stream (?)
* etc...

### Evented::Object and packages based on it

Since version 5, juno-ircd has depended on many of the "Evented" packages. These are all
included as submodules.

* [Evented::Object](https://github.com/cooper/evented-object) - provides methods to fire and respond to events on objects.
* [Evented::Configuration](https://github.com/cooper/evented-configuration) - a configuration class which fires events when values are changed.
* [Evented::Database](https://github.com/cooper/evented-database) - a database based upon Evented::Configuration with seamless database functionality in a configuration class.
* [API Engine](https://github.com/cooper/api-engine) - an extensible API class based on the original APIs of juno, providing a base for juno's module interfaces.

## fetching and updating
  
**To fetch juno for the first time**

The easiest way to fetch juno-ircd is to use recursive options for the clone command.

```
git clone --recurse-submodules git://github.com/cooper/kedler.git
# or
git clone --recursive git://github.com/cooper/kedler.git
# (I'm not sure which was available first, so just use whichever works.)
```

If all else fails, you may need to run `git submodule update --init`.

**To update an existing copy of juno**

To update, you should pull with the `git pull` command. Then, in order to update
submodules, you may need to run `git submodule update`. If this does not work, run
`git submodule update --init`. This is usually necessary if a new submodule has been
included since your last update.

## configuring juno and its database

Traditionally, juno has always included a working configuration. This allows you to run it
without changing anything at all. However, version 6 (kedler-ircd) transition to the
Evented::Database configuration package. This configuration is quite different than any
other IRC server software's configuration mechanisms. In short, you use a database
rather than a single configuration file. This allows you to make changes to the
configuration database without modifying the file itself. Configuration files are still
used, but their values are a fallback and are only searched for if no other value is
present in the database. juno will also include a script to generate a configuration file
from your configuration database. Currently, SQLite is the only type of database available
for use in juno.

## starting, stopping, and rehashing juno

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
* **juno-ircd (juno1)**: very poorly written but has more features: five prefixes instead of two,
  multi-prefix, CAP, channel link mode, internal logging channel, network administrator
  support, oper-override mode, channel mute mode, kline command, an almost-working buggy
  linking protocol, and a network name configuration option.
**and that's when I realized pIRCd blows.**
* **juno (juno2)**: rewritten from scratch, *far* more usable than any other previous version. This
  version of juno is what I would consider to be "fully-featured." It has an easy-to-use
  module API and just about every channel mode you can think of. However, it does not
  support server linking at all.
* **juno3**: rewritten from scratch, *far* more efficient than any previous version of juno.
  capable of handling over nine thousand connections and 100,000 global users. has an even
  more capable module API than juno2. has its own custom linking protocol that is also
  very, very extensible. designed to be so customizable that almost anything can be edited
  by using a module. requires more resources than before, but is also more prepared for
  IRC networks with large loads.
* **juno4**: also known as juno-mesh, juno4 is the first version of juno which is not a
  from-scratch rewrite. it is based on juno3 and aims to implement mesh server linking.
* **juno5**: juno5 is a fork of juno4 (itself a fork of juno3). it includes the new
  features introduced in juno4, but it does not support mesh server linkage.
* **kedler-ircd (juno6)**: kedler-ircd is a major leap for juno, as it introduces many features no
  earlier version had. as well as implementing the core set of IRC commands and modes,
  kedler features an event-driven core, making it even more extensibe than juno3. kedler
  also implements new APIs for all of its new features. it attempts to move JELP out of
  the core of juno, eventually making it possible to implement other linking protocols
  through the use of modules.
  
When juno2 was in development, it was named "juno" where juno1 was named "juno-ircd" as it
always had been. When juno3 was born, juno-ircd and juno were renamed to juno1 and juno2
to avoid confusion. Versions are written as version.major.minor.commit, such as 3.2.1.1
(juno3 2.1 commit 1.)


## what is juno-ircd version 5?

juno5 is a fork of juno4 which does not support mesh server linking. However, it adopted
performance fixes and new features introduced in juno4. Mesh linking was canceled because
it isn't exactly worth the extra effort and ugly code.

## what is juno-ircd version 4?

juno4 is a fork of juno3 which supports mesh server linking. No server links two servers.
If a server disconnects, only the users on that server are lost. The rest of the network,
including any services package, stays intact. With this setup, it is actually possible to
have certain servers linked only to certain servers. I don't know why in the world you
might want that, but it's possible. just FYI. It also means that if a server disconnects
from one server for whatever reason (i.e. ping timeout), it doesn't necessarily mean that
that server is going to disconnect from the rest of the servers on the network. This
change was a few very simple modifications to juno3's existing linking protocol. Thanks to
AndrewX192 for recommending it. This is a very rare but useful feature.

## what is juno-ircd version 3?

juno-ircd is a fully-featured, modular, and usable IRC daemon written in Perl. It is aimed
to be highly extensible and customizable. At the same time it is efficient and usable.  

Here is a list of goals that juno-ircd is designed for.

* being written in Perl.
* being extensible and flexible.
* being customizable in every visibly possible way.
* compatibility with some standards and hopefully *most* clients.
* seamless multi-server IRC networks.
* drop-in code: the ability to update most features without restarting.
* being bugless. (but everyone makes mistakes every once in a while..)

Here's a list of things juno is not designed for.

* being memory-friendly.
* compatibility with non-unix-like systems.
* being a compiled executable.
* replicating functionality of the original ircd or ircds branched from it.
* replicating inspircd.
* supporting IRC clients from 1912.
* non-English-speaking server administrators.
* linking with other ircds (so don't ask for that.)

## from juno2 to juno3, what's new?

* **a very extensible linking protocol**
* more efficiency
* the ability to host over 9,000 users
* an even more extensible API
* more customization
* a better configuration
* even more modular
* more IRC-compliant (probably better for OS X IRC clients!)
* less buggy
* more features in general
* the ability to update core features without restarting


# More information

Here you will find contact information, licensing, development information, etc. 

## development, changes, etc.

If you are interested in assisting with the development of this software, please visit me
on IRC at `irc.notroll.net port 6667 #k`. I am willing to hear your ideas as well, whether
or not you are a developer. If you are interested in writing modules for juno-ircd, please
contact me on IRC. Unfortunately, the APIs are not yet fully documented. I will gladly
give you a tour of juno-ircd's several programming interfaces.

### changelog

See INDEV for a changelog and TODO list. It has been extended throughout all versions of
this software. The newest changes are at the bottom.

## about the author

Mitchell Cooper, mitchell@notroll.net  
  
juno1 was my first project in Perl, ever. Since then I have created loads of things. I am
still learning, but I have gotten to a point now where I know the Perl language well
enough to stop learning. Most of my creations in Perl are related to IRC in some way,
though I have other projects as well. I always look back at things I worked on a month ago
and realize how terrible they are. That is why there are three writes of the same IRCd.
You will notice in my work that I don't really care about people with machines from the
'90s. (just kidding, juno is surprisingly resource-friendly.) I use unix-like systems, and
all of my work is designed specifically for unix-like systems. I would be very, very
surprised if someone got this IRCd working on Windows. I and many others have formed an
organized known as NoTrollPlzNet which aims to create safe chatting environments (on IRC,
in particular.) I like apple pie. I am American. I know a woman who was raised in Africa.
I live near a house that was on Extreme Makeover Home Edition. I build, sell, and maintain
computers. I love chicken, but I don't like beer chicken. Dark meet is significantly
better than white meat. Pepsi is better than coke. I like Perl.

## getting help and more info

If you need any help with setting up/configuring juno, visit us on NoTrollPlzNet IRC at
`irc.notroll.net port 6667 #k`. I love new ideas, so feel free to recommend a feature or
fix here as well. In fact, I encourage you to visit me on IRC because I understand that
many parts of this software are poorly documented. Most of the documentation lives only
in my head, so feel free to ask me anything you may wish to know.

## license information

juno-ircd version 3 and all of its derivatives are licensed under the three-clause
"New" BSD license. A copy of this license should be included with all instances of this
software source, either in the root directory or in the 'doc' directory.

