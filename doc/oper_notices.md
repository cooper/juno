# Oper notice flags

Too lazy to write a proper description for these, so here they are. I will do
that eventually though, probably after adding notice classes/categories.

Opers with `all` receive all notices.

## Local connections
```
new_connection          => '%s (%d)'
connection_terminated   => '%s (%s): %s'
connection_invalid      => '%s: %s'
```

## Users
```
new_user                => '%s [%s] on %s'
user_quit               => '%s [%s] from %s (%s)'
user_opered             => '%s gained flags on %s: %s'
user_deopered           => '%s is no longer an IRC operator'
user_killed             => '%s killed by %s (%s)'
user_nick_change        => '%s is now known as %s'
user_join               => '%s joined %s'
user_part               => '%s parted %s (%s)'
user_part_all           => '%s parted all channels: %s'
user_kick               => '%s was kicked from %s by %s (%s)'
user_mask_change        => '%s switched from (%s@%s) to (%s@%s)'
user_identifier_taken   => '%s introduced %s with UID %s, which is already taken by %s'
user_saved              => '%s was spared in the midst of a nick collision (was %s)'
user_logged_in          => '%s is now logged in as %s'
user_logged_out         => '%s logged out (was %s)'
```

## Servers
```
new_server              => '%s ircd %s, proto %s [%s] parent: %s'
server_closing          => 'Received SQUIT from %s; dropping link (%s)'
server_quit             => '%s quit from parent %s (%s)'
server_burst            => '%s is bursting information'
server_endburst         => '%s finished burst, %d seconds elapsed'
connect                 => '%s issued CONNECT for %s to %s'
connect_attempt         => '%s (%s) on port %d (Attempt %d)'
connect_cancel          => '%s canceled auto connect for %s'
connect_fail            => 'Can\'t connect to %s: %s'
connect_success         => 'Connection established to %s'
squit                   => '%s issued SQUIT for %s from %s'
server_reintroduced     => '%s attempted to introduce %s which already exists'
server_identifier_taken => '%s attempted to introduce %s as SID %d, which is already taken by %s'
server_protocol_warning => '%s %s'
server_protocol_error   => '%s %s; dropping link'
```

## Bans
```
kline           => 'K-Line for %s added by %s, will expire %s (%s) [%s]'
kline_delete    => 'K-Line for %s deleted by %s [%s]'
kline_expire    => 'K-Line for %s expired after %s [%s]'
dline           => 'D-Line for %s added by %s, will expire %s (%s) [%s]'
dline_delete    => 'D-Line for %s deleted by %s [%s]'
dline_expire    => 'D-Line for %s expired after %s [%s]'
resv            => 'Reserve for %s added by %s, will expire %s (%s) [%s]'
resv_delete     => 'Reserve for %s deleted by %s [%s]'
resv_expire     => 'Reserve for %s expired after %s [%s]'
```

## Server management
```
reload          => '%s %s by %s'
update_fail     => 'update to %s git reposity by %s failed'
update          => '%s git repository updated to version %s successfully by %s'
grant           => '%s granted flags to %s: %s'
ungrant         => '%s removed flags from %s: %s'
module_load     => '%s loaded %s (%s)'
module_unload   => '%s unloaded %s'   
module_reload   => '%s reloaded %s'   
```

## Modes
```
user_mode_unknown       => 'Attempted to set %s, but this mode is not defined on %s; ignored'
channel_mode_unknown    => 'Attempted to set %s, but this mode is not defined on %s; ignored'
```

## Miscellaneous
```
perl_warning            => '%s'
exception               => '%s'
rehash                  => '%s is rehashing the server'
rehash_fail             => 'Configuration error: %s'
rehash_success          => 'Server configuration rehashed successfully'
```
