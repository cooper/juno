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

Handle one or more lines of incoming data from the user. The appropriate user command
handlers will be called, or if a command does not exist, `ERR_UNKNOWNCOMMAND` will be sent
to the user.  

This method returns undef and raises a warning if $user does not belong to the local
server or does not have an associated connection object. Handling data from a remote
user may be dangerous but can be achieved instead with `->handle_unsafe()`.

* __$data__: one or more _complete_ lines of data, including any possible trailing
newlines or carriage returns.

### $user->handle_unsafe($data)

Works exactly like `->handle()` except it will not return fail if the user is not
connected directly to the local server.

* __$data__: one or more _complete_ lines of data, including any possible trailing
newlines or carriage returns.

### $user->send($line)

Sends a line of data to the user.  

This method returns undef and raises a warning if $user does not belong to the local
server or does not have an associated connection object. However, some other sending
methods work on remote users such as `->numeric()` and `->server_notice()`.

* __$line__: a line of data WITHOUT a suffixing newline and carriage return.

### $user->sendfrom($from, $line)

Sends a line of data from a source. This is just a convenience method to avoid ugly
concatenation all over the place where it could otherwise be avoided.  

The supplied source should not be an object but instead a string. Typically the `->full`
method of either a user or server will be used. For users, this is `nick!ident@host` where
host is either a cloak or the real host. For a server, the server name is used.

```perl
# where $ouser is some other user.
$user->sendfrom($ouser->full, 'AWAY :gtg bye');

# the above is equivalent to
$user->send(':'.$ouser->full.' AWAY :gtg bye');
```

* __$from__: the source string of the message.
* __$line__: a line of data WITHOUT a suffixing newline and carriage return.

### $user->sendme($line)

Sends a line of data from the server. This is a convenience method to avoid ugly
concatentation all over the place where it could otherwise be avoided.

```perl
$user->sendme("NOTICE $$user{nick} :Hi!");

# the above is equivalent to both of the following:
$user->sendfrom($me->name, "NOTICE $$user{nick} :Hi!");
$user->send(':'.$me->name." NOTICE $$user{nick} :Hi!");

# but just for the record, this is only an example.
# the proper way to achieve the above is:
$user->server_notice('Hi!');
```

* __$line__: a line of data WITHOUT a suffixing newline and carriage return.

### $user->server_notice(optional $info, $message)

Send a notice to the user from the local server.  
This method works on both local and remote users.

* __$info__: _optional_, a brief description of the notice which will be formatted in an
appealing way; e.g. 'kill' for a kill command result.
* __$message__: the notice message to send to the user.

### $user->numeric($const, @args)

* __$const__: the string name of the numeric reply.
* __@args__: _optional_ (depending on the numeric), a list of arguments for the user
numeric handler.

### $user->new_connection

Sends initial information upon user registration. Not for public use.

### $user->send_to_channels($line)

Sends data with the user as the source to all local users who have one or more channels in
common with the user, including himself.

```perl
$user->send_to_channels('NICK steve');
# sends :nick!user@host NICK steve to all users in a common channel with him
```

* __$line__: a line of data WITHOUT a suffixing newline and carriage return.

### $user->do_mode_string($mode_string, $force)

Handles a mode string with `->handle_mode_string()`. If the user is local, a MODE message
will notify the user with the result of any changes. The mode message will then be
forwarded and handled on child servers.

* __$mode_string__: the mode string to be handled; e.g. `+iox`.
* __$force__: if true, failure of user mode blocks will be ignored, forcing the changes.

### $user->do_mode_string_local($mode_string, $force)

Handles a mode string with `->handle_mode_string()`. If the user is local, a MODE message
will notify the user with the result of any changes. Contrary to `->do_mode_string()`, the
mode message will only be handled locally and will not be forwarded to child servers.

* __$mode_string__: the mode string to be handled; e.g. `+iox`.
* __$force__: if true, failure of user mode blocks will be ignored, forcing the changes.

### $user->add_notices(@flags)

Adds any of the supplied oper notice flags that the user does not already have. Oper
notices are not propagated across servers.

* __@flags__: a list of oper notice flags to enable.

### $user->has_notice($flag)

Returns true if the user has the supplied oper notice flag enabled.

* __$flag__: the oper notice flag being tested.

### $user->get_killed_by($murderer, $reason)

Handles a kill on a local level. If the user is not local, this method returns `undef` and
fails. Otherwise, the user will be removed from the server, the message will be forwarded
to child servers, and those in a common channel with him will be notified.

* __$murderer__: the user committing the action.
* __$reason__: the comment for why the user was killed.

### $user->get_invited_by($inviter, $ch_or_name)

Handles an invitation for a local user. If the user is not local or is already in the
channel, this method returns `undef` and fails. Otherwise, an INVITE message will be sent
to the user, and the invitation will be recorded.  

This method accepts either a channel name or a channel object. This is due to the fact
that users may be invited to channels which are not (yet) existent.

* __$inviter__: the user committing the invitation.
* __$ch_or_name__: a channel object or channel name string to which the user was invited.

## Procedural functions

Procedural functions typically involve multiple users and are called as follows:

```perl
user::function(@args)
```

### sendfrom_to_many($from, $line, @users)

Sends a piece of data to several users at once from the specified source. Even if any user
occurs multiple times in the list, the message will only be sent once to each user.  

Note: A variant of this function exists for sending to 

```perl
user::sendfrom_to_many($user->full, 'NICK steve', @users, $user);
# the above example sends a NICK message as follows: :user!ident@hosty NICK steve
# to all of the users within the list @users as well as himself.
```

* __$from__: the source string of the message.
* __$line__: a line of data WITHOUT a suffixing newline and carriage return.
* __@users__: a list of users to send the data to.

## Events

User objects are listened upon by the [pool](pool.md). Most events involving user
interaction with a channel are fired on the [channel](channel.md) object rather than the
user object.

### can_invite

### can_join($channel)

Fired before a local user joins a channel. Callbacks of this event typically run checks
to see if the user can join, stopping the event fire if not. For instance, one such
callback checks if the user is banned.  

This event is never fired for remote users, as it is the responsibility of each server
to determine whether its own users should be able to join a channel.  

This event is fired by the [Core::UserCommands](mod/Core/UserCommands.md) module.

* __$channel__: the channel the user is attempting to join.

#### (30) in.channel

Checks if the user is in the channel already. If so, the event fire is stopped.

#### (20) has.invite

Checks if the channel is invite only. Then, the event fire is stopped if the user has not
been invited to the channel.  

This callback belongs to the [Invite](mod/Invite.md) module.

#### (10) is.banned

Checks if the user is banned from the channel. Unless there is an exception that matches
the user, the event fire is stopped.

### account_registered($act)

Fired after a local user registers an account. Understand that this is not a reliable
event for tracking all account registrations, as it is not fired when remote users
register accounts. This is due to the fact that accounts are sometimes registered without
a user present at all, especially within account negotiation during server burst.  

This event is fired by the [Account](mod/Account.md) module.

* __$act__: a hash reference representing the account information entry.

### account_logged_in($act)

Fired after either a local or remote user logs into an account.  

This event is fired by the [Account](mod/Account.md) module.

* __$act__: a hash reference representing the account information entry.

### account_logged_out($act)

Fired after either a local or remote user logs out of an account.  

This event is fired by the [Account](mod/Account.md) module.

* __$act__: a hash reference representing the account information entry.

## Keys
