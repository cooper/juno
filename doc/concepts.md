# Concepts

These are some of the main concepts within juno's architecture.

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