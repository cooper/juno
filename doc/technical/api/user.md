# user

Instances of the `user` package represent IRC users, both local and remote.
The package is provided by the ircd::user submodule of
[ircd](../../modules.md#ircd).

## Low-level methods

These methods are most often used internally. Many of them exist merely to
standardize the way certain user fields are stored and retrieved.

Unlike the many [high-level methods](#high-level-methods), these low-level ones
do not notify local clients or uplinks about any changes. Most modules will find
the high-level methods more useful because they deal with the logistics
associated with the changing of user data.

### user->new(%opts)

Creates a new user object.

This low-level initializer should almost never be used directly;
look at [`pool->new_user()`](pool.md) instead.

```perl
my $user = $pool->new_user(
    nick  => 'Steve',
    ident => '~steve',
    host  => 'server.example.com',
    cloak => 'server.example.com',
    ip    => '93.184.216.119'
);
```

* __%opts__ - hash of constructor options.

### $user->is_mode($mode_name)

Returns true if user has the supplied mode set.

```perl
if ($user->is_mode('ircop')) {
    $user->numeric('RPL_YOUREOPER');
}
```

* __$mode_name__ - name of the mode being tested.

### $user->set_mode($mode_name)

The lowest level of user mode setting.

Local clients and uplinks are NOT notified; see
[`->handle_mode_string()`](#user-handle_mode_stringmode_string-force),
[`->do_mode_string()`](#user-do_mode_stringmode_string-force), and
[`->do_mode_string_local()`](#user-do_mode_string_localmode_string-force)
for ways to achieve that.

```perl
if (password_correct($pw)) {
    $user->set_mode('ircop');
}
```

* __$mode_name__ - name of the mode being set.

### $user->unset_mode($mode_name)

The lowest level of user mode unsetting.

Local clients and uplinks are NOT notified; see
[`->handle_mode_string()`](#user-handle_mode_stringmode_string-force),
[`->do_mode_string()`](#user-do_mode_stringmode_string-force), and
[`->do_mode_string_local()`](#user-do_mode_string_localmode_string-force)
for ways to achieve that.

```perl
$user->unset_mode('invisible');
```

* __$mode_name__ - name of the mode being unset.

### $user->handle_mode_string($mode_string, $force)

The lowest level of mode string handling.

Local clients and uplinks are NOT notified. The method only calls
[`->set_mode()`](#user-set_modemode_name) and
[`->unset_mode()`](#user-unset_modemode_name) after firing
any possible user mode blocks. See
[`->do_mode_string()`](#user-do_mode_stringmode_string-force) and
[`->do_mode_string_local()`](#user-do_mode_string_localmode_string-force) for
the different ways to handle mode strings at a higher level.  

Returns a mode string of changes that occurred such as `+ix`.

```perl
$user->handle_mode_string('+o', 1);
```

* __$mode_string__ - mode string to be handled; e.g. `+iox`. this is in the
perspective of user's server.
* __$force__ - _optional_, if true, failure of user mode blocks will be ignored,
forcing the changes.

### $user->mode_string

Returns string of all modes set on user; e.g. `+iox`.

```perl
# unset all modes
my $all_modes = $user->mode_string;
substr($all_modes, 0, 1) = '-';
$user->handle_mode_string($all_modes, 1);
```

### $user->flags

Returns the list of oper flags belonging to user.

### $user->has_flag($flag)

Returns true if user has the specified oper flag enabled.

```perl
if (!$user->has_flag('gkill')) {
    $user->numeric(ERR_NOPRIVILEGES => 'gkill');
    return;
}
```

* __$flag__ - name of the flag being tested; e.g. `kill`.

### $user->add_flags(@flags)

The lowest level of oper flag handling.

Adds any of the supplied oper flags that user does not have already.
Local clients and uplinks are NOT notified.

```perl
$user->add_flags('kill', 'gkill');
```

* __@flags__ - list of oper flags to add.

### $user->remove_flags(@flags)

The lowest level of oper flag handling.

Removes any of the supplied oper flags that user has enabled.
Local clients and uplinks are NOT notified.

```perl
$user->remove_flags('kill', 'gkill');
```

* __@flags__ - list of oper flags to remove.

### $user->clear_flags

Removes all of user's oper flags at a low level.

### $user->update_flags

After committing oper flag changes, sets or unsets user's
IRCop mode as necessary. Also notifies user and other opers of flags granted.

Used for both local and remote users.

### $user->has_notice($flag)

Returns true if user has the supplied oper notice flag enabled.

```perl
if ($user->has_notice('user_nick_change')) {
    $user->server_notice(nick => $user_other->full.' -> '.$new_nick);
}
```

* __$flag__ - oper notice flag being tested.

### $user->add_notices(@flags)

Adds any of the supplied oper notice flags that user does not already have.

This has no effect on remote users.

```perl
$user->add_notices('user_nick_change', 'user_killed');
```

* __@flags__ - list of oper notice flags to enable.

### $user->change_nick($new_nick, $new_nick_ts)

The lowest level of user nick changing.

Local clients and uplinks are NOT notified. You probably want
[`->do_nick()`](#user-do_nicknew_nick-new_nick_ts) or
[`->do_nick_local()`](#user-do_nick_localnew_nick-new_nick_ts) instead.

Returns the new nick TS if the nick was changed successfully. This can fail if
it is invalid or already taken. Note that true is returned if the new nick is
the same as it was already.

```perl
$user->change_nick('newbie');
```

* __$new_nick__ - nick to replace the current one.
* __$new_nick_ts__ - _optional_, new nick TS. defaults to current time.

### $user->set_away($reason)

The lowest level of marking a user as away.

Local clients and uplinks are NOT notified. You likely want
[`->do_away()`](#user-do_awayreason) instead.

```perl
$user->set_away('Be back later.');
```

* __$reason__ - comment for why user is away.

### $user->unset_away

The lowest level of marking a user as here.

Local clients and uplinks are NOT notified. You likely want
[`->do_away()`](#user-do_awayreason) instead.

```perl
$user->unset_away();
```

### $user->quit($reason)

The lowest level of user quitting for both local and remote users.

To terminate the connection of a local user, you should instead use
[`$user->conn->done($reason)`](connection.md), which will in turn call this
method after dropping the connection.  

All event callbacks will be deleted as this method prepares the user object for
disposal.

```perl
$user->quit('~ <insert meaningless quote here>');
```

* __$reason__ - reason for quitting.

### $user->channels

Returns list of channel objects of which user is a member.

```perl
my $n;
for my $channel ($user->channels) {
    next if !$channel->user_has_basic_status($user);
    $n++;
}
say "I have ops in $n channels across 1 networks. But no one cares.";
```

### $user->is_local

Returns true if user belongs to the local server.

```perl
if ($user->is_local) {
    $user->sendfrom($other->full, 'AWAY :Be back later.');
}
```

### $user->full

Returns string `nick!ident@host` where host may be either an artificial
host (cloak) or the actual hostname.

```perl
$user->sendfrom($other->full, 'AWAY :Be back later.');
```

### $user->fullreal

Returns string `nick!ident@host` where host is always the actual hostname,
ignoring any possible cloak or artificial host.

Generally [`->full`](#user-full) is favored over this if the
return value may be exposed to other users.

```perl
# show opers the real host
notice(user_nick_change => $user->fullreal, $new_nick);
```

### $user->fullip

Returns string `nick!ident@host` where host is the human-readable IP
address of user, completely ignoring any host or cloak.

```perl
if (match($mask, $user->fullip)) {
    kill_user($user, "You're banned!");
}
```

### $user->notice_info

Returns a list of user's nick, ident, and actual host in that order.
Useful for oper notices where these three items are commonly displayed.

```perl
notice(user_nick_change => $user->notice_info, $new_nick);
```

### $user->hops_to($target)

Returns the number of hops to a server or user.

```perl
$user->hops_to($user);          # 0
$user->hops_to($other_server);  # 1
```

* __$target__ - target user or server object. if it's a user, the result is
the same as calling with `$target->server`.

### $user->id

Returns the globally unique internal identifier associated with user.

```perl
# sometimes it is useful to use IDs rather than
# increasing the refcount on the user object
push @invited_users, $user->id;
```

### $user->name

Returns user's nick.

```perl
my $target = $pool->lookup_channel($id) || $pool->lookup_user($id);
say 'Sending the message to '.$target->name;
```

### $user->server

Returns the server to which user belongs, regardless of whether that
server is directly linked to the local one.

```perl
if ($user->server != $fwd_serv) {
    $msg->forward_to($fwd_serv, privmsg => $target, $message);
}
```

## High-level methods

High-level methods are typically for modifying data associated with a user
and then notifying local clients and uplinks.

Most modules will find the high-level methods more useful than the low-level
ones because they deal with the logistics associated with changing data
associated with user.

### $user->server_notice($info, $message)

Send a notice to user from the local server.

Works on both local and remote users.

```perl
$user->server_notice('A client is connecting.');
```
```perl
$user->server_notice(kill => $other_user->name.' was killed');
```

* __$info__ - _optional_, a brief description of the notice which will be
formatted in an appealing way; e.g. 'kill' for a kill command result.
* __$message__ - notice message to send to user.

### $user->numeric($const, @args)

Send a numeric reply to user from the local server.

Works on both local and remote users. The string is formatted locally so that
remote servers do not have to understand the numeric.

```perl
$user->numeric(RPL_MAP => $spaces, $server->name, $users, $per);
```

* __$const__ - string name of the numeric reply.
* __@args__ - _optional_ (depending on the numeric), a list of arguments for the
user numeric handler.

### $user->simulate_numeric($const, @args)

Like [`->numeric`](#user-numericconst-args), except instead of actually sending
the numeric, returns the data which would have been sent.

Useful for checking the length of what the base of a numeric reply will be so
that the message byte limit is not exceeded.

### $user->handle_unsafe($data)

Emulates that user sent a piece of data to the local server.

It is "unsafe" in that it assumes that the command handlers are capable of
dealing with emulated data from remote users.

Works exactly like [`->handle()`](#user-handledata) except it will not return
fail if user is not connected directly to the local server.

```perl
$user->handle_unsafe("TOPIC $ch_name :$new_topic");
```

* __$data__ - one or more _complete_ lines of data, including any possible
trailing newlines or carriage returns.

### $user->handle_with_opts_unsafe($data, %opts)

Same as [`->handle_unsafe()`](#user-handle_unsafedata), except that the provided
options will be passed to the underlying call.

```perl
$user->handle_with_opts_unsafe("TOPIC $ch_name :$new_topic", fantasy => 1);
```

* __$data__ - one or more _complete_ lines of data, including any possible
trailing newlines or carriage returns.
* __%opts__ - _optional_, a hash of options to pass to the underlying function
call.

### $user->get_killed_by($murderer, $reason)

Handles a kill on a local level.

To clarify, neither user nor murderer has to be local, but uplinks are NOT
notified. Local kills MUST be associated with a
`broadcast()` call, and remote kills MUST be broadcast to other uplinks with
forward methods.

```perl
my $reason = "Your behavior is not conducive to the desired environment.";
$user->get_killed_by($other_user, $reason);
```

* __$murderer__ - user committing the action.
* __$reason__ - comment for why user was killed.

### $user->get_mask_changed($new_ident, $new_host)

Handles an ident or cloak change on a local level.

To clarify, user does not have to be local, but uplinks are NOT notified.

Updates the user fields, notifying local clients as necessary. If neither the
ident nor the cloak has changed, the call is quietly discarded.

Local clients with the
[`chghost`](http://ircv3.net/specs/extensions/chghost-3.2.html)
capability will receive a CHGHOST notification. Others will receive a quit and
rejoin emulation, unless `users:chghost_quit` is explicitly disabled.


```perl
$user->get_mask_changed('someone', 'my.vhost');
```
```perl
$user->get_mask_changed($user->{ident}, 'my.vhost');
```

* __$new_ident__ - new ident. if unchanged, the current ident MUST be passed.
* __$new_host__ - new cloak. if unchanged, the current cloak MUST be passed.

### $user->save_locally

Handles a nick collision on user at a local level, adopting his UID as a nick.

To clarify, user does not have to be local, but uplinks are NOT notified.

Remote servers should been notified (such as through a SAVE, NICK, or similar
message) that user was saved and will adopt his UID as a nick.

```perl
if ($save_old) {
    $server->fire_command(save_user => $me, $used);
    $used->save_locally;
}
```

### $user->do_away($reason)

Processes an away or return for both local and remote users.

Calls [`->set_away()`](#user-set_awayreason) or
[`->unset_away()`](#user-unset_away), depending on whether the reason is
provided.

If user is local, he receives a numeric notification.

Local clients with the
[`away-notify`](http://ircv3.net/specs/extensions/away-notify-3.1.html)
capability are also notified.

```perl
$user->do_away("Be back later");
```
```perl
$user->do_away(undef);
```

* __$reason__ - _optional_, the away comment. if undefined or empty string,
user is considered to have returned from being away.

### $user->do_away_local($reason)

Local version.

### $user->do_part_all

Parts user from all channels, notifying local clients.

This is typically initiated by a `JOIN 0` command.

```perl
if ($target eq '0') {
    $user->do_part_all();
}
```

### $user->do_part_all_local

Local version.

### $user->do_login($act_name, $no_num)

Logs user into the given account name.

If user is local, he receives a numeric notification.

Local clients with the
[`account-notify`](http://ircv3.net/specs/extensions/account-notify-3.1.html)
capability are also notified.

```perl
$user->do_login($act_name);
```

* __$act_name__ - name of the account.
* __$no_num__ - _optional_, if provided, user will not receive a numeric
reply. this is useful if the reply was already sent before calling this method,
such as during SASL authentication.

### $user->do_login_local($act_name, $no_num)

Local version.

### $user->do_logout

Logs user out from their current account.

If user is not logged in, the call is quietly discarded.

If user is local, he receives a numeric notification.

Local clients with the
[`account-notify`](http://ircv3.net/specs/extensions/account-notify-3.1.html)
capability are also notified.

```perl
$user->do_logout();
```

### $user->do_logout_local

Local version.

### $user->do_nick($new_nick, $new_nick_ts)

Changes user's nick, notifying local clients and uplinks.

```perl
$user->do_nick($new_nick, $new_nick_ts);
$user->do_nick($new_nick); # use current time
```

* __$new_nick__ - nick to replace the current one.
* __$new_nick_ts__ - _optional_, new nick TS. defaults to current time.

Returns the new nick TS if the nick was changed successfully. This can fail if
it is invalid or already taken. Note that true is returned if the new nick is
the same as it was already.

### $user->do_nick($new_nick, $new_nick_ts)

Local version.

### $user->do_privmsgnotice($command, $source, $message, %opts)

Handles a PRIVMSG or NOTICE to user.

This is used for both local and remote users. Fires events like `can_message`,
`cant_message`, `can_receive_message`, `privmsg`, `notice`, plus several others.
These are used by modules to either block or modify messages.

This method also deals with routing of the message. If user is local, he
will receive the message. Otherwise, the message will be forwarded to the
appropriate uplink.

```perl
$target->do_privmsgnotice('notice', $someone, 'hi there');
```

* __$command__ - either 'privmsg' or 'notice'. case-insensitive.
* __$source__ - user or server object which is the source of the message.
* __$message__ - message text was it was received.
* __%opts__ - _optional_, a hash of options.

__%opts__
* __force__ - if specified, the `can_privmsg`, `can_notice`, and `can_message`
 events will not be fired. this means that any modules that prevent the message
 from being sent OR that modify the message will NOT have an effect on this
 message. used when receiving remote messages.
* __dont_forward__ - if specified, the message will NOT be forwarded to uplinks
  when user is not local.

### $user->do_privmsgnotice_local($command, $source, $message, %opts)

Local version.

### $user->do_mode_string($mode_string, $force)

Handles a mode string with
[`->handle_mode_string()`](#user-handle_mode_stringmode_string-force),
notifying user and uplinks.

If user is local, a MODE message will notify user with the result of any
changes. The mode message will then be forwarded to uplinks.

```perl
$user->do_mode_string('+io', 1);
```

* __$mode_string__ - mode string to be handled; e.g. `+iox`. this is in the
perspective of user's server, `$user->server`.
* __$force__ - _optional_, if true, failure of user mode blocks will be ignored,
forcing the changes.

### $user->do_mode_string_local($mode_string, $force)

Handles a mode string with
[`->handle_mode_string()`](#user-handle_mode_stringmode_string-force), notifying
user.

If user is local, a MODE message will notify user with the result of any
changes.

Unlike [`->do_mode_string()`](#user-do_mode_stringmode_string-force), the
mode message will only be handled locally and will NOT be forwarded uplinks.

```perl
$user->do_mode_string_local('+i');
```

* __$mode_string__ - mode string to be handled; e.g. `+iox`. this is in the
perspective of user's server, `$user->server`.
* __$force__ - _optional_, if true, failure of user mode blocks will be ignored,
forcing the changes.

### $user->send_to_channels($line, %opts)

Sends data with user as the source to all local users with at least one channel
in common with user.

User himself will also receive the message, regardless of whether he has
joined any channels.

```perl
$user->send_to_channels('NICK steve');
# sends :nick!user@host NICK steve to all users in a common channel with him
```

* __$line__ - line of data WITHOUT a suffixing newline and carriage return.
* __%opts__ - _optional_, a hash of options to pass to the underlying
`sendfrom_to_many_with_opts()` function.

## Local-only methods

These methods may ONLY be called on local users; however, some have similar
versions or wrappers which support remote users.

Many of these methods require that the user is local because they involve
using methods on their connection object, e.g. sending data directly to the
associated socket.

### $user->handle($data)

Handle one or more lines of incoming data from user.

The appropriate user command handlers will be called, or if a command does not
exist, `ERR_UNKNOWNCOMMAND` will be sent to user.  

Returns undef and produces a warning if user does not belong to the
local server or does not have an associated connection object. Handling data
from a remote user may be dangerous but can be achieved instead with
[`->handle_unsafe()`](#user-handle_unsafedata).

```perl
$user->handle("MOTD $$serv{name}");
```

* __$data__ - one or more _complete_ lines of data, including any possible
trailing newlines or carriage returns.

### $user->handle_with_opts($data, %opts)

Same as [`->handle()`](#user-handledata), except that the provided options will
be passed to the underlying call.

```perl
$user->handle_with_opts("MODE $$channel{name}", fantasy => 1);
```

* __$data__ - one or more _complete_ lines of data, including any possible
trailing newlines or carriage returns.
* __%opts__ - _optional_, a hash of options to pass to the underlying function
call.

### $user->send($line)

Sends a line of data to user.  

Returns undef and produces a warning if user does not belong to the
local server or does not have an associated connection object. However, some
other sending methods work on remote users such as
[`->numeric()`](#user-numericconst-args) and
[`->server_notice()`](#user-server_noticeinfo-message).

```perl
$user->send(':'.$me->name.' NOTICE '.$user->name.' :welcome to our server');
```

* __$line__ - line of data WITHOUT a suffixing newline and carriage return.

### $user->sendfrom($from, $line)

Sends a line of data from a source.

The supplied source should not be an object but instead a string. Typically the
[`->full`](#user-full) method of either a user or server will be used. For
users, this is `nick!ident@host` where host is either a cloak or the real host.
For servers, this is the server name.

```perl
# where $ouser is some other user.
$user->sendfrom($ouser->full, 'AWAY :gtg bye');

# the above is equivalent to
$user->send(':'.$ouser->full.' AWAY :gtg bye');
```

* __$from__ - source string of the message.
* __$line__ - line of data WITHOUT a suffixing newline and carriage return.

### $user->sendme($line)

Sends a line of data from the local server.

```perl
$user->sendme("NOTICE $$user{nick} :Hi!");

# the above is equivalent to both of the following:
$user->sendfrom($me->name, "NOTICE $$user{nick} :Hi!");
$user->send(':'.$me->name." NOTICE $$user{nick} :Hi!");

# but just for the record, this is only an example.
# the proper way to achieve the above is:
$user->server_notice('Hi!');
```

* __$line__ - line of data WITHOUT a suffixing newline and carriage return.

### $user->has_cap($flag)

Returns true if user has the specified client capability enabled.

```perl
if ($user->has_cap('away-notify')) {
    $user->sendfrom($other_user->full, 'AWAY');
}
```

* __$flag__ - name of the capability.

### $user->add_cap($flag)

Enables a client capability.

```perl
$user->add_cap('userhost-in-names');
```

* __$flag__ - name of the capability.

### $user->remove_cap($flag)

Disables a client capability.

```perl
$user->remove_cap('multi-prefix');
```

* __$flag__ - name of the capability.

### $user->forward($event_name, @args)

Convenience method for [`$user->location->forward(...)`](server.md).

### $user->conn

Returns the connection object associated with user.

This is never present for remote users, and may even be absent for some local
users. Thus, you must always test for it.

```perl
$user->conn->done('Goodbye');
```

## Procedural functions

These functions typically involve operations on multiple users. Rather than
being called in the `$user->method()` form, they should be used directly from
the `user` package, as in `user::some_function()`.

### sendfrom_to_many($from, $line, @users)

Sends a piece of data to several users at once from the specified source.

Even if any user occurs multiple times in the list, the message will only be
sent once to each user.  

```perl
user::sendfrom_to_many($user->full, 'NICK steve', @users, $user);
# the above sends a NICK message as follows: :user!ident@host NICK steve
# to all of the users within the list @users as well as himself.
```

* __$from__ - source string of the message.
* __$line__ - line of data WITHOUT a suffixing newline and carriage return.
* __@users__ - list of users to send the data to.

### sendfrom_to_many_with_opts($from, $line, \%opts, @users)

Same as [`sendfrom_to_many()`](#sendfrom_to_manyfrom-line-users),
except that additional features may be used
through the added options argument.

```perl
my $opts = { no_self => 1 };
user::sendfrom_to_many($user->full, 'NICK steve', $opts, @users);
# the above sends a NICK message as follows: :user!ident@host NICK steve
# to all of the users in @users other than $user
```

* __$from__ - source string of the message.
* __$line__ - line of data WITHOUT a suffixing newline and carriage return.
* __\%opts__ - _optional_, a hash reference of options.
* __@users__ - list of users to send the data to.

#### Supported options

* __ignore__ - _optional_, user object to ignore. if ignored user is found in
  the provided list, they are skipped and will not receive the message.
* __no_self__ - _optional_, if true, the user identified by the mask `$from`
  will be skipped and will not receive the message.
* __cap__ - _optional_, client capability. if provided, the message will only
  be sent to users with this capability enabled.
* __alt__ - _optional_, alternate message to send to users without the
  capability specified by the `cap` option.
* __batch__ - _optional_, batch that this message belongs to, as returned by
  [`message->new_batch()`](message.md#message-new_batchbatch_type-params).

### sendfrom_to_all($from, $line)

Like [`sendfrom_to_many()`](#sendfrom_to_manyfrom-line-users), except that it
sends the message to all local users.

### sendfrom_to_all_with_opts($from, $line, \%opts, @users)

Like [`sendfrom_to_many_with_opts()`](#sendfrom_to_many_with_optsfrom-line-opts-users),
except that it sends the message to all local users.

## Events

User objects are
[listened upon](https://metacpan.org/pod/Evented::Object#Listener-object) by the
[pool](pool.md). Most events involving user interaction with a channel are fired
on the [channel](channel.md) object rather than the user object.

### user.can_join($channel)

Fired before a local user joins a channel.

Callbacks of this event typically run checks to see if user can join, stopping
the event fire if not. For instance, one such callback checks if user is banned.  

Never fired for remote users, as it is the responsibility of each server to
determine whether its own users should be able to join a channel.  

Fired by [Core::UserCommands](../../modules.md#core).

```perl
$pool->on('user.can_join' => sub {
    my ($event, $channel) = @_;
    my $user = $event->object;

    # channel is not invite-only.
    return $JOIN_OK
        unless $channel->is_mode('invite_only');

    # user has been invited.
    return $JOIN_OK
        if $user->{invite_pending}{ lc $channel->name };

    # user matches the exception list.
    return $JOIN_OK
        if $channel->list_matches('invite_except', $user);

    # sorry, not invited, no exception.
    $user->numeric(ERR_INVITEONLYCHAN => $channel->name)
        unless $event->{silent_errors};
    $event->stop('not_invited');

}, name => 'has.invite', priority => 20);
```

* __$channel__ - channel user is attempting to join.

### user.can_invite($t_user, $ch_name, $channel, $quiet)

Fired before a local user invites someone to a channel.

Callbacks of this event typically run checks to see if user can invite, stopping
the event fire if not. For instance, one such callback checks if the target user
is already in the channel.  

Never fired on remote users, as it is the responsibility of each server to
determine whether its own users should be able to invite.  

Fired by [Invite](../../modules.md#channelinvite).

```perl
$pool->on('user.can_invite' => sub {
    my ($event, $t_user, $ch_name, $channel) = @_;
    my $user = $event->object;
    return unless $channel;

    # target is not in there.
    return $INVITE_OK
        unless $channel->has_user($t_user);

    # target is in there already.
    $event->stop;
    $user->numeric(ERR_USERONCHANNEL => $t_user->{nick}, $ch_name);

}, name => 'target.in.channel', priority => 20);
```

* __$t_user__ - local or remote user that we are sending an invitation to.
* __$ch_name__ - name of the channel `$t_user` is being invited to. this is
necessary because we allow invitations to nonexistent channels
(unless `channels:invite_must_exist` is enabled).
* __$channel__ - channel object or `undef` if it does not yet exist.
* __$quiet__ - if true, the handler MUST NOT send error replies to user.

### user.can_message($target, \$message, $lc_cmd)

Fired on a local user who is attempting to send a message.

The target may be a user or channel. This event allows modules to prevent a user
from sending a message by stopping the event. Modules can also modify the
message text before it is delivered to its target.

If your callback adds a message restriction, call `$event->stop($reason)` with a
human-readable reason as to why the message was blocked. This may be used for
debugging purposes. If you need to send an error numeric to the source user, do
not call [`->numeric()`](#user-numericconst-args) directly, as some errors are
suppressed by other modules. Instead, use the `$event->{error_reply}` key, like
so:
```perl
$event->{error_reply} = [ ERR_INVITEONLYCHAN => $channel->name ];
```

You can hook onto this event using any of these:

| Event                     | Command   | Target    |
| ------------------------- | --------- | --------- |        
| __can_message__           | Any       | Any       |
| __can_message_user__      | Any       | User      |
| __can_message_channel__   | Any       | Channel   |
| __can_privmsg__           | `PRIVMSG` | Any       |
| __can_privmsg_user__      | `PRIVMSG` | User      |
| __can_privmsg_channel__   | `PRIVMSG` | Channel   |
| __can_notice__            | `NOTICE`  | Any       |
| __can_notice_user__       | `NOTICE`  | User      |
| __can_notice_channel__    | `NOTICE`  | Channel   |

```perl
# not in channel and no external messages?
$pool->on('user.can_message_channel' => sub {
    my ($user, $event, $channel, $message_ref, $type) = @_;

    # not internal only, or user is in channel.
    return unless $channel->is_mode('no_ext');
    return if $channel->has_user($user);

    # no external messages.
    $event->{error_reply} =
        [ ERR_CANNOTSENDTOCHAN => $channel->name, 'No external messages' ];
    $event->stop('no_ext');

}, name => 'no.external.messages', with_eo => 1, priority => 30);
```

* __$target__ - message target. a user or channel object.
* __\$message__ - scalar reference to the message text. callbacks may
 overwrite this to modify the message.
* __$lc_cmd__ - `privmsg` or `notice`. only useful for `can_message_*` events.

### user.cant_message($target, $message, $can_fire, $lc_cmd)

You can hook onto this event using any of these:

| Event                      | Command   | Target    |
| -------------------------- | --------- | --------- |        
| __cant_message__           | Any       | Any       |
| __cant_message_user__      | Any       | User      |
| __cant_message_channel__   | Any       | Channel   |
| __cant_privmsg__           | `PRIVMSG` | Any       |
| __cant_privmsg_user__      | `PRIVMSG` | User      |
| __cant_privmsg_channel__   | `PRIVMSG` | Channel   |
| __cant_notice__            | `NOTICE`  | Any       |
| __cant_notice_user__       | `NOTICE`  | User      |
| __cant_notice_channel__    | `NOTICE`  | Channel   |

* __$target__ - message target. a user or channel object.
* __$message__ - message text.
* __$can_fire__ - event fire object from the `can_message` and related
  events. this is useful for extracting information about why the message was
  blocked.
* __$lc_cmd__ - `privmsg` or `notice`. only useful for `cant_message_*` events.

### user.can_receive_message($target, \$message, $lc_cmd)

Fired on a local user who is about to receive a message.

The message is either addressed directly to user or a channel of which user is
a member. By the time this event is fired,
[`->do_privmsgnotice()`](#user-do_privmsgnoticecommand-source-message-opts) has
already determined that the source is permitted to send the message.
Modifications may have been made to the primary message text as well.

Modules may hook onto this to prevent a specific user from seeing the message
by stopping the event, or they can modify the text that the specific user will
see. Modifying the message will not affect what other channel members might see,
for example.

You can hook onto this event using any of these:

| Event                             | Command   | Target    |
| --------------------------------- | --------- | --------- |        
| __can_receive_message__           | Any       | Any       |
| __can_receive_message_user__      | Any       | User      |
| __can_receive_message_channel__   | Any       | Channel   |
| __can_receive_privmsg__           | `PRIVMSG` | Any       |
| __can_receive_privmsg_user__      | `PRIVMSG` | User      |
| __can_receive_privmsg_channel__   | `PRIVMSG` | Channel   |
| __can_receive_notice__            | `NOTICE`  | Any       |
| __can_receive_notice_user__       | `NOTICE`  | User      |
| __can_receive_notice_channel__    | `NOTICE`  | Channel   |

* __$target__ - message target. a user or channel object.
* __\$message__ - scalar reference to the message text. callbacks may
 overwrite this to modify the message. unlike `can_message`, changes to it will
 only affect what the user the event is fired on sees.
* __$lc_cmd__ - `privmsg` or `notice`. only useful for `can_receive_message_*`
 events.
