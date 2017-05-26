# message

Instances of the `message` class represent IRC messages in a format like the one
described in RFC1459. This is used for the client protocol as well as all
currently-supported linking protocols.

## Constructors

### message->new($data)

If only one argument is passed to the constructor, a new message is created from
the given data.

```perl
my $msg = message->new(':nick!ident@host PRIVMSG #channel :Hi!');
```

### message->new(%opts)

Constructs a new message.

```perl
my $msg = message->new(command => 'PRIVMSG')
```

__%opts__
* __command__ - IRC command name
* __source__ - _optional_, command source. user or server objects are permitted
  as well as strings
* __params__ - _optional_, array reference of command parameters, or a single
  value is fine if there is just one parameter. strings and IRC objects are
  permitted. undefined or empty parameters are ignored
* __tags__ - _optional_, hash reference of message tags. string keys, values
  may be of any type mentioned above for params
* __data__ - _optional_, IRC data

## Message data

IRC data, source, and command.

### $msg->data

Retrieves or constructs IRC data for this message.

```perl
my $data = message->new(
    source  => $user,
    command => 'privmsg',
    params  => ['#channel', 'Hello everyone']
)->data;

say $data; # :nick!ident@host PRIVMSG #channel :Hello everyone!
```

Returns the data.

### $msg->reset_data

