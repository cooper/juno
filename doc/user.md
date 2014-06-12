# user

The `ircd::user` submodule of [ircd](ircd.md) provides the `user` package whose instances
represent IRC users, both local and remote.

## Methods

### user->new(%opts)

Creates a new object. This class method should almost never be used directly; you should
probably look at [pool](pool.md)'s `->new_user()` method instead.

```perl
my $user = $pool->new_user(
    nick  => 'Steve',
    ident => '~steve',
    host  => 'server.example.com',
    cloak => 'server.example.com',
    ip    => '93.184.216.119'
);
```

* __%opts__: a hash of constructor options.

### $user->set_mode($mode_name)

The lowest level of mode setting on a user. This method does not tell anyone about the
change; see `->handle_mode_string()`, `->do_mode_string()`, and `->do_mode_string_local()`
for ways to achieve that.

* __$mode_name__: the name of the mode being set.

### $user->unset_mode($mode_name)

The lowest level of mode unsetting on a user. This method does not tell anyone about the
change; see `->handle_mode_string()`, `->do_mode_string()`, and `->do_mode_string_local()`
for ways to achieve that.

* __$mode_name__: the name of the mode being unset.

### $user->is_mode($mode_name)

Returns true if the user has the supplied mode set.

* __$mode_name__: the name of the mode being tested.

### $user->quit($reason)

The lowest level of user quitting for both local and remote users. This should not be used
to terminate a connection or to remove a user from the network but instead only to handle
such situations. To terminate the connection of a local user, you should use the
`->done()` method of the user's associated [connection](connection.md) object, which will
in turn call this method after dropping the connection.  

All event callbacks will be deleted as this method prepares the user object for disposal.

* __$reason__: the reason for quitting; e.g. `~ Off to milk the cow!`.

### $user->change_nick($new_nick)

The lowest level of user nickname changing. This method does not notify any users of the
change. There is currently no method for safely changing nicknames; so `->change_nick()`
should not be used directly at this time.  

Returns the new nickname if successful otherwise `undef`.

* __$new_nick__: the nickname to replace the current nickname.

### $user->handle_mode_string($mode_string, $force)

The lowest level of mode string handling. This method does not notify other users or
servers of the change. It only calls `->set_mode()` and `->unset_mode()` after firing
any possible user mode blocks. See `->do_mode_string()` and `->do_mode_string_local()` for
the different ways to handle mode strings at a higher level.  

Returns a mode string of changes that occurred such as `+ix`.

* __$mode_string__: the mode string to be handled; e.g. `+iox`.
* __$force__: if true, failure of user mode blocks will be ignored, forcing the changes.

### $user->mode_string

Returns a string of all the modes set on the user; e.g. `+iox`.

### $user->add_flags(@flags)

The lowest level of oper flag handling. Adds any of the supplied oper flags that the user
does not have already. Other servers and users will not be notified of the change. There
is currently no method for safely adding flags, so `->add_flags()` should not be used
directly at this time.

* __@flags__: a list of oper flags to add.

### $user->remove_flags(@flags)

The lowest level of oper flag handling. Removes any of the supplied oper flags that the
user has enabled. Other servers and users will not be notified of the change. There
is currently no method for safely removing flags, so `->remove_flags()` should not be used
directly at this time.

* __@flags__: a list of oper flags to remove.

### $user->has_flag($flag)

Returns true if the user has the specified oper flag enabled.

* __$flag__: the name of the flag being tested; e.g. `kill`.

### $user->set_away($reason)

The lowest level of marking a user as away. This method does not notify any other users
or servers; it only handles the actual setting upon the user object. There is currently no
method for safely setting a user as away, so `->set_away()` should not be used directly
at this time.

* __$reason__: the comment for why the user is away.

### $user->unset_away

The lowest level of marking a user as here. This method does not notify any other users
or servers; it only handles the actual setting upon the user object. There is currently no
method for safely setting a user as here, so `->unset_away()` should not be used directly
at this time.

### $user->is_local

Returns true if the user belongs to the local server.

### $user->full

Returns a string of `nick!ident@host` where host may be either an artificial host (cloak)
or the actual hostname.

### $user->fullreal

Returns a string of `nick!ident@host` where host is always the actual hostname, ignoring
any possible cloak or artificial host. Most of the time, `->full` is favored over this
method if the return value may be exposed to other users.

### $user->fullip

Returns a string of `nick!ident@host` where host is the human-readable IP address of the
user, completely ignoring any host or cloak.

### $user->notice_info

Returns a list of the user's nick, ident, and actual host in that order. Useful for oper
notices where these three items are commonly displayed.

## Mine methods

### $user->handle($data)

### $user->handle_unsafe($data)

### $user->send($line)

### $user->sendfrom($from, $message)

### $user->sendme($message)

### $user->server_notice(optional $info, $message)

### $user->numeric($const, @args)

### $user->new_connection

### $user->send_to_channels($message)

### $user->do_mode_string($mode_string, $force)

### $user->do_mode_string_local($mode_string, $force)

### $user->add_notices(@flags)

### $user->has_notice($flag)

### $user->get_killed_by($murderer, $reason)

### $user->get_invited_by($inviter, $ch_or_name)

## Procedural functions

### sendfrom_to_many($from, $message, @users)

## Events

User objects are listened upon by the [pool](pool.md). Most events involving user
interaction with a channel are fired on the [channel](channel.md) object rather than the
user object.

### can_invite

### can_join

### account_registered

### account_logged_in

### account_logged_out

## Keys
