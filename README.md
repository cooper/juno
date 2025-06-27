# juno

Yes.  
It really is an IRC daemon.  
It's written in Perl.  

...  

You can breathe again.  
There. Very good.  

# Introduction

This is juno, a seriously modern IRC daemon written from scratch
in Perl. Really.

> Perl is the right language for IRC. IRC is chock full of various strings and
> other what not, all of which is easily parsed by Perl, where the C IRC daemons
> jump through all kinds of hoops and have really nasty looking code (have you
> ever looked at the Undernet IRC daemon?) Whereas this is, in my opinion, very
> clean.

This software will hopefully surprise you with its novel features and
functionality. It's super easy to install and even comes with a working
configuration, so go ahead and [try it already](#installation).

Come chat with us at
[`#k` on `irc.notroll.net`](irc://irc.notroll.net/k) too.

## Features

Here are some things that make juno stand out. You can

* [Upgrade](doc/modules.md#reload) an entire network from IRC without restarting
  servers or dropping connections.
* [Check out](doc/modules.md#git) the latest version from git via IRC.
* [Configure](doc/modules.md#configurationset) servers directly from IRC.
* [Link](doc/ts6.md#supported-software) a complex network of various IRCds and
  services packages spanning multiple server protocols.
* [Write](doc/index.md#technical) modules for the easy-to-use event-based
  module API.

Plus, juno

* Is free and open-source.
* Is written in Perl, making it fun and easy to tinker with.
* Is extensively [documented](doc/index.md).
* Is excessively [configurable](doc/config.md).
* Despite that, ships with a working configuration and runs out-of-the-box.
* Consists entirely of [modules](doc/modules.md) and therefore can be as minimal
  or bloated as you're comfortable with.
* Supports the latest [IRCv3](doc/ircv3.md) standards.
* Supports multiple linking protocols, including [TS6](doc/ts6.md#supported-software)
  and [JELP](doc/technical/proto/jelp.md).
* Supports [Atheme](http://atheme.org), [PyLink](https://github.com/jlu5/PyLink)
  and probably other IRC services packages.

## Concepts

* __Eventedness__: The core unifying policy of juno is the excessive use of
  events. Just about any operation that occurs is represented as an event. This
  is made possible by [Evented::Object](https://metacpan.org/pod/Evented::Object),
  the base of every class within the IRCd.

```perl
# if it's a server, add the $PROTO_message events
if (my $server = $connection->server) {
    my $proto = $server->{link_type};
    push @events, [ $server, "${proto}_message"        => $msg ],
                  [ $server, "${proto}_message_${cmd}" => $msg ];
    $msg->{_physical_server} = $server;
}

# fire the events
my $fire = $connection->prepare(@events)->fire('safe');
```

* __Extensibility__: Through the use of events and other mechanisms,
  extensibility is another important guideline around which juno is designed. It
  should not be assumed that any commands, modes, prefixes, etc. are fixed or
  finite. They should be changeable, replaceable, and unlimited.

```
[ modes: channel ]
    no_ext        = [ mode_normal, 'n' ]    # no external channel messages
    protect_topic = [ mode_normal, 't' ]    # only ops can set the topic
    ban           = [ mode_list,   'b' ]    # ban
    except        = [ mode_list,   'e' ]    # ban exception
    limit         = [ mode_pset,   'l' ]    # user limit
    forward       = [ mode_pset,   'f' ]    # channel forward mode
    key           = [ mode_key,    'k' ]    # keyword for entry
```

* __Modularity__: By responding to events, [modules](doc/modules.md) add new
  features and functionality. Without them, juno is made up of
  [under thirty lines](https://github.com/cooper/juno/blob/master/bin/ircd) of
  code. Modules work together to create a single functioning body whose parts can
  be added, removed, and modified dynamically. This is made possible by the
  [Evented::API::Engine](https://github.com/cooper/evented-api-engine),
  a class that manages modules and automatically tracks their events.

```
Ban::TS6 10.6
   TS6 ban propagation
   TS6 CAPABILITIES
       BAN, KLN, UNKLN
   TS6 COMMANDS
       BAN, ENCAP_DLINE, ENCAP_KLINE, ENCAP_NICKDELAY
       ENCAP_RESV, ENCAP_UNDLINE, ENCAP_UNKLINE
       ENCAP_UNRESV, KLINE, RESV, UNKLINE, UNRESV
   OUTGOING TS6 COMMANDS
       BAN, BANDEL, BANINFO
```

* __Upgradability__: The beauty of Perl's malleable symbol table makes it
  possible for an entire piece of software to be upgraded or reloaded without
  restarting it. With the help of the
  [Evented::API::Engine](https://github.com/cooper/evented-api-engine) and with
  modularity as a central principle, juno aims to do exactly that. With just
  [one command](doc/modules.md#reload), you can jump up one or one hundred
  versions, all without your users disconnecting.

```
*** Update: k.notroll.net git repository updated to version 12.88 (juno12-mihret-209-g269c83c)
*** Reload: k.notroll.net upgraded from 12.48 to 12.88 (up 88 versions since start)
```

* __Configurability__: Very few values are hard coded. Many have defaults, but
  nearly everything is [configurable](doc/config.md). In spite of that, the
  included working configuration is minimal and easy-to-follow. This is made
  possible by
  [Evented::Configuration](https://metacpan.org/pod/Evented::Configuration).
  [Real-time modification](doc/modules.md#configurationset) of the configuration
  is also feasible, thanks to
  [Evented::Database](https://github.com/cooper/evented-database).

```
[ listen: 0.0.0.0 ]
    port    = [6667..6669, 7000]
    sslport = [6697]
    ts6port = [7050]

[ ssl ]
    cert = 'etc/ssl/cert.pem'   
    key  = 'etc/ssl/key.pem'    
```

* __Efficiency__: Modern IRC servers have a higher per-user load and therefore
  must be prompt at fulfilling requests. Utilizing the wonderful
  [IO::Async](https://metacpan.org/pod/IO::Async) framework, juno is quite
  reactive.

# Setup and operation

## Installation

Before installing juno, install the **tools** for a common building environment
(a compiler, `make`, etc.) Below is an example on a Debian-based distribution.
Also install a few **Perl modules** from the CPAN:

```bash
sudo apt-get install build-essential # or similar
cpanm --sudo IO::Async IO::Socket::IP Socket::GetAddrInfo JSON JSON::XS DBD::SQLite
```

Once you've installed the appropriate Perl packages, **clone the repository**:

```bash
git clone --recursive https://github.com/cooper/juno.git
# OR (whichever is available on your git)
git clone --recurse-submodules https://github.com/cooper/juno.git
```

If your `git` does not support recursive cloning, or if you forgot to specify,
run `git submodule update --init` to check out the submodules.

Next, **pick a release**. The default branch is `master` which is the
development branch and might be broken at any given moment.
```bash
git checkout juno13-ava
```

Now [**set up SSL**](#ssl-setup) if you want or skip to the
[**configuration**](#configuration).

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

juno comes with a working example configuration. So if you want to try it with
next to no effort, just copy `etc/ircd.conf.example` to `etc/ircd.conf`.
The password for the default oper account `admin` is `k`.  

The configuration is, for the most part, self-explanatory. Anything that might
be questionable probably has a comment that explains it. Explanations of all
options are available in the [configuration spec](doc/config.md).

Note that, because juno ships with a configuration suitable for fiddling, the
default values in the `limit` block are rather low. A production IRC server will
likely require less strict limits on connection and client count, for example.

## Operation

Most actions for managing the IRC server are committed with the `juno` script.

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

On Windows, start juno with `juno-start.bat`.

## Upgrading

To upgrade an existing repository, run the following commands:

```bash
git pull origin master
git submodule update --init
git checkout <desired release tag>
```

**OR** (from IRC with the Git module loaded)

1. `/UPDATE`
2. `/CHECKOUT <desired release tag>`
3. `/RELOAD`

# Information

## Contact

Go to [`#k` on `irc.notroll.net`](irc://irc.notroll.net/k).

If you discover a reproducible bug, please
[file an issue](https://github.com/cooper/juno/issues).

## Author

Mitchell Cooper, mitchell@notroll.net  

juno was my first project in Perl — ever. Scary, right? Luckily it's been
through more than 10 years of improvement, including
[a few rewrites](doc/history.md); and I am awfully proud of the current codebase.

## License

This is free software released under the [ISC license](LICENSE).
