# Configuration

This file documents ALL configuration options. Because juno is so excessively
configurable, the less frequently used ones are omitted from the
[example configuration](https://github.com/cooper/juno/blob/master/etc/ircd.conf.example)
but are present here.

## Server info

Basic server info.

    [ server ]

        network     = 'JunoDevNet'                  # network name
        name        = 'devserver.example.com'       # server name
        description = 'juno development server'     # server description
        sex         = 'male'                        # server gender
        id          = 0                             # server ID (must be unique and integral)
        casemapping = 'rfc1459'                     # 'rfc1459' or 'ascii'
                                                    # you MUST use rfc1459 if using TS6
## Modes

Mode definitions. These are omitted from the example configuration because,
when not otherwise specified, defaults are used. These are merely mappings;
you can safely define modes which may not even be present on the server
(due to the providing modules not being loaded) without breaking things.

### User modes

    [ modes: user ]

        ircop         = 'o'                         # IRC operator                         (o)
        invisible     = 'i'                         # invisible mode                       (i)
        ssl           = 'z'                         # SSL connection                       (z)
        registered    = 'r'                         # registered nickname                  (r)
        service       = 'S'                         # network service                      (S)
        deaf          = 'D'                         # does not receive channel messages    (D)
        admin         = 'a'                         # server administrator                 (a)
        wallops       = 'w'                         # receives wallops                     (w)
        bot           = 'B'                         # marks user as a bot                  (B)
        cloak         = 'x'                         # hostname cloaking                    (x)

### Channel modes

- `mode_normal` - no parameter
- `mode_param` - parameter always
- `mode_pset` - parameter only when setting
- `mode_list` - banlike/list mode
- `mode_key` - channel key (special case)

    [ modes: channel ]

        no_ext        = [ mode_normal, 'n' ]        # no external channel messages         (n)
        protect_topic = [ mode_normal, 't' ]        # only operators can set the topic     (t)
        invite_only   = [ mode_normal, 'i' ]        # you must be invited to join          (i)
        free_invite   = [ mode_normal, 'g' ]        # you do not need op to invite         (g)
        free_forward  = [ mode_normal, 'F' ]        # you do not need op in forwad channel (F)
        oper_only     = [ mode_normal, 'O' ]        # you need to be an ircop to join      (O)
        moderated     = [ mode_normal, 'm' ]        # only voiced and up may speak         (m)
        secret        = [ mode_normal, 's' ]        # secret channel                       (s)
        private       = [ mode_normal, 'p' ]        # private channel, hide and no knocks  (p)
        ban           = [ mode_list,   'b' ]        # channel ban                          (b)
        mute          = [ mode_list,   'Z' ]        # channel mute ban                     (Z)
        except        = [ mode_list,   'e' ]        # ban exception                        (e)
        invite_except = [ mode_list,   'I' ]        # invite-only exception                (I)
        access        = [ mode_list,   'A' ]        # Channel::Access module list mode     (A)
        limit         = [ mode_pset,   'l' ]        # Channel user limit mode              (l)
        forward       = [ mode_pset,   'f' ]        # Channel forward mode                 (f)
        key           = [ mode_key,    'k' ]        # Channel key mode                     (k)
        permanent     = [ mode_normal, 'P' ]        # do not destroy channel when empty    (P)
        reg_only      = [ mode_normal, 'r' ]        # only registered users can join       (r)
        ssl_only      = [ mode_normal, 'S' ]        # only SSL users can join              (S)
        strip_colors  = [ mode_normal, 'c' ]        # strip mIRC color codes from messages (c)
        op_moderated  = [ mode_normal, 'z' ]        # send blocked messages to channel ops (z)
        join_throttle = [ mode_pset,   'j' ]        # limit join frequency N:T             (j)
        no_forward    = [ mode_normal, 'Q' ]        # do not forward users to this channel (Q)
        large_banlist = [ mode_normal, 'L' ]        # allow lots of entries on lists       (L)

### Channel status modes

Format is `[ letter, preix, weight, weight to set ]`. Higher weight has more
privileges. Weight `0` is the reference point which should always refer to a
normal channel op.

If the last element is omitted, then any user with weight greater than or equal
to a given status mode can give/take that mode.

The default behavior is that admins can give/take admin,
but halfops cannot give/take halfop. Only ops or higher can.

Note that anything less than -1 (halfop) cannot set/unset any status. This is
because they cannot set any channel modes.

    [ prefixes ]

        owner  = [ 'q', '~',  2    ]                # channel owner                        (q)
        admin  = [ 'a', '&',  1    ]                # channel administrator                (a)
        op     = [ 'o', '@',  0    ]                # channel operator                     (o)
        halfop = [ 'h', '%', -1, 0 ]                # channel half-operator                (h)
        voice  = [ 'v', '+', -2    ]                # voiced channel member                (v)

## Modules

Each entry to the `[api]` block is a module name to load on start. This section
is here merely for demonstration; for a more up-to-date list of available
modules, see [this document](modules.md).

    [ api ]

        # Basic stuff

        Core                        # Loads core commands, modes, etc.
        Resolve                     # Resolve hostnames
        Ident                       # Resolve user identities (ident protocol)
        Cloak                       # Hostname cloaking
        Alias                       # Support for command aliases
        SASL                        # Support for SASL authentication (for services)
        JELP                        # Juno Extensible Linking Protocol
        #TS6                        # TS6 linking protocol

        # Channel features

        Channel::Fantasy            # Fantasy commands
        Channel::Access             # Access list mode (+A)
        Channel::Invite             # Invitation support (INVITE, +i, +I, +g)
        Channel::Key                # Key support (+k)
        Channel::Limit              # Member limit support (+l)
        Channel::Secret             # Secret/private channel support (+s/+p)
        Channel::OperOnly           # Oper-only channel support (+O)
        Channel::Forward            # Channel forward support (+f, +F)
        Channel::Mute               # Mute/quiet bans (+Z)
        Channel::TopicAdditions     # Commands to prepend or append topic
        Channel::Permanent          # Preserve empty channels, make permanent (+P)
        Channel::RegisteredOnly     # Registered only channel support (+r)
        Channel::SSLOnly            # SSL users only channel support (+S)
        Channel::NoColor            # Strip colors from messages (+c)
        Channel::OpModerate         # Sends blocked messages to chanops (+z)
        Channel::ModeSync           # Improves channel mode synchronization
        Channel::JoinThrottle       # Prevents channel join flooding (+j)
        Channel::LargeList          # Enable large ban lists (+L)
        
        # Server management

        Modules                     # Manage IRCd modules directly from IRC
        Git                         # Manage IRCd git repository directly from IRC
        #Configuration::Set         # Manage IRCd configuration directly from IRC
        Reload                      # Reload or upgrade the IRCd in 1 command
        Grant                       # grant user oper flags from IRC
        #Eval                       # Evaluate Perl code directly from IRC

        # Global ban support

        Ban::Dline                  # server/user IP ban (D-Line/Z-Line)
        Ban::Kline                  # user hostmask ban (K-Line)
        Ban::Resv                   # nick and channel reservations (required for services)

        # Extras

        Monitor                     # IRCv3 client availability notifications
        DNSBL                       # Built-in host blacklist checking
        #LOLCAT                     # SPEEK LIEK A LOLCATZ!


## Maximum values

Limits and maximum lengths.

    [ limit ]

        # the maximum number of:

        connection  = 100                           # connections
        perip       = 50                            # local  connections per IP address
        globalperip = 100                           # global connections per IP address
        client      = 80                            # users (currently unused)
        bytes_line  = 2048                          # bytes per line
        lines_sec   = 30                            # lines per second
        channel     = 100                           # channels a user can be in at once
        monitor     = 100                           # monitor entries; off = unlimited

        # the maximum number of characters in:

        nick        = 32                            # nicknames
        topic       = 1000                          # channel topics
        kickmsg     = 300                           # kick messages
        channelname = 50                            # channel names
        away        = 100                           # away messages
        key         = 50                            # channel keys

## File paths

    [ file ]

        motd = 'etc/ircd.motd.example'              # message of the day
        log  = 'var/log/ircd.log'                   # where to write logs

## SSL

    [ ssl ]

        cert = 'etc/ssl/cert.pem'
        key  = 'etc/ssl/key.pem'

## Administrative info

    [ admin ]

        line1 = 'John Doe'
        line2 = 'Server administrator'
        email = 'admin@example.com'

## Server options

    [ servers ]

        ping_freq       = 20                        # how often to send pings
        ping_timeout    = 300                       # seconds with no pong to drop server
        ping_warn       = 60                        # seconds to warn about pings

        delta_max       = 120                       # max time delta in seconds
        delta_warn      = 30                        # time delta to produce a warning
        
        allow_hidden    = on                        # allow servers to hide themselves

## User options

    [ users ]

        automodes       = '+ix'                     # set these modes on users at connect

        chghost_quit    = on                        # quit and rejoin on host change
        allow_uid_nick  = on                        # allow NICK 0 command
        notify_uid      = off                       # send UID to users on connect

        ping_freq       = 30                        # how often to send pings
        ping_timeout    = 120                       # seconds with no pong to drop user

## Channel options

    [ channels ]

        automodes = '+ntqo +user +user'             # set these modes as users enter channel

        invite_must_exist           = off           # restrict INVITE to existing channels
        only_ops_invite             = off           # restrict INVITE to chanops
        resv_force_part             = on            # force users to part RESV'd channels

        client_max_modes_simple     = 46            # max simple mode count per msg
        client_max_mode_params      = 10            # max mode params per msg, MODES in RPL_ISUPPORT

        max_modes_per_line          = 5             # max modes per outgoing MODE message
        max_modes_per_server_line   = 10            # same as above, except for servers
        max_param_length            = 50            # number of characters permitted for parameters
        max_ban_length              = 195           # number of characters permitted for a ban
        max_bans                    = 100           # number of bans permitted per channel
        max_bans_large              = 500           # number of bans permitted with Channel::LargeList (+L)

### Fantasy commands

The commands present here are valid for use as
[fantasy commands](modules.md#channelfantasy). Commands that are not available
to the server are quietly ignored. This is omitted from the example
configuration.

    [ channels: fantasy ]

        kick
        topic
        part
        names
        modelist
        up                                          # any of these fantasy commands can be
        down                                        # disabled from the normal conf with:
        topicprepend                                # [ channels: fantasy ]
        topicappend                                 #      <command> = off
        mode
        eval
        lolcat

## Services options

    [ services ]

        nickserv = 'NickServ'       # nickname of nick service. used with TS6
        saslserv = 'SaslServ'       # nickname of SASL service. used by SASL
        
        saslserv_allow_reauthentication = on    # allow reauthentication?
        saslserv_max_failures = 3               # SASL failures before dropping

## Listening

`[listen]` blocks are named by the host to listen on.

Examples below include dedicated ports for linking protocols. This is required
for all linking protocols except for JELP, which may share ports with the
client protocol.

    # all IPv4 hosts
    [ listen: 0.0.0.0 ]

        port        = [6667..6669, 7000]            # unsecured listening ports
        sslport     = [6697]                        # secure ports
        ts6port     = [7001]                        # proto-specific port
        ts6sslport  = [7002]                        # proto-specific SSL port

    # all IPv6 hosts
    [ listen: :: ]

        port    = [6667..6669, 7000]                # unsecured listening ports
        sslport = [6697]                            # secure ports

## Server uplinks

`[connect]` blocks are named by the server name.

    [ connect: server2.example.com ]

        # Address(es) to accept connection from.
        # MUST be IP addresses, not hostnames.
        # Wildcards are accepted. Any number of address allowed.

            address = ['192.168.1.\*', '127.0.0.1']

        # Outgoing port. If initiating a connection, the server will try this port.
        # Currently, this option does not affect incoming connections.

            port = 7000

        # Enable SSL connection? If so, be sure that the above port is an SSL listen
        # port and that the other server has SSL configured properly. This setting
        # is only applicable to outgoing connections which this server initiates.

            ssl = on

        # Plain text outgoing password

            send_password = 'k'

        # Incoming password and the encryption for it.
        # Accepted crypts: sha1, sha224, sha256, sha384, sha512, md5, none

            receive_password = '13fbd79c3d390e5d6585a21e11ff5ec1970cff0c'
            encryption       = 'sha1'

        # Auto connect on startup. Note that this only applies to when the server
        # is first started. To reconnect dropped connections, see auto_timer.

            #autoconnect

        # Reconnect timer. If connection drops, try again every x seconds.
        # Uncomment below if you wish to enable this feature.

            #auto_timer = 30

## IRC operators

`[oper]` blocks are named by the oper name used with the `OPER` command.

    [ oper: admin ]

        # Operator class (optional).
        # If present, the oper will receive flags and notices defined in this class
        # and all other classes from which it may inherit.

            class = 'netadmin'

        # Hostmask(s) to accept for opering.
        # These can include either hostnames or IP addresses.
        # Multiple values accepted. Wildcards accepted.

            host = ['*@*']

        # The password and encryption for it

            password   = '13fbd79c3d390e5d6585a21e11ff5ec1970cff0c'
            encryption = 'sha1'

        # Flags (optional).
        # Oper flags which are specific to this oper. These will be granted in
        # conjunction with any others that might exist from oper classes.
        # Multiple flags accepted. Wildcards NOT accepted.
        # See doc/oper_flags.md. 'all' matches all flags.

            flags = ['all']

        # Oper notice flags (optional).
        # Notice flags which are specific to this oper. These will be granted in
        # conjunction with any others that might exist from oper classes.
        # Multiple flags accepted. Wildcards not accepted. 'all' matches all flags.

            notices = ['all']
        
IRC operator classes. These are omitted from the example configuration. The
default ones here may be outdated; see the
[default configuration](https://github.com/cooper/juno/blob/master/etc/default.conf)
for up-to-date info. `[operclass]` blocks are named by the name of the oper
class which may be specified as the `class` option in `[oper]` blocks.

    [ operclass: local ]

        flags = [ 'kill', 'see_invisible', 'rehash' ]

    [ operclass: global ]

        extends = 'local'
        flags   = [ 'gkill', 'grehash' ]

    [ operclass: netadmin ]

        extends = 'global'
        flags   = [ 'grant' ]
        notices = [ 'all' ]

## Command aliases

Requires Alias module.

- `$N` will be replaced with the Nth parameter;
- `$N-` will be replaced with the Nth parameter and all which follow it.

The default ones here may be outdated; see the
[default configuration](https://github.com/cooper/juno/blob/master/etc/default.conf)
for up-to-date info.

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

## DNS blacklists

Requires DNSBL module.

    [ dnsbl: EFnetRBL ]

        host     = "rbl.efnetrbl.org"
        ipv4     = on
        ipv6     = off
        timeout  = 3
        duration = '1d'
        reason   = "Your host is listed on EFnet RBL. See http://efnetrbl.org/?i=%ip"

    [ dnsbl: DroneBL ]

        host     = "dnsbl.dronebl.org"
        ipv4     = on
        ipv6     = on
        timeout  = 3
        duration = '1d'
        reason   = "Your host is listed on DroneBL. See http://dronebl.org/lookup?ip=%ip"

    [ dnsbl: dan.me.uk ]

        host     = "tor.dan.me.uk"
        ipv4     = on
        ipv6     = off
        timeout  = 3
        matches  = [100]
        duration = '1d'
        reason   = "Your host is listed as a Tor node."

## Administrator information

[ admin ]

    line1 = 'John Doe'
    line2 = 'Server administrator'
    email = 'admin@example.com'

## IRCd definitions

These are used for linking with many types of servers. Generally you do not need
this in your configuration, unless you intend to link juno with a server that is
not supported by default.

    [ ircd: fakeIRCd ]

        fakeircd_based  = on            # for all ircds, you should include a $NAME_based
                                        # key so that this can be used as a last resort
                                        # guess for whether a certain feature is supported
                                        
        extends         = 'charybdis'   # optionally specify another IRCd definition to
                                        # inherit options from
                                        
        nicklen         = 31            # max nick length
        
        no_host_slashes = off           # '/' not permitted in hosts
        
        truncate_hosts  = 63            # truncate hosts to this length
        
        burst_topicwho  = on            # in TS6, include the 'setby' param in TB command
        
    [ ircd_umodes: fakeIRCd ]
    
        # user modes in the same format as in [ modes: user ]
        service       = 'S'                         # network service                      (S)
        ssl           = 'Z'                         # using SSL                            (Z)
        deaf          = 'D'                         # does not receive channel messages    (D)
        admin         = 'a'                         # server administrator                 (a)
        wallops       = 'w'                         # receives wallops                     (w)
        cloak         = 'x' # or 'h'!               # cloaking is enabled                  (x)

    [ ircd_cmodes: fakeIRCd ]

        # channel modes in the same format as [ modes: channel ]
        mute          = [ mode_list,   'q' ]        # channel mute ban                     (q)
        free_invite   = [ mode_normal, 'g' ]        # you do not need op to invite         (g)
        forward       = [ mode_pset,   'f' ]        # forward users if they cannot enter   (f)
        free_forward  = [ mode_normal, 'F' ]        # you do not need op in forwad channel (F)
        oper_only     = [ mode_normal, 'O' ]        # you need to be an ircop to join      (O)
        join_throttle = [ mode_pset,   'j' ]        # limit join frequency N:T             (j)
        large_banlist = [ mode_normal, 'L' ]        # allow lots of entries on lists       (L)
        permanent     = [ mode_normal, 'P' ]        # do not destroy channel when empty    (P)
        no_forward    = [ mode_normal, 'Q' ]        # do not forward users to this channel (Q)
        strip_colors  = [ mode_normal, 'c' ]        # strip mIRC color codes from messages (c)
        op_moderated  = [ mode_normal, 'z' ]        # send blocked messages to channel ops (z)
        
        
    [ ircd_prefixes: elemental ]

        # channel prefixes in the same format as [ prefixes ]
        owner  = [ 'y', '~',  2 ]                   # channel owner                        (y)
        admin  = [ 'a', '!',  1 ]                   # channel administrator                (a)
        op     = [ 'o', '@',  0 ]                   # channel operator                     (o)
        halfop = [ 'h', '%', -1 ]                   # channel half-operator                (h)
        voice  = [ 'v', '+', -2 ]                   # voiced channel member                (v)
