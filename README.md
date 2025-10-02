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

## YES, this project is maintained!

As of Q4 2025, this project is being developed during my free time. I'm currently
building out additional IRCv3 capabilities and working on InspIRCd linking. Since
PyLink is no longer maintained, and juno has strong foundations for modules and
hot reloading, I intend to expand its bridging capabilities. I am all ears for
other feature requests.

## Features

Here are some things that make juno stand out. You can

* [Check out](doc/modules.md#git) the latest code and [hot reload](doc/modules.md#reload)
  your entire network with one IRC command, without restarting servers or dropping a
  single connection.
* [Link](doc/ts6.md#supported-software) a complex network of various IRCds and
  services packages spanning multiple server protocols.
* [Configure](doc/modules.md#configurationset) servers en masse directly from IRC.
* [Write](doc/index.md#technical) modules for the easy-to-use event-based
  module API.

Plus, juno

* Is free and open-source with [over 15 years of development](doc/history.md).
* Is written in Perl, making it fun and easy to tinker with and extend.
* Is already way more feature-complete than you're likely expecting.
* Is extensively [documented](doc/index.md).
* Is excessively [configurable](doc/config.md), but also runs out-of-the-box.
* Consists entirely of [modules](doc/modules.md) that can be optionally loaded.
* Supports the latest [IRCv3](doc/ircv3.md) standards.
* Supports multiple server protocols, including [TS6](doc/ts6.md#supported-software)
  and [JELP](doc/technical/proto/jelp.md).
* Fully supports most IRC Services (Atheme, Anope, PyLink, etc.).

See [Concepts](doc/concepts.md) for more on my goals for juno.

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
The password for the default oper account `admin` is `k`. You'll want to change that.

The config is for the most part self-explanatory, but the [configuration spec](doc/config.md)
has all the details.

Note that, because juno ships with a configuration suitable for fiddling, the
default values in the `limit` block are rather low. A production IRC server may
require higher limits on connection and client count, for example.

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

* __debug__: Runs the IRCd in the foreground, printing the logging output. Note,
 the log messages do NOT include raw messages as many IRC softwares do in debug mode.

* __forever__: Runs the IRCd continuously in the background. In other words, if
  it is stopped for any reason (such as a crash or exploit or SHUTDOWN), it will
  start again (with an incremental timeout if stopping repeatedly).

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

[File issues and feature requests here.](https://github.com/cooper/juno/issues)

## Author

Mitchell Cooper, aka cooper on irc.notroll.net #k

I've been working on this forever; see [history](doc/history.md)

## License

This is free software released under the [ISC license](LICENSE).
