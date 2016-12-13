# IRC operator flags

Anything with (g) in front of it means that the 'g' prefix is optional to
specify whether the privilege works remotely.

### all

Those with all are gods, capable of anything.

### grant

Use GRANT command. Note that this allows the user to apply any flags to himself,
even "all."

### (g)rehash

Reload the local server configuration or remote servers (g)lobally.

### see_invisible

See invisible (+i) users where they would otherwise be hidden.

### see_hosts

Show users' hostnames and IP addresses in WHOIS.

### see_secret

See secret and private channels where they would otherwise be hidden.

### (g)squit

Disconnect links to the local server or issue SQUIT command (g)lobally.

### (g)connect

Establish links to the local server or issue CONNECT command (g)lobally.

### (g)kill

Kill users locally or (g)lobally.

### modules

Use MODLOAD, MODUNLOAD, and MODRELOAD commands.

### (g)update

Update the git repository on the local server or (g)lobally.

### (g)checkout

Switch branches or commits on the git repository of the local server or
(g)lobally.

### (g)reload

Issue a RELOAD command locally or (g)lobally.

### kline

Add and remove K-Lines.

### dline

Add and remove D-Lines.

### resv

Add and remove channel and nickname reservations.

### list_bans

View K-Lines, D-Lines, etc.

### (g)confget

Use CONFGET command to view the server configuration locally or (g)lobally.

### (g)confset

Use CONFSET command to dynamically modify the server configuration locally or
(g)lobally.

### set_permanent

Mark channels as permanent (+P) or temporary.
