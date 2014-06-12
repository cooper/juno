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

### $user->unset_mode($mode_name)

### $user->is_mode($mode_name)

### $user->quit($reason)

### $user->change_nick($new_nick)

### $user->handle_mode_string($mode_string, $force)

### $user->mode_string

### $user->add_flags(@flags)

### $user->remove_flags(@flags)

### $user->has_flag($flag)

### $user->set_away($reason)

### $user->unset_away

### $user->is_local

### $user->full

### $user->fullreal

### $user->fullip

### $user->notice_info

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

User objects are listened upon by the [pool](pool.md). 

## Keys
