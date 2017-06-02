# channel

Instances of the `channel` package represent IRC channels.
The package is provided by the ircd::channel submodule of
[ircd](../../modules.md#ircd).

## Constructor

### channel->new(%opts)

Creates a channel object. This class method should almost never be used
directly; you should probably look at [pool](pool.md)'s `->new_channel()` method
instead.

```perl
my $channel = channel->new(
    name => '#chat',
    time => time
);
```

* __%opts__ - hash of constructor options

## Modes

### $LEVEL_SPEAK_MOD
    
This exported variable is the numerical status level required to speak when
channel moderation is enabled.

```perl
die 'You cannot speak'
    if $channel->user_get_highest_level($user) < $channel::LEVEL_SPEAK_MOD;
```

### $LEVEL_SIMPLE_MODES

This exported variable is the numerical status level required to set simple
modes.

```perl
die 'You cannot set modes'
    if $channel->user_get_highest_level($user) < $channel::LEVEL_SIMPLE_MODES;
```

### $channel->is_mode($name)

Checks whether a mode is enabled.

* __name__ - name of the mode

```perl
say 'The channel is moderated' if $channel->is_mode('moderated');
```

Returns a true value when the mode is enabled.

### $channel->mode_parameter($name)

Fetches the value of a mode parameter.

* __name__ - name of the mode

```perl
my $throttle = $channel->mode_parameter('join_throttle');
die 'Throttle active' if $joins >= $throttle->{joins};
```

Returns the value or `undef` if no parameter is set. Also returns `undef` for
list modes and modes that take no parameter. Note that values may be
strings or hash references.

### $channel->set_mode($name, $param)

Sets a channel mode at the lowest level.

* __name__ - name of the mode
* __param__ - mode parameter value. this may be a string or hash reference. if
  the mode does not a parameter, this argument should be omitted

This notifies neither local users nor uplinks. For that reason it is probably
only useful internally. Use higher-level mode methods instead.

This is used only for simple modes, not status or list modes.

```perl
$channel->set_mode('moderated');
$channel->set_mode(limit => 5);
```

### $channel->unset_mode($name)

Unsets a channel mode at the lowest level.

* __name__ - name of the mode

This notifies neither local users nor uplinks. For that reason it is probably
only useful internally. Use higher-level mode methods instead.

This is used only for simple modes, not status or list modes.

```perl
$channel->unset_mode('moderated');
```

### $channel->set_mlock($modes)

Sets the channel mode lock.

* __modes__ - [modes](modes.md) to use as the mode lock

This does not notify uplinks.

Modes which require a parameter in the mode reference should use `*` as the
parameter. This is because there are plans to support locking specific entries
of list modes, which would require parameter propagation.

```perl
my $modes = modes->new(moderated => undef, limit => '*');
$channel->set_mlock($modes);
```

### $channel->mlock

Fetches the current mode lock.

```perl
my $mlock = $channel->mlock;
say $mlock->to_string($me);
```

Returns [modes](modes.md) or `undef` if no mode lock is set.

### $channel->list_has($list, $entry)

Checks if a list or status mode has an entry.

* __list__ - name of the list or status mode
* __entry__ - entry to look for. this is either a case-sensitive string or a
  user object (for status modes)

```perl
die "You're bannned" if $channel->list_has('ban', '*!*@*');
```

Returns true if the entry is present in the list.

### $channel->list_matches($list, $mask)

Checks if a list or status mode has an entry matching the mask.

* __list__ - name of the list or status mode
* __mask__ - a mask to look for in `nick!ident@host` format or a user object

```perl
die "You're banned" if $channel->list_matches('ban', $user);
```

Returns true if at least one list entry matches the mask.

### $channel->list_elements($list)

Fetches all entries of a status or list mode.

* __list__ - name of the list or status mode

```perl
my @bans = $channel->list_elements('ban');
```

Returns the list of entries.

### $channel->list_count($list)

Fetches the number of entries for a list or status mode.

* __list__ - name of the list or status mode

```perl
my $num_ops = $channel->list_count('ops');
```

Returns the number of entries.

### $channel->list_is_full($list)

Determines whether a list or status mode table is full.

* __list__ - name of the list or status mode

This is generally decided by `channels:max_bans` or `channels:max_bans_large`
(with [Channel::LargeList](../../modules.md#channellargelist)), but other
modules could change it.

```perl
die "Can't add another ban" if $channel->list_is_full('ban');
```

Returns true if the list is full.

### $channel->add_to_list($list, $entry)

Adds an entry to a list or status mode at the lowest level.

* __list__ - name of the list or status mode
* __entry__ - entry to add. this is either a string or a user object
  (for status modes)

```perl
$channel->add_to_list('except', '*!*@localhost');
$channel->add_to_list('op', $user);
```

Returns nothing if the entry was already in the list.

Returns true if the entry was added successfully.

### $channel->remove_from_list($list, $entry)

Removes an entry from a list or status mode at the lowest level.

* __list__ - name of the list or status mode
* __entry__ - entry to remove. this is either a string or a user object
  (for status modes)
  
```perl
$channel->remove_from_list('except', '*!*@localhost');
$channel->remove_from_list('op', $user);
```

Returns nothing if the entry was not in the list.

Returns true if the entry was removed successfully.

### $channel->handle_modes($source, $modes, $force)

Handle a series of a mode changes at a low level.

* __source__ - user or server committing the mode change
* __modes__ - [modes](modes.md) to apply
* __force__ - _optional_, force the mode changes, ignoring channel privileges

This notifies neither local users nor uplinks. Use higher-level methods
[`->do_modes`](#channel-do_modessource-modes-force)
[`->do_modes_local`](#channel-do_modes_localsource-modes-force)
for that.

```perl
my $modes = modes->new(op => $user, no_ext => undef);
$channel->handle_modes($me, $modes, 1); # internally sets +no $user
```

Returns [modes](modes.md) that were actually changed. Depending on permissions
and parameter normalization among other factors, this may not be equivalent to
the input modes.

### $channel->handle_mode_string($perspective, $source, $mode_str, $force, $over_protocol)

Handle a mode string at a low level.

* __perspective__ - server whose mode mappings to use to parse `$mode_str`
* __source__ - user or server committing the mode change
* __mode_str__ - mode string to apply, in the perspective of `$perspective`
* __force__ - _optional_, force the mode changes, ignoring channel privileges
* __over_protocol__ - _optional_, if true, the mode string originated on S2S and
  has UIDs instead of nicks

This notifies neither local users nor uplinks. Use higher-level methods
[`->do_mode_string`](#channel-do_mode_stringperspective-source-mode_str-force-over_protocol)
[`->do_mode_string_local`](#channel-do_mode_string_localperspective-source-mode_str-force-over_protocol)
for that.

```perl
$channel->handle_mode_string($serv, $user, '+qo nick nick', 1);
```

Returns [modes](modes.md) that were actually changed. Depending on permissions
and parameter normalization among other factors, this may not be equivalent to
the input modes.

### $channel->do_modes($source, $modes, $force)

Like [`->handle_modes()`](#channel-handle_modessource-modes-force),
except that it also notifies local users and uplinks. This is the highest-level
mode handling method.

### $channel->do_modes_local($source, $modes, $force)

Like [`->handle_modes()`](#channel-handle_modessource-modes-force),
except that it also notifies local users. It does not notify uplinks, however.

### $channel->do_mode_string($perspective, $source, $mode_str, $force, $over_protocol)

Like [`->handle_mode_string()`](#channel-handle_mode_stringperspective-source-mode_str-force-over_protocol),
except that it also notifies local users and uplinks. This is the highest-level
mode string handling method.

### $channel->do_mode_string_local($perspective, $source, $mode_str, $force, $over_protocol)

Like [`->handle_mode_string()`](#channel-handle_mode_stringperspective-source-mode_str-force-over_protocol),
except that it also notifies local users. It does not notify uplinks, however.

### $channel->all_modes

Fetch all modes set in the channel.

```perl
# an elegant way to unset all modes
$channel->do_modes($me, $channel->all_modes->inverse, 1);
```

Returns [modes](modes.md).

### $channel->modes_with(@mode_types)

Fetch specific modes set in the channel.

* __mode_types__ - list of mode names and/or mode types

```perl
use modes qw(MODE_LIST);
# fetch all banlike modes, plus no external messages and moderated
my $restrictions = $channel->modes_with('no_ext', 'moderated', MODE_LIST);
```

Returns matching [modes](modes.md).

### $channel->mode_string_with($perspective, @mode_types)

Like [`->modes_with`](#channel-modes_withmode_types), except it returns a mode string.

* __perspective__ - server whose mode mappings should be used to construct
  the mode string
* __mode_types__ - list of mode names and/or mode types

### $channel->mode_string($perspective)

* __perspective__ - server whose mode mappings should be used to construct
  the mode string

```perl
say $channel->mode_string($me); # +nt
```

Returns a mode string with all simple modes. This includes all modes except
banlike/list modes and status modes.
  
### $channel->mode_string_all($perspective, $no_status)

Like [`->mode_string`](#channel-mode_stringperspective), except it also includes
list and status modes. Status modes may be omitted though.

* __perspective__ - server whose mode mappings should be used to construct
  the mode string
* __no_status__ - _optional_, omit status modes

```perl
say $channel->mode_string_all($me);     # +bnot *!*@example.com nick
say $channel->mode_string_all($me, 1);  # +bnt *!*@example.com
```

## Members

Methods for fetching and manipulating users in the channel.

### $channel->add($user)

Adds a user to the channel at the lowest level.

* __user__ - user to add

```perl
$channel->add($user) or die 'already on channel';
```

Returns the channel TS on success, nothing if the user was already a member.

### $channel->remove($user)

Removes a user from the channel at the lowest level.

* __user__ - user to remove

```perl
$channel->remove($user) or die 'not on channel';
```

Returns true on success.

### $channel->has_user($user)

Tests if a user is in the channel.

* __user__ - user to test

```perl
die 'You are not on that channel' if !$channel->has_user($user);
```

Returns true if the user is in the channel.

### $channel->user_is($user, $level)

Tests if a user has a status.

* __user__ - user to test
* __level__ - numerical level or status mode name

```perl
say 'user has +o' if $channel->user_is($user, 0);
say 'user has voice' if $channel->user_is($user, 'voice');
```

Returns true if the user has the exact status given.

### $channel->user_is_at_least($user, $level)

Tests if a user has at least the given status.

* __user__ - user to test
* __level__ - numerical level or status mode name

```perl
say 'user has +o or greater' if $channel->user_is_at_least($user, 0);
say 'user can speak' if $channel->user_is_at($user, 'voice');
```

Returns true if the user has the status given or one above it.

### $channel->user_has_basic_status($user)

Tests if a user has basic privileges in the channel for setting modes, as
determined by [`$LEVEL_SIMPLE_MODES`](#level_simple_modes). With the default
configuration, this means halfop or higher.

* __user__ - user to test

```perl
die 'You cannot set modes' if !$channel->user_has_basic_status($user);
```

Returns true if the user has basic status.

### $channel->user_get_highest_level($user)

* __user__ - user to test

```perl
if ($channel->user_get_highest_level($kicker) < $channel->user_get_highest_level($kickee)) {
    die 'You cannot kick someone with higher status';
}
```

Returns the highest numerical status level the user has. If the user has no
status, returns negative infinity.

### $channel->user_get_levels($user)

* __user__ - user to test

```perl
my @levels = $channel->user_get_levels($user);
```

Returns a list of numerical status level the user has.

### $channel->user_is_banned($user)

Checks whether a user is banned.

* __user__ - user to test

```perl
die 'You are banned' if $channel->user_is_banned($user);
```

Returns true if the user is banned from the channel and does not have an
exception.

### $channel->user_has_invite($user)

Checks whether a user has an invitation.

* __user__ - user to test

```perl
die 'Cannot join'
    if $channel->is_mode('invite_only')
    && !$channel->user_has_invite($user);
```

Returns true if the user has a pending invitation.

### $channel->user_clear_invite($user)    

Clears a user's pending invitation to the channel.

* __user__ - user to test

```perl
$channel->user_clear_invite($user);
```

### $channel->prefix($user)

Fetch user's status prefix.

* __user__ - user whose prefix to fetch

```perl
my $method   = $client->has_cap('multi-prefix') ? 'prefixes' : 'prefix';
my $prefixes = $channel->$method($user);
```

Returns the local prefix associated with the user's highest status. Returns an
empty string if the user has no status.

### $channel->prefixes($user)

Fetch user's status prefixes.

* __user__ - user whose prefixes to fetch

```perl
my $method   = $client->has_cap('multi-prefix') ? 'prefixes' : 'prefix';
my $prefixes = $channel->$method($user);
```

Returns the local prefixes associated with all of the user's status modes in
the channel in descending order of privilege as a concatenated string. Returns
an empty string if the user has no status.

### $channel->users

```perl
my @users = $channel->users;
```

Returns a list of all users in the channel.

### $channel->users_satisfying($code)

* __code__ - code reference which will be called with the user as its sole
  argument. it should return true to include the user in the resulting list

```perl
# ircops only
my @users = $channel->users_satisfying(sub { !shift->is_mode('ircop') });
```

Returns a list of all users in the channel that satisfy the given code
reference.

### $channel->users_with_at_least($level)

* __level__ - numerical level or status mode name

```perl
my @users = $channel->users_with_at_least(0);       # op or higher
my @users = $channel->users_with_at_least('voice'); # users that can speak
```

Returns a list of all users in the channel that have the given status or higher.

### $channel->all_local_users

```perl
my @users = $channel->all_local_users;
```

Returns a list of all local users in the channel.

### $channel->real_local_users

```perl
my @users = $channel->real_local_users;
```

Returns a list of all real local users in the channel.

## Send methods

### $channel->send_all($message, %opts)

Send a message to all users on the channel.

* __message__ - message text
* __%opts__ - _optional_, options for the underlying
  [`sendfrom_to_many_with_opts()`](user.md#sendfrom_to_many_with_optsfrom-line-opts-users)
  function

```perl
$channel->send_all(':nick!ident@host NICK nicholas');
```

### $channel->sendfrom_all($from, $message, %opts)

Send a prefixed message to all users on the channel.

* __from__ - user, server, or string message source
* __message__ - message text
* __%opts__ - _optional_, options for the underlying
  [`sendfrom_to_many_with_opts()`](user.md#sendfrom_to_many_with_optsfrom-line-opts-users)
  function
  
```perl
$channel->sendfrom_all($user, 'NICK nicholas');
```

### $channel->sendfrom_all_cap($from, $message, $alt, $cap, %opts)

Send a prefixed message to all users on the channel with a specified capability.

* __from__ - user, server, or string message source
* __message__ - message text
* __alt__ - _optional_, alternate message text for members without the required
  capability
* __%opts__ - _optional_, options for the underlying
  [`sendfrom_to_many_with_opts()`](user.md#sendfrom_to_many_with_optsfrom-line-opts-users)
  function
  
```perl
$channel->sendfrom_all_cap(
    $user->full,
    "JOIN $$channel{name} $act_name :$$user{real}",     # IRCv3.1
    "JOIN $$channel{name}",                             # RFC1459
    'extended-join',
    batch => $batch
);
```
  
### $channel->notice_all($what, $ignore, $local, $no_stars)

Send a server notice to all users on the channel.


* __what__ - notice text
* __ignore__ - _optional_, user to skip
* __local__ - _optional_, only send to local users
* __no_stars__ - _optional_, by default the notice is prefixed with `*** `;
  this disables that

```perl
$channel->notice_all("New channel time: ".scalar(localtime $time));
```

### $channel->send_names($user, $no_endof)

Send name replies to the user.

This is used by the `NAMES` command and on channel join.

### $channel->send_modes($user)

Send mode replies to the user.

This is used by the `MODE` command.

## Timestamp

### $channel->set_time($ts)

Sets the channel TS at the lowest level.

### $channel->take_lower_time($ts, $ignore_modes)

* __ts__ - timestamp to compare with the channel TS
* __ignore_modes__ - _optional_, if true, never reset modes or invitations

If `$ts` is newer or equal to the internal channel TS, does nothing.

If `$ts` is older than the internal channel TS, locally resets all modes and
invitations, notifying local users.

```perl
my $new = $channel->take_lower_time($ts);
die 'Timestamp not accepted' if $new != $ts;
```

Returns the new channel TS.

## Actions

### $channel->attempt_join($user, $new, $key, $force)

Attempts a local join.

* __user__ - user trying to join the channel
* __new__ - _optional_, if true, the intention is to created the channel
* __key__ - _optional_, channel key (disregarded with `$force`)
* __force__ - _optional_, if true, ignore restrictions such as bans

This is essentially a `JOIN` command handler, but it is provided here so that
modules can initiate high-level local joins. It checks that a local user can
join a channel (respecting bans, limits, and other restrictions), deals with
channel creation if necessary, sets [automodes](../../config.md#user-options),
and propagates everything to uplinks.

This can only be used for local users. Use
[`->do_join_local`](#channel-do_join_localuser-allow_already)
instead for locally handling the join of a remote user.

```perl
# example from Channel::Forward module
my ($f_chan, $new) = $pool->lookup_or_create_channel($f_ch_name);
$f_chan->attempt_join($user, $new, undef, 1); # force join
```

Returns true on success.

### $channel->do_join_local($user, $allow_already)

Handles a join locally.

* __user__ - user to join
* __allow_already__ - _optional_, if true, don't bail if the user is already in
  the channel. used in cases where [`->add()`](#channel-adduser) has already
  been called

1. Joins a user to the channel with [`->add()`](#channel-adduser), ignoring any
   restrictions such as bans
2. Sends `JOIN` message to local users in common channels
   (and possibly other messages for IRCv3 capabilities, etc.)
3. If the user is local, sends `TOPIC` and `NAMES` replies.
4. Fires the `user_joined` event

This method is permitted for both local and remote users, but it does not
notify uplinks. For local users whose joins should be broadcast,
[`->attempt_join()`](#channel-attempt_joinuser-new-key-force)
should be used instead.

See issue [#76](https://github.com/cooper/juno/issues/76) for background info.

```perl
$channel->do_join_local($user);
```

Returns true on success.

### $channel->do_part($user, $reason)

* __user__ - user to part
* __reason__ - _optional_, part comment

```perl
$channel->do_part($user, 'Leaving');
```

Returns true on success, false if the user was not in the channel.

### $channel->do_part_local($user, $reason)

Local version.

### $channel->do_privmsgnotice($command, $source, $message, %opts)

Sends a message to local members and uplinks with members in the channel.

* __command__ - `PRIVMSG` or `NOTICE`
* __source__ - user or server sending the message
* __message__ - message text
* __opts__ - _optional_, additional options

__%opts__ - all are optional

* __force__ - if specified, the `can_privmsg`, `can_notice`, and `can_message`
events will not be fired. this means that any modules that prevent the message
from being sent OR that modify the message will NOT have an effect on this
message. used when receiving remote messages

* __dont_forward__ - if specified, the message will NOT be forwarded to other
servers by this method

* __users__ - if specified, this list of users will be used as the destinations.
they can be local, remote, or a mixture. when omitted, all non-deaf users of the
channel will receive the message. deaf users will never received messages, even
if passed explicitly

* __op_moderated__ - if true, this message was blocked but will be sent to ops
in an op moderated channel

* __serv_mask__ - if provided, the message is to be sent to all users which
belong to servers matching the mask

* __atserv_nick__ - if provided, this is the nickname for a `target@server`
message. if it is present, `atserv_serv` must also exist

* __atserv_serv__ - if provided, this is the server object for a `target@server`
message. if it is present, `atserv_nick` must also exist

* __min_level__ - a status level which this message is directed to. the message
will be sent to users with the prefix; e.g. `@#channel` or `+#channel`

### $channel->do_privmsgnotice_local

Local version.

### $channel->do_topic($source, $topic, $setby, $time)

Sets the channel topic, notifying local users and uplinks.

* __source__ - server or user setting the topic. this is not stored, just used
  as the source of the topic messages
* __topic__ - topic text
* __setby__ - nick, `nick!ident@host`, or server name that set the topic
* __time__ - new topic TS

```perl
$channel->do_topic($user, 'Dragons', $user->full, time);
```

Returns true if the topic was changed, whether that be the topic text or just
the metadata associated with it.

### $channel->do_topic_local

Local version.

### $channel->do_kick($user, $source, $reason)

Kick a user from the channel, notifying local users and uplinks.

* __user__ - user to kick
* __source__ - user or server committing the kick
* __reason__ - _optional_, kick comment

```perl
$channel->do_kick($target, $me, 'Flood limit reached');
```

Returns true on success.

### $channel->do_kick_local

Local version.
    
## Metadata

### $channel->id

```perl
for my $channel (@channels) {
    next if $sent_to{ $channel->id }++;
    $channel->notice_all('Spam attack! All channels are locked!');
}
```

Returns channel name, lowercased according to the current
[casemapping](../../config.md#server-info).

This is suitable hash keys, caching, and things like that.

### $channel->name

```perl
say $channel->name;
```

Returns channel name.

### $channel->topic

```perl
my $topic = $channel->topic;
die 'No topic is set' if !$topic;

print 'Topic is ', $topic->{topic};
print ' set by ', $topic->{setby}                   if $topic->{setby};
print ' set on ', scalar localtime $topic->{time}   if $topic->{time};
```

If a topic is set, returns a hash reference with the following info:
* __topic__ - the topic text
* __setby__ - a nickname, `nick!ident@host`, or server name that set the topic.
  this might not always be present
* __time__ - topic TS, the time when the topic was set. this might not always
  be present

Otherwise, returns nothing.

## Miscellaneous
        
### $channel->destroy_maybe

Fires an event to check whether the channel should be destroyed, and if so,
destroys it. This is determined by whether there are users in the channel,
whether channel is marked as [permanent](../../modules.md#channelpermanent),
and possibly other modules.

Called in user part handlers.

```perl
$channel->destroy_maybe;
```

Returns true if the channel was destroyed, nothing otherwise.

### $channel->clear_all_invites

Clears pending invitations.

This is used when the channel TS is reset and a few other places.

```perl
$channel->clear_all_invites;
```
