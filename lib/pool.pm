# Copyright (c) 2014, Mitchell Cooper
package pool;

use warnings;
use strict;
use 5.010;
use parent 'Evented::Object';

use Scalar::Util qw(weaken blessed);

use utils qw(v log2);

# create a pool.
sub new {
    return bless { user_i => 'a' }, shift;
}

###################
### CONNECTIONS ###
###################

# create a connection.
sub new_connection {
    my ($pool, %opts) = @_;
    my $connection = connection->new($opts{stream}) or return;
    
    # store it by stream.
    $pool->{connections}{ $opts{stream} } = $connection;
    
    # weakly reference to the pool.
    weaken($connection->{pool} = $pool);
    
    # become an event listener.
    $connection->add_listener($pool, 'connection');

    # fire connection creation event.
    $connection->fire_event('new');

    # update total connection count
    v('connection_count')++;

    # update maximum connection count
    if ((scalar keys %{ $pool->{connections} }) + 1 > v('max_connection_count')) {
        v('max_connection_count') = 1 + scalar keys %{ $pool->{connections} };
    }
    
    log2("processing connection from $$connection{ip}");
    return $connection;
}

# find a connection by its stream.
sub lookup_connection {
    my ($pool, $stream) = @_;
    return $pool->{connections}{$stream};
}

# delete a connection.
sub delete_connection {
    my ($pool, $connection) = @_;
    
    # forget it.
    delete $connection->{pool};
    delete $pool->{connections}{ $connection->{stream} };
    
    log2("deleted connection from $$connection{ip}");
    return 1;
}

sub connections { values %{ shift->{connections} } }

###############
### SERVERS ###
###############

# create a server.
sub new_server {
    my ($pool, %opts) = @_;
    my $server = server->new(%opts) or return;
    
    # store it by ID and name.
    $pool->{servers}{ $opts{sid} } =
    $pool->{server_names}{ lc $opts{name} } = $server;
    
    # weakly reference to the pool.
    weaken($server->{pool} = $pool);
    
    # become an event listener.
    $server->add_listener($pool, 'server');
    
    # add as child.
    if ($opts{parent} && blessed $opts{parent}) {
        push @{ $opts{parent}{children} }, $server;
    }
    
    log2(
        "new server $$server{sid}:$$server{name} $$server{proto}-$$server{ircd} " .
        "parent:$$server{parent}{name} [$$server{desc}]"
    );
    return $server;
}

# find a server.
sub lookup_server {
    my ($pool, $sid) = @_;
    return $pool->{servers}{$sid};
}

# find a server by its name.
sub lookup_server_name {
    my ($pool, $sname) = @_;
    return $pool->{server_names}{lc $sname};
}

# delete a server.
sub delete_server {
    my ($pool, $server) = @_;
    
    # forget it.
    delete $server->{pool};
    delete $pool->{servers}{ $server->{sid} };
    delete $pool->{server_names}{ lc $server->{name} };
    
    log2("deleted server $$server{name}");
    return 1;
}

sub servers { values %{ shift->{servers} } }

#############
### USERS ###
#############

# create a user.
sub new_user {
    my ($pool, %opts) = @_;
    
    # no UID provided; generate one.
    $opts{uid} //= v('SERVER', 'sid').$pool->{user_i}++;
    
    my $user = user->new(%opts) or return;
    
    # store it by ID and nick.
    $pool->{users}{ $opts{uid} } =
    $pool->{nicks}{ lc $opts{nick} } = $user;
    
    # weakly reference to the pool.
    weaken($user->{pool} = $pool);
    
    # become an event listener.
    $user->add_listener($pool, 'user');
    
    # update max local and global user counts.
    my $max_l = v('max_local_user_count');
    my $max_g = v('max_global_user_count');
    my $c_l   = scalar grep { $_->is_local } values %{ $pool->{users} };
    my $c_g   = scalar values %{ $pool->{users} };
    v('max_local_user_count')  = $c_l if $c_l > $max_l;
    v('max_global_user_count') = $c_g if $c_g > $max_g;

    # add the user to the server.
    push @{ $opts{server}{users} }, $user;

    log2(
        "new user from $$user{server}{name}: $$user{uid} " .
        "$$user{nick}!$$user{ident}\@$$user{host} [$$user{real}]"
    );
    return $user;
}

# find a user.
sub lookup_user {
    my ($pool, $uid) = @_;
    return $pool->{users}{$uid};
}

# find a user by his nick.
sub lookup_user_nick {
    my ($pool, $nick) = @_;
    return $pool->{nicks}{lc $nick};
}

# delete a user.
sub delete_user {
    my ($pool, $user) = @_;
    
    # remove from server.
    # this isn't a very efficient way to do this.
    @{ $user->{server}{users} } = grep { $_ != $user} @{ $user->{server}{users} };
    
    # forget it.
    delete $user->{pool};
    delete $pool->{users}{ $user->{uid} };
    delete $pool->{nicks}{ lc $user->{nick} };
    
    log2("deleted user $$user{nick}");
    return 1;
}

sub users { values %{ shift->{users} } }

################
### CHANNELS ###
################

# create a channel.
sub new_channel {
    my ($pool, %opts) = @_;
    
    # make sure it doesn't exist already.
    if ($pool->{channels}{ lc $opts{name} }) {
        log2("attempted to create channel that already exists: $opts{name}");
        return;
    }
    
    my $channel = channel->new(%opts) or return;
    
    # store it by name.
    $pool->{channels}{ lc $opts{name} } = $channel;
    
    # weakly reference to the pool.
    weaken($channel->{pool} = $pool);
    
    # become an event listener.
    $channel->add_listener($pool, 'channel');
    
    log2("new channel $opts{name} at $opts{time}");
    return $channel;
}

