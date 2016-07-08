# user

The `ircd::user` submodule of [ircd](ircd.md) provides the `user` package whose instances
represent IRC users, both local and remote.

## Low-level methods

### user->new(%opts)

Creates a new user object. This class method should almost never be used directly;
you should probably look at [pool](pool.md)'s `->new_user()` method instead.

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

### $user->is_mode($mode_name)

Returns true if the user has the supplied mode set.

* __$mode_name__: the name of the mode being tested.

### $user->set_mode($mode_name)

The lowest level of mode setting on a user. This method does not tell anyone about the
change; see
[`->handle_mode_string()`](#user-handle_mode_stringmode_string-force),
[`->do_mode_string()`](#user-do_mode_stringmode_string-force), and
[`->do_mode_string_local()`](#user-do_mode_string_localmode_string-force)
for ways to achieve that.

* __$mode_name__: the name of the mode being set.

### $user->unset_mode($mode_name)

The lowest level of mode unsetting on a user. This method does not tell anyone about the
change; see
[`->handle_mode_string()`](#user-handle_mode_stringmode_string-force),
[`->do_mode_string()`](#user-do_mode_stringmode_string-force), and
[`->do_mode_string_local()`](#user-do_mode_string_localmode_string-force)
for ways to achieve that.

* __$mode_name__: the name of the mode being unset.

### $user->handle_mode_string($mode_string, $force)

The lowest level of mode string handling. This method does not notify other users or
servers of the change. It only calls
[`->set_mode()`](#user-set_modemode_name) and
[`->unset_mode()`](#user-unset_modemode_name) after firing
any possible user mode blocks. See
[`->do_mode_string()`](#user-do_mode_stringmode_string-force) and
[`->do_mode_string_local()`](#user-do_mode_string_localmode_string-force) for
the different ways to handle mode strings at a higher level.  

Returns a mode string of changes that occurred such as `+ix`.

* __$mode_string__: the mode string to be handled; e.g. `+iox`.
* __$force__: _optional_, if true, failure of user mode blocks will be ignored, forcing the changes.

### $user->mode_string

Returns a string of all the modes set on the user; e.g. `+iox`.

### $user->has_flag($flag)

Returns true if the user has the specified oper flag enabled.

* __$flag__: the name of the flag being tested; e.g. `kill`.

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

### $user->has_notice($flag)

Returns true if the user has the supplied oper notice flag enabled.

* __$flag__: the oper notice flag being tested.

### $user->add_notices(@flags)

Adds any of the supplied oper notice flags that the user does not already have. Oper
notices are not propagated across servers.

* __@flags__: a list of oper notice flags to enable.

### $user->change_nick($new_nick)

The lowest level of user nickname changing. This method does not notify any users of the
change. There is currently no method for safely changing nicknames; so `->change_nick()`
should not be used directly at this time.  

Returns the new nickname if successful otherwise `undef`.

* __$new_nick__: the nickname to replace the current nickname.

### $user->set_away($reason)

The lowest level of marking a user as away. This method does not notify any other users
or servers; it only handles the actual setting upon the user object. There is currently no
method for safely setting a user as away, so `->set_away()` should not be used directly
at this time.

* __$reason__: the comment for why the user is away.

### $user->unset_away()

The lowest level of marking a user as here. This method does not notify any other users
or servers; it only handles the actual setting upon the user object. There is currently no
method for safely setting a user as here, so `->unset_away()` should not be used directly
at this time.

### $user->quit($reason)

The lowest level of user quitting for both local and remote users. This should not be used
to terminate a connection or to remove a user from the network but instead only to handle
such situations. To terminate the connection of a local user, you should use the
`->done()` method of the user's associated [connection](connection.md) object, which will
in turn call this method after dropping the connection.  

All event callbacks will be deleted as this method prepares the user object for disposal.

* __$reason__: the reason for quitting; e.g. `~ Off to milk the cow!`.

### $user->channels

Returns the complete list of channel objects the user is a member of.

### $user->is_local

Returns true if the user belongs to the local server.

### $user->full

Returns a string of `nick!ident@host` where host may be either an artificial host (cloak)
or the actual hostname.

### $user->fullreal

Returns a string of `nick!ident@host` where host is always the actual hostname, ignoring
any possible cloak or artificial host. Most of the time, [`->full`](#user-full)
is favored over this method if the return value may be exposed to other users.

### $user->fullip

Returns a string of `nick!ident@host` where host is the human-readable IP address of the
user, completely ignoring any host or cloak.

### $user->notice_info

Returns a list of the user's nick, ident, and actual host in that order. Useful for oper
notices where these three items are commonly displayed.

### $user->hops_to($target)

Returns the number of hops to a server or to another user.

* __$target__: either a user or server object. if it's a user, the result is the
same as calling with `$target->server`.

### $user->id

Returns the internal identifier associated with the user.
This is unique globally.

### $user->name

Returns the user's nickname.

### $user->server

Returns the server object that this user belongs to, regardless of whether the
server is directly linked to the local one.

## High-level methods

### $user->server_notice($info, $message)

Send a notice to the user from the local server. This method works on both local
and remote users.

* __$info__: _optional_, a brief description of the notice which will be formatted in an
appealing way; e.g. 'kill' for a kill command result.
* __$message__: the notice message to send to the user.

### $user->numeric($const, @args)

Send a numeric reply to the user from the local server. This method works on
both local and remote users. The string is formatted locally so that remote
servers do not have to understand the numeric.

* __$const__: the string name of the numeric reply.
* __@args__: _optional_ (depending on the numeric), a list of arguments for the user
numeric handler.

### $user->handle_unsafe($data)

Emulates that the user sent a piece of data to the local server. It is called
unsafe because it assumes that the command handler(s) are capable of dealing
with emulated data from remote users.

Works exactly like [`->handle()`](#user-handledata) except it will not return
fail if the user is not connected directly to the local server.

* __$data__: one or more _complete_ lines of data, including any possible trailing
newlines or carriage returns.

### $user->handle_with_opts_unsafe($data, %opts)

Same as [`->handle_unsafe()`](#user-handle_unsafedata), except that the provided
options will be passed to the underlying call.

* __$data__: one or more _complete_ lines of data, including any possible trailing
newlines or carriage returns.
* __%opts__: _optional_, a hash of options to pass to the underlying function call.

### $user->get_mask_changed($new_ident, $new_host)

Handles an ident or cloak change. This method updates the user fields and
notifies local clients when necessary. If neither the ident nor the cloak has
changed, the call does nothing.

Clients with the [`chghost`](http://ircv3.net/specs/extensions/chghost-3.2.html)
capability will receive a CHGHOST command. Others will receive a quit and
rejoin emulation, unless `users:chghost_quit` is explicitly disabled.

* __$new_ident__: the new ident. if unchanged, the current ident MUST be passed.
* __$new_host__: the new cloak. if unchanged, the current cloak MUST be passed.

### $user->save_locally

Deals with a user who was saved from a nick collisions on a local level.
Changes the user's nickname to his unique identifier.

This method works under the presumption that remote servers have been notified
(such as through a SAVE, NICK, or similar message) that the user was saved and
will adopt his UID as his nickname.

### $user->do_away($reason)

Processes an away or return for both local and remote users. Calls
[`->set_away()`](#user-set_awayreason) or
[`->unset_away()`](#user-unset_away),
depending on whether the reason is
provided. If the user is local, he receives a numeric notification.

Other local clients may be notified by an AWAY message if they have the
[`away-notify`](http://ircv3.net/specs/extensions/away-notify-3.1.html)
capability.

* __$reason__: _optional_, the away comment. if undefined or empty string,
the user is considered to have returned from being away.

### $user->do_part_all()

Parts the user from all channels, notifying local clients. This is typically
initiated by a `JOIN 0` command.

### $user->do_login($act_name, $no_num)

Logs the user into the given account name. If the user is local, he receives a
numeric notification.

Other local clients may be notified by an ACCOUNT message if they have the
[`account-notify`](http://ircv3.net/specs/extensions/account-notify-3.1.html)
capability.

* __$act_name__: the name of the account.
* __$no_num__: _optional_, if provided, the user will not receive a numeric
reply. this is useful if the reply was already sent before calling this method,
such as during SASL authentication.

### $user->do_logout()

Logs the user out from their current account. If they are not logged in, the
method does nothing. If the user is local, he receives a numeric notification.

Other local clients may be notified by an ACCOUNT message if they have the
[`account-notify`](http://ircv3.net/specs/extensions/account-notify-3.1.html)
capability.

### $user->do_mode_string($mode_string, $force)

Handles a mode string with
[`->handle_mode_string()`](#user-handle_mode_stringmode_string-force).
If the user is local, a MODE message
will notify the user with the result of any changes. The mode message will then be
forwarded and handled on child servers.

* __$mode_string__: the mode string to be handled; e.g. `+iox`.
* __$force__: _optional_, if true, failure of user mode blocks will be ignored,
forcing the changes.

### $user->do_mode_string_local($mode_string, $force)

Handles a mode string with
[`->handle_mode_string()`](#user-handle_mode_stringmode_string-force).
If the user is local, a MODE message
will notify the user with the result of any changes.

Unlike [`->do_mode_string()`](#user-do_mode_stringmode_string-force), the
mode message will only be handled locally and will NOT be forwarded to remote servers.

* __$mode_string__: the mode string to be handled; e.g. `+iox`.
* __$force__: _optional_, if true, failure of user mode blocks will be ignored,
forcing the changes.

### $user->do_mode_string_unsafe($mode_string, $force)

Handles a mode string with
[`->handle_mode_string()`](#user-handle_mode_stringmode_string-force).
If the user is local, a MODE message
will notify the user with the result of any changes. The mode message will then be
forwarded and handled on child servers, regardless of whether the user is local.

Unlike [`->do_mode_string()`](#user-do_mode_stringmode_string-force),
linked servers will be notified of the change even if the
user is remote. The result is that the local server forces a mode change on a remote
user. That is why this is called unsafe and should be used with caution.

* __$mode_string__: the mode string to be handled; e.g. `+iox`.
* __$force__: _optional_, if true, failure of user mode blocks will be ignored,
forcing the changes.

### $user->send_to_channels($line, %opts)

Sends data with the user as the source to all local users who have one or more channels in
common with the user.

The user himself will also receive the message, regardless of whether he has joined
any channels.

```perl
$user->send_to_channels('NICK steve');
# sends :nick!user@host NICK steve to all users in a common channel with him
```

* __$line__: a line of data WITHOUT a suffixing newline and carriage return.
* __%opts__: _optional_, a hash of options to pass to the underlying
`sendfrom_to_many_with_opts()` function.

## Local-only methods

### $user->handle($data)

Handle one or more lines of incoming data from the user. The appropriate user command
handlers will be called, or if a command does not exist, `ERR_UNKNOWNCOMMAND` will be sent
to the user.  

This method returns undef and raises a warning if $user does not belong to the local
server or does not have an associated connection object. Handling data from a remote
user may be dangerous but can be achieved instead with
[`->handle_unsafe()`](#user-handle_unsafedata).

* __$data__: one or more _complete_ lines of data, including any possible trailing
newlines or carriage returns.

### $user->handle_with_opts($data, %opts)

Same as [`->handle()`](#user-handledata), except that the provided options will
be passed to the underlying call.

* __$data__: one or more _complete_ lines of data, including any possible trailing
newlines or carriage returns.
* __%opts__: _optional_, a hash of options to pass to the underlying function call.

### $user->send($line)

Sends a line of data to the user.  

This method returns undef and raises a warning if $user does not belong to the local
server or does not have an associated connection object. However, some other sending
methods work on remote users such as
[`->numeric()`](#user-numericconst-args) and
[`->server_notice()`](#user-server_noticeinfo-message).

* __$line__: a line of data WITHOUT a suffixing newline and carriage return.

### $user->sendfrom($from, $line)

Sends a line of data from a source. This is just a convenience method to avoid ugly
concatenation all over the place where it could otherwise be avoided.  

The supplied source should not be an object but instead a string. Typically the
[`->full`](#user-full) method of either a user or server will be used. For users,
this is `nick!ident@host` where host is either a cloak or the real host. For a
server, its name is used.

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

### $user->loc_get_killed_by($murderer, $reason)

Handles a kill on a local level. If the user is not local, this method returns `undef` and
fails. Otherwise, the user will be removed from the server, the message will be forwarded
to child servers, and those in a common channel with him will be notified.

* __$murderer__: the user committing the action.
* __$reason__: the comment for why the user was killed.

### $user->loc_get_invited_by($inviter, $ch_or_name)

Handles an invitation for a local user. If the user is not local or is already in the
channel, this method returns `undef` and fails. Otherwise, an INVITE message will be sent
to the user, and the invitation will be recorded locally.  

This method accepts either a channel name or a channel object. This is due to the fact
that users may be invited to channels which are not yet existent
(unless `channels:invite_must_exist` is enabled).

* __$inviter__: the user offering the invitation.
* __$ch_or_name__: a channel object or channel name string to which the user was invited.

### $user->has_cap($flag)

Returns true if the user has a particular client capability enabled.

* __$flag__: the name of the capability.

### $user->add_cap($flag)

Enables a client capability.

* __$flag__: the name of the capability.

### $user->remove_cap($flag)

Disables a client capability.

* __$flag__: the name of the capability.

### $user->conn

Returns the connection object associated with the user.

## Procedural functions

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

### sendfrom_to_many_with_opts($from, $line, \%opts, @users)

Same as [`sendfrom_to_many()`](#sendfrom_to_manyfrom-line-users),
except that additional features may be used
through the added options argument.

* __$from__: the source string of the message.
* __$line__: a line of data WITHOUT a suffixing newline and carriage return.
* __\%opts__: _optional_, a hash reference of options.
* __@users__: a list of users to send the data to.

#### Supported options

* __ignore__: _optional_, a user object to ignore. if it is found in the
provided list of users, it is skipped. the user will receive no data.
* __no_self__: _optional_, if true, the user identified by the mask `$from` will
be ignored. the user will be skipped and will receive no data. this is
particularly useful for messages intended to notify other local clients about
the user's changes but which are not necessary to send to the user himself due
to other numeric replies.
* __cap__: _optional_, a client capability. if provided, the message will only
be sent to users with this capability enabled.
* __alternative__: _optional_, if the `cap` option was provided, this option
defines an alternative line of data to send to users without the specified
capability. without `cap`, this option has no effect.

## Events

User objects are listened upon by the [pool](pool.md). Most events involving user
interaction with a channel are fired on the [channel](channel.md) object rather than the
user object.

### can_join($channel)

Fired before a local user joins a channel. Callbacks of this event typically run checks
to see if the user can join, stopping the event fire if not. For instance, one such
callback checks if the user is banned.  

This event is never fired for remote users, as it is the responsibility of each server
to determine whether its own users should be able to join a channel.  

This event is fired by the [Core::UserCommands](mod/Core/UserCommands.md) module.

* __$channel__: the channel the user is attempting to join.

### can_invite($t_user, $ch_name, $channel)

Fired before a local user invites someone to a channel. Callbacks of this event typically
run checks to see if the user can invite, stopping the event fire if not. For instance,
one such callback checks if the target user is already in the channel.  

This event is never fired on remote users, as it is the responsibility of each server
to determine whether its own users should be able to invite.  

This event is fired by the [Invite](mod/Invite.md) module.

* __$t_user__: the local or remote user that we are sending an invitation to.
* __$ch_name__: the name of the channel `$t_user` is being invited to. this is
necessary because we allow invitations to nonexistent channels
(unless `channels:invite_must_exist` is enabled).
* __$channel__: the channel object or `undef` if it does not yet exist.
