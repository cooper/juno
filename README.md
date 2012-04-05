# juno-ircd version 5

Yes.  
It really is an IRC daemon.  
It's written in Perl.  
  
...  
You can breathe again.  
There. Very good.  
  

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

## installation

juno is designed to be used out-of-the-box. It comes with a working configuration and, up
until recently, depended only on modules that ship with Perl. However, it now requires
much of the IO::Async library and IO::Socket::IP for IPv4 and IPv6 support. After you get
everything you need installed, feel free to either fire up the IRCd for trying it out or
editing the example configuration. The configuration should be saved as etc/ircd.conf.

## history

juno-ircd started as a fork of pIRCd, the Perl IRC daemon written several years ago by Jay
Kominek. It has grown to be a bit more *practical*.  
  
* **pIRCd**: very buggy, lacking features other than traditional IRC features, poorly coded.
  during its time it was one of few IRCds that featured SSL support.
* **pIRCd2**: the same as pIRCd, except you can use dollar signs in your nicks, like Ke$ha.
* **juno-ircd**: very poorly written but has more features: five prefixes instead of two,
  multi-prefix, CAP, channel link mode, internal logging channel, network administrator
  support, oper-override mode, channel mute mode, kline command, an almost-working buggy
  linking protocol, and a network name configuration option.
**and that's when I realized pIRCd blows.**
* **juno**: rewritten from scratch, *far* more usable than any other previous version. This
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
  
When juno2 was in development, it was named "juno" where juno1 was named "juno-ircd" as it
always had been. When juno3 was born, juno-ircd and juno were renamed to juno1 and juno2
to avoid confusion. Versions are written as version.major.minor.commit, such as 3.2.1.1
(juno3 2.1 commit 1.)

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

## more info

See INDEV for a changelog and TODO list. If you need any help with setting up/configuring
juno, visit us on NoTrollPlzNet IRC at `irc.notroll.net port 6667 #k`. I love new ideas,
so feel free to recommend a feature or fix.