# find a channel by its name.
sub lookup_channel {
    my ($pool, $name) = @_;
    return $pool->{channels}{lc $name};
}

# returns true if the two passed users have a channel in common.
# well actually it returns the first match found, but that's usually useless.
sub channel_in_common {
    my ($pool, $user1, $user2) = @_;
    foreach my $channel (values %{ $pool->{channels} }) {
        return $channel if $channel->has_user($user1) && $channel->has_user($user2);
    }
    return;
}

# delete a channel.
sub delete_channel {
    my ($pool, $channel) = @_;
    
    # forget it.
    delete $channel->{pool};
    delete $pool->{channels}{ lc $channel->{name} };
    
    log2("deleted channel $$channel{name}");
    return 1;
}

sub channels { values %{ shift->{channels} } }

#############################
### USER COMMAND HANDLERS ###
#############################

# register command handlers
sub register_user_handler {
    my ($pool, $source, $command) = (shift, shift, uc shift);

    # does it already exist?
    if (exists $pool->{user_commands}{$command}) {
        log2("attempted to register $command which already exists");
        return
    }

    my $params = shift;

    # ensure that it is CODE
    my $ref = shift;
    if (ref $ref ne 'CODE') {
        log2("not a CODE reference for $command");
        return
    }

    my $desc = shift;

    # success
    $pool->{user_commands}{$command} = {
        code    => $ref,
        params  => $params,
        source  => $source,
        desc    => $desc
    };
    log2("$source registered $command: $desc");
    return 1
}

# unregister handler
sub delete_user_handler {
    my ($pool, $command) = (shift, uc shift);
    log2("deleting handler $command");
    delete $pool->{user_commands}{$command};
}

sub user_handlers {
    my ($pool, $command) = (shift, uc shift);
    return $pool->{user_commands}{$command};
}

#####################
### USER NUMERICS ###
#####################

# register user numeric
sub register_numeric {
    my ($pool, $source, $numeric, $num, $fmt) = @_;

    # does it already exist?
    if (exists $pool->{numerics}{$numeric}) {
        log2("attempted to register $numeric which already exists");
        return;
    }

    $pool->{numerics}{$numeric} = [$num, $fmt];
    log2("$source registered $numeric $num");
    return 1;
}

# unregister user numeric
sub delete_numeric {
    my ($pool, $source, $numeric) = @_;

    # does it exist?
    if (!exists $pool->{numerics}{$numeric}) {
        log2("attempted to delete $numeric which does not exists");
        return;
    }

    delete $pool->{numerics}{$numeric};
    log2("$source deleted $numeric");
    
    return 1;
}

sub numeric {
    my ($pool, $numeric) = @_;
    return $pool->{numerics}{$numeric};
}

###############################
### SERVER COMMAND HANDLERS ###
###############################


# register command handlers
# ($source, $command, $callback, $forward)
sub register_server_handler {
    my ($pool, $source, $command) = (shift, shift, uc shift);

    # does it already exist?
    if (exists $pool->{server_commands}{$command}) {
        log2("attempted to register $command which already exists");
        return
    }

    # ensure that it is CODE
    my $ref = shift;
    if (ref $ref ne 'CODE') {
        log2("not a CODE reference for $command");
        return
    }

    #success
    $pool->{server_commands}{$command} = {
        code    => $ref,
        source  => $source,
        forward => shift
    };
    log2("$source registered $command");
    return 1
}

# unregister
sub delete_server_handler {
    my ($pool, $command) = (shift, uc shift);
    log2("deleting handler $command");
    delete $pool->{server_commands}{$command};
}

sub server_handlers {
    my ($pool, $command) = (shift, uc shift);
    return values $pool->{server_commands}{$command};
}

################################
### OUTGOING SERVER COMMANDS ###
################################

# register outgoing command handlers
sub register_outgoing_handler {
    my ($pool, $source, $command) = (shift, shift, uc shift);

    # does it already exist?
    if (exists $pool->{outgoing_commands}{$command}) {
        log2("attempted to register $command which already exists");
        return
    }

    # ensure that it is CODE
    my $ref = shift;
    if (ref $ref ne 'CODE') {
        log2("not a CODE reference for $command");
        return
    }

    # success
    $pool->{outgoing_commands}{$command} = {
        code    => $ref,
        source  => $source
    };
    log2("$source registered $command");
    return 1
}

# unregister
sub delete_outgoing_handler {
    my ($pool, $command) = (shift, uc shift);
    log2("deleting handler $command");
    delete $pool->{outgoing_commands}{$command}
}

# fire outgoing
sub fire_command {
    my ($pool, $server, $command, @args) = (shift, shift, uc shift, @_);
    if (!$pool->{outgoing_commands}{$command}) {
        log2((caller)[0]." fired $command which does not exist");
        return
    }

    # send
    $server->send($pool->{outgoing_commands}{$command}{code}(@args));

    return 1
}

sub fire_command_all {
    my ($pool, $command, @args) = (shift, uc shift, @_);
    if (!$pool->{outgoing_commands}{$command}) {
        log2((caller)[0]." fired $command which does not exist");
        return
    }

    # send
    v('SERVER')->send_children(undef, $pool->{outgoing_commands}{$command}{code}(@args));

    return 1
}


1