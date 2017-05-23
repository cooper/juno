# IRC operator flags

Anything with (g) in front of it means that the 'g' prefix is optional to
specify whether the privilege works remotely.

### all

Those with all are gods, capable of anything.

### grant

Use `GRANT` to add and remove oper privileges from a user. Note that this allows
the user to apply any flags to himself as well.

### (g)rehash

Reload the server configuration with `REHASH`.

### see_invisible

See invisible (+i) users where they would otherwise be hidden.

### see_hidden

Show hidden servers in commands like `MAP` and `LINKS`.

### see_hosts

Show users' hostnames and IP addresses in `WHO` and `WHOIS`.

### see_secret

See secret (+s) and private (+p) channels where they would otherwise be hidden.

### (g)squit

Disconnect uplinks from the server with `SQUIT`.

### (g)connect

Establish uplinks to the server with `CONNECT`.

### (g)kill

Remove a user from the server with the `KILL` command.

### modules

Use `MODLOAD`, `MODUNLOAD`, and `MODRELOAD` commands.

### (g)update

Update the server git repository with `UPDATE`.

### (g)checkout

Switch the server git repository to a different release with `CHECKOUT`.

### (g)reload

Reload the server with the `RELOAD` command.

### kline

Add and remove K-Lines with `KLINE` and `UNKLINE`.

### dline

Add and remove D-Lines with `DLINE` and `UNDLINE`.

### resv

Add and remove channel and nickname reservations with `RESV` and `UNRESV`.

### list_bans

View K-Lines, D-Lines, etc. with the `BANS` command.

### (g)confget

Use `CONFGET` to view the server configuration.

### (g)confset

Use `CONFSET` to dynamically modify the server configuration.

### set_permanent

Mark channels as permanent (+P).

### set_large_banlist

Enable large channel ban lists (+L).

### modesync

Fix channel desyncs with the `MODESYNC` command.