If the `data` option is provided to the constructor, it is always used for the
value of [`$msg->data`](#msg-data). This method overrules that, so that after
providing `data` and making other changes you can force the message data to be
reconstructed.

```perl
my $msg = message->new(':nick!ident@host PRIVMSG #channel :Hi!');
$msg->add_tag(account => 'someone');
my $data = $msg->reset_data->data;
```

Returns the message.

### $msg->parse

If the `data` option is NOT provided to the constructor, you may set it later.
In this case, `->parse` will up the source, command, and other values.

**Do not call `->parse` when providing data to the constructor. The message
is parsed automatically in that case.**

```perl
my $msg = message->new(command => 'PONG', params => 'k.notroll.net');
$msg->{data} = 'PING :k.notroll.net';
$msg->parse;
say $msg->command; # PING
```

Returns nothing if there is no data associated with the message. Otherwise,
returns the message.

### $msg->command

```perl
say message->new('ping :k.notroll.net')->command; # PING
```

Returns the command in uppercase.

### $msg->raw_cmd

```perl
say message->new('ping :k.notroll.net')->raw_cmd; # ping
```

Returns the command in the case it was provided.

### $msg->source

```
my $msg = message->new(':nick!ident@host PRIVMSG #channel :spam');
my $user = $msg->source or die "Can't find Nick\n";
$user->get_killed_by($me, 'Please don\'t spam!');
```

Returns the message source object. If a source cannot be resolved,
returns `undef`.

### $msg->event

In message handlers, this returns the fire object.

## Message parameters

Fetch and resolve message parameters.

### $msg->params

```perl
my @params = $msg->params;
```

Returns a list of raw parameters.

### $msg->param($i)

```perl
my $msg   = message->new(':nick!ident@host PRIVMSG #channel :Hi everyone')
my $param = $msg->param(1); # 'Hi everyone'
```

Returns the parameter at the given index.

### $msg->parse_params($fmt)

Given a [format string](#universal-matchers), parses raw parameters.

This is used to verify parameter data types and to conveniently convert
nicks to user objects, channel names to channel objects, etc.
[Base::UserCommands](../../modules.md#base) and the server protocol APIs
use these for the command registry `params` option.

```perl
my $msg = message->new(':nick!ident@host PRIVMSG #channel :Hi everyone');
my ($ok, $channel, $message) = $msg->parse_params('channel *');
die "Failed to parse" if !$ok;
say "The message to ", $channel->name, " says: ", $message;
```

Returns `($ok, @params)`. `$ok` is true if the parameters were successfully
aligned with the given format; `@params` is the list of resultant parameters.

### Universal matchers

These matchers are provided for all messages. Others may be available for the
specific protocol being used.

* __-message__ - injects the message object
* __-event__ - injects the [event](#msg-event)
* __-data__ - injects the [data](#msg-data)
* __-command__ - injects the [command](#msg-command)

### Client protocol matchers

These matchers are available to all messages of the IRC client protocol.

* __-oper__ - requires that the source of the command is an IRC operator
  * [oper flags](../../oper_flags.md) may be passed as options comma-separated.
    if the user does not have one or more of them, the match fails
  * if the conditions are not met, send `ERR_NOPRIVILEGES`
* __server__ - matches a server name, yielding a server object
  * if the server does not exist, sends `ERR_NOSUCHSERVER`
* __server_mask__ - matches a server mask, which may be an absolute server name
  or may contain wildcards
  * if the local server matches, it is always preferred
  * if multiple other servers match, the result is unpredictable
  * if no servers match, sends `ERR_NOSUCHSERVER`
* __user__ - matches a nick, yielding a user object
  * if the user does not exist, sends `ERR_NOSUCHNICK`
* __channel__ - matches a channel name, yielding a channel object
  * if the channel does not exist, sends `ERR_NOSUCHCHANNEL`
  * option `inchan` requires that the source of the message is in the channel
    in order to match; if not, sends `ERR_NOTONCHANNEL`

## Message tags

[Message tags](http://ircv3.net/specs/core/message-tags-3.2.html) allow
additional named parameters to be tagged onto existing message types.

### $msg->tags

Fetches all message tags.

```perl
my $msg = message->new('@account=nicholas :nick!ident@host PRIVMSG #channel :hi');
my $tags = $msg->tags;
say 'nick is logged in as ', $tags->{account};
```

Returns a hash reference of message tags.

### $msg->tag($key)

Fetches a message tag value.

```perl
my $msg = message->new('@account=nicholas :nick!ident@host PRIVMSG #channel :hi');
say 'nick is logged in as ', $msg->tag('account');
```

### $msg->set_tag($key => $value)

Sets a message tag value.

```perl
my $msg = message->new(':nick!ident@host PRIVMSG #channel :hi');
$msg->set_tag(account => 'nicholas');
say $msg->data; # @account=nicholas :nick!ident@host PRIVMSG #channel :hi
```

## Message batch

[Batches](http://ircv3.net/specs/extensions/batch-3.2.html) allow messages to be
grouped as relating to a single operation.

### message->new_batch($batch_type, @params)

Creates a new batch.

```perl
my $batch = message->new_batch('netsplit', $server->parent->name, $server->name);
```

Returns a message for the `BATCH` command to start the batch, with an
automatically allocated identifier.

The returned message can be used for the `batch` option of [user](user.md) send
functions. This will magically associate the messages with the batch if the
user supports the necessary capabilities.

### $batch->end_batch

Terminates a batch.

```perl
my $batch = message->new_batch('netsplit', $server->parent->name, $server->name);
my $msg = message->new(source => $user, command => 'QUIT', params => $reason);
$msg->set_batch($batch);
$batch->end_batch;
```

Returns a message for the `BATCH` command to end the batch.

If the batch was used as the `batch` option of [user](user.md) send functions,
each user who received messages belonging to this batch will automatically be
sent the batch termination message upon calling `->end_batch`.

### $msg->set_batch($batch)

For any message, sets the batch to which it belongs. This adds the `batch`
message tag and stores internally that it belongs to the given batch.

```perl
my $batch = message->new_batch('netsplit', $server->parent->name, $server->name);
my $msg = message->new(source => $user, command => 'QUIT', params => $reason);
$msg->set_batch($batch);
```

## Message propagation

In handlers for server protocol messages, these methods are provided for
message propagation.

### $msg->broadcast($event_name => @args)

Forwards the message to all uplinks besides the one we received it from.

```perl
$msg->broadcast(nick_change => $user);
```

### $msg->forward_plus_one($event_name => @args)

Forwards the message to all uplinks, even the one we received it from.

```perl
$msg->forward_plus_one(oper => $user, @flags);
```

### $msg->forward_to($server, $event_name => @args)

Forwards the message to a specific server.

```perl
$msg->forward_to($t_server, whois => $user, $t_user, $t_server);
```

### $msg->forward_to_mask($server_mask, $event_name => @args)

Forwards the message to all servers matching a mask.

```perl
$msg->forward_to_mask($serv_mask, sasl_host_info => @common, $data, $ip);
```
