# Copyright (c) 2009-17, Mitchell Cooper
#
# @name:            "ircd::connection"
# @package:         "connection"
# @description:     "represents a connection to the server"
# @version:         ircd->VERSION
#
# @no_bless
# @preserve_sym
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package connection;

use warnings;
use strict;
use 5.010;
use parent 'Evented::Object';

use Socket::GetAddrInfo;
use Scalar::Util qw(weaken blessed looks_like_number);
use utils qw(conf v notice broadcast irc_match ref_to_list simplify);

our ($api, $mod, $me, $pool, $conf);

sub init {

    # send unknown command. this is canceled by handlers.
    $pool->on('connection.message' => sub {
        my ($conn, $event, $msg) = @_;

        # ignore things that aren't a big deal.
        return if $msg->command eq 'NOTICE' && ($msg->param(0) || '') eq '*';
        return if $msg->command eq 'PONG' || $msg->command eq 'PING';
        return if looks_like_number($msg->command); # numeric

        # server command unknown.
        if ($conn->server) {
            my ($command, $name) = ($msg->command, $conn->server->name);
            my $proto = $conn->server->{link_type};
            notice(server_protocol_warning =>
                $conn->server->notice_info,
                "sent $command which is unknown by $proto; ignored"
            );
            return;
        }

        $conn->numeric(ERR_UNKNOWNCOMMAND => $msg->raw_cmd);
        return;
    }, name => 'ERR_UNKNOWNCOMMAND', priority => -200, with_eo => 1);
}

# create a new connection
sub new {
    my ($class, $stream) = @_;
    return unless $stream && $stream->{write_handle};

    # check the IP.
    my $ip = $stream->{write_handle}->peerhost;
    $ip = utils::safe_ip(utils::embedded_ipv4($ip) || $ip);

    # create the connection object.
    bless my $conn = {
        stream        => $stream,
        ip            => $ip,
        host          => $ip,
        family        => $stream->write_handle->sockdomain,
        localport     => $stream->write_handle->sockport,
        peerport      => $stream->write_handle->peerport,
        ssl           => $stream->isa('IO::Async::SSLStream'),
        source        => $me->{sid},
        time          => time,
        last_response => time,
        last_command  => time,
        wait          => {}
    }, $class;

    # two initial waits:
    # in clients - one for NICK   (id1), one for USER (id2).
    # in servers - one for SERVER (id1), one for PASS (id2).
    $conn->reg_wait('id1');
    $conn->reg_wait('id2');

    return $conn;
}

# handle incoming data
sub handle {
    my ($conn, $data) = @_;

    # update ping information.
    delete @$conn{'ping_in_air', 'warned_ping'};
    $conn->{last_response} = time;

    # connection is being closed or empty line.
    return if $conn->{goodbye} || !length $data;

    my $name = $conn->type ? $conn->type->name : '(unregistered)';
    D("R[$name] $data") if $::enable_data_debug;

    # create a message.
    my $msg = message->new(
        data            => $data,
        source          => $conn,
        real_message    => 1
    );
    my $cmd = $msg->command;

    # connection events.
    my @events = (
        [ message               => $msg ],
        [ "message_${cmd}"      => $msg ]
    );

    # user events.
    if (my $user = $conn->user) {
        push @events, $user->_events_for_message($msg);
        $conn->{last_command} = time
            unless $cmd eq 'PING' || $cmd eq 'PONG';
    }

    # server $PROTO_message events.
    elsif (my $server = $conn->server) {
        my $proto = $server->{link_type};
        push @events, [ $server, "${proto}_message"        => $msg ],
                      [ $server, "${proto}_message_${cmd}" => $msg ];
        $msg->{_physical_server} = $server;
    }

    # fire with safe option.
    my $fire = $conn->prepare(@events)->fire('safe');

    # an exception occurred.
    if (my $e = $fire->exception) {
        my $stopper = $fire->stopper;
        notice(exception => "Error in $cmd from $stopper: $e");
        return;
    }

    return 1;
}

# increase the registration wait count
sub reg_wait {
    my ($conn, $name) = @_;
    $conn->{wait} or return;
    $conn->{wait}{$name} = 1;
}

# decrease the registration wait count
sub reg_continue {
    my ($conn, $name) = @_;
    $conn->{wait} or return;
    delete $conn->{wait}{$name};
    $conn->ready unless scalar keys %{ $conn->{wait} };
}

# called when all waits are complete and registration can continue
sub ready {
    my $conn = shift;
    
    # already ready, or connection has been closed
    return if $conn->{ready} || $conn->{goodbye};

    # check for errors
    if (my $err = $conn->verify) {
        $conn->done($err);
        return;
    }

    # Safe point - ready!
    $conn->fire('ready');

    # must be a user.
    if ($conn->{looks_like_user}) {

        # check if the ident is valid.
        if (!utils::validident($conn->{ident})) {
            $conn->early_reply(NOTICE =>
                ':*** Your username is invalid.');
            $conn->done("Invalid username [$$conn{ident}]");
            return;
        }

        # at this point, if a user by this nick exists, fall back to UID.
        delete $conn->{nick}
            if $pool->lookup_user_nick($conn->{nick});

        # create a new user.
        my $user = $conn->{type} = $pool->new_user(
            %$conn,
            conn                     => $conn,
            $Evented::Object::props  => {},
            $Evented::Object::events => {}
        );

        weaken($user->{conn});
        $conn->fire(user_ready => $user);

        # we notify other servers of the new user in $user->_new_connection
    }

    # must be a server.
    elsif ($conn->{looks_like_server}) {
        my $name = $conn->{name};

        # check if the server is linked already.
        if (my $err = server::protocol::check_new_server(
        $conn->{sid}, $conn->{name}, $me->{name})) {
            notice(connection_invalid => $conn->{ip}, 'Server exists');
            $conn->done($err);
            return;
        }

        # create a new server.
        my $server = $conn->{type} = $pool->new_server(
            %$conn,
            $Evented::Object::props  => {},
            $Evented::Object::events => {}
        );

        weaken($server->{conn} = $conn);
        $conn->fire(server_ready => $server);

        # tell other servers.
        broadcast(new_server => $server);
        $server->fire('initially_propagated');
        $server->{initially_propagated}++;
    }

    $conn->fire(ready_done => $conn->type);
    $conn->type->_new_connection if $conn->user;
    return $conn->{ready} = 1;
}


# verifies the connection is valid. this is checked after the connection
# becomes ready and registration should continue
sub verify {
    my $conn = shift;
    $conn->{verify}++;
    
    # guess what type of connection this is
    $conn->{looks_like_user} //=
        length $conn->{nick} && length $conn->{ident};
    $conn->{looks_like_server} //=
        length $conn->{name};
    my $is_serv = $conn->{looks_like_server};
    my $is_user = $conn->{looks_like_user};
    
    # neither server nor user
    if (!$is_serv && !$is_user) {
        warn 'Connection ->ready called prematurely';
        return 'Alien';
    }
    
    # force class recalculation
    delete $conn->{class_name};
    my $class = $conn->class_name;
    
    # connection matches no class
    return 'Not accepting connections'
        if !$class;

    # if the connection IP limit has been reached, disconnect.
    my $ip = $conn->ip;
    my $same_ip = scalar grep { $_->{ip} eq $ip } $pool->connections;
    return 'Connections per IP limit exceeded'
        if $same_ip > $conn->class_max('perip');
        
    # if the global user IP limit has been reached, disconnect.
    $same_ip = scalar grep { $_->{ip} && $_->{ip} eq $ip }
        $pool->real_users, $pool->servers;
    return 'Global connections per IP limit exceeded'
        if $same_ip > $conn->class_max('globalperip');
        
        # if the client limit has been reached, hang up.
    my $max_client = $conn->class_max('client');
    if (!$is_serv && scalar $pool->real_local_users >= $max_client) {
        $conn->done('Not accepting clients');
        return;
    }
        
    return; # success
}

# send data
sub send {
    my ($conn, @msg) = @_;

    # check that there is a writable stream.
    return unless $conn->stream;
    return unless $conn->stream->write_handle;
    return if $conn->{goodbye};
    @msg = grep defined, @msg;
    my $name = $conn->type ? $conn->type->name : '(unregistered)';
    for (@msg) {
        last if !$::enable_data_debug;
        D("S[$name] $_");
    }
    $conn->stream->write("$_\r\n") foreach @msg;
}

# send data with a source
sub sendfrom {
    my ($conn, $source) = (shift, shift);
    $conn->send(map { ":$source $_" } @_);
}

# send data from this server
# JELP SID if server (for compatibility), server name otherwise
sub sendme {
    my $conn = shift;
    my $source =
        $conn->server ? $me->{sid} : $me->{name};
    $conn->sendfrom($source, @_);
}

sub stream { shift->{stream}                }   # IO::Async::Stream
sub sock   { shift->stream->{write_handle}  }   # IO::Socket::IP
sub ip     { shift->{ip}                    }   # IP address

# send a command to a possibly unregistered connection
sub early_reply {
    my ($conn, $cmd) = (shift, shift);
    my $target = ($conn->user || $conn)->{nick} // '*';
    $conn->sendme("$cmd $target @_");
}

# terminates the connection, quitting the associated user or server, if any
sub done {
    my ($conn, $reason) = @_;
    return if $conn->{goodbye};
    L("Closing connection from $$conn{ip}: $reason");

    # a user or server is associated with the connection.
    if ($conn->type && !$conn->type->{did_quit}) {

        # share this quit with the children.
        broadcast(quit => $conn, $reason)
            if $conn->type->{initially_propagated} &&
            !$conn->{killed};

        # tell user.pm or server.pm that the connection is closed.
        $conn->type->quit($reason);
        $conn->type->{did_quit}++;

    }

    # this is safe because ->send() is safe now.
    $conn->send("ERROR :Closing Link: $$conn{host} ($reason)");

    # remove from connection the pool if it's still there.
    # if the connection has reserved a nick, release it.
    my $r = defined $conn->{nick} ?
        $pool->nick_in_use($conn->{nick}) : undef;
    $pool->release_nick($conn->{nick}) if $r && $r == $conn;
    $pool->delete_connection($conn, $reason) if $conn->{pool};

    # will close it WHEN the buffer is empty
    # (if the stream still exists).
    $conn->stream->close_when_empty
        if $conn->stream && $conn->stream->write_handle;

    # destroy these references, just in case.
    delete $conn->type->{conn} if $conn->type;
    delete $conn->{$_} foreach qw(type location server stream);

    # prevent confusion if buffer spits out more data.
    delete $conn->{ready};
    $conn->{goodbye}++;

    # fire done event, then
    # delete all callbacks to dispose of any possible
    # looping references within them.
    $conn->fire(done => $reason);
    $conn->clear_futures;
    $conn->delete_all_events;

    return 1;
}

# sends a numeric
# this is used mostly for unregistered connections
# user->numeric() is preferred for users
sub numeric {
    my ($conn, $const, @response) = (shift, shift);

    # does not exist.
    if (!$pool->numeric($const)) {
        L("attempted to send nonexistent numeric $const");
        return;
    }

    my ($num, $val, $allowed) = @{ $pool->numeric($const) };

    # CODE reference for numeric response.
    if (ref $val eq 'CODE') {
        $allowed or L("$const only allowed for users") and return;
        @response = $val->($conn, @_);
    }

    # formatted string.
    else {
        @response = sprintf $val, @_;
    }

    # ignore registered servers.
    return if $conn->server;

    # send.
    my $nick = ($conn->user || $conn)->{nick} // '*';
    $conn->sendme("$num $nick $_") foreach @response;

    return 1;
}

# what protocols might this be, according to the port?
sub possible_protocols {
    my ($conn, @protos) = shift;
    
    # established server
    return $conn->{link_type}
        if defined $conn->{link_type};
        
    # established user
    return 'client'
        if $conn->user;
        
    # unregistered client, so we have to guess based on the port.
    # client connections are currently permitted on all ports,
    # and JELP connections are permitted on all ports which are not
    # explicitly associated with another linking protocol.
    my $port = $conn->{localport};
    return ('client', $ircd::listen_protocol{$port} || 'jelp');
}

# could this connection be protocol?
sub possibly_protocol {
    my ($conn, $proto) = @_;
    return grep { $_ eq $proto } $conn->possible_protocols;
}

# returns the protocol associated with this connection
# ONLY IF it is absolutely certain (due to a dedicated port or registered
# client or server), undef otherwise
sub protocol {
    my @protos = shift->possible_protocols;
    return $protos[0] if @protos == 1;
    return undef;
}

####################
### CAPABILITIES ###
####################

# has a capability
sub has_cap {
    my ($obj, $flag) = (shift, lc shift);
    return unless $obj->{cap_flags};
    foreach my $f (@{ $obj->{cap_flags} }) {
        return 1 if $f eq $flag;
    }
    return;
}

# add a capability
sub add_cap {
    my ($obj, @flags) = (shift, map { lc } @_);
    foreach my $flag (@flags) {
        next if $obj->has_cap($flag);
        push @{ $obj->{cap_flags} ||= [] }, $flag;
    }
    return 1;
}

# remove a capability
sub remove_cap {
    my ($obj, @flags) = (shift, map { lc } @_);
    return unless $obj->{cap_flags};
    my %all_flags = map { $_ => 1 } @{ $obj->{cap_flags} };
    delete @all_flags{@flags};
    @{ $obj->{cap_flags} } = keys %all_flags;
}

#############
### FLAGS ###
#############

# flag list
sub flags {
    my $obj = shift;
    return @{ $obj->{flags} || [] };
}

# has a flag
sub has_flag {
    my ($obj, $flag) = @_;
    foreach ($obj->flags) {
        return 1 if $_ eq $flag;
        return 1 if $_ eq 'all';
    }
    return;
}

# add flags
sub add_flags {
    my $obj = shift;
    my $their_flags = $obj->{flags} ||= [];

    # weed out duplicates
    my %has   = map  { $_ => 1   } $obj->flags;
    my @flags = grep { !$has{$_} } simplify(@_);
    return unless @flags;

    # add the flags
    push @$their_flags, @flags;

    # return the flags that were added
    return @flags;
}

# remove flags
sub remove_flags {
    my $obj = shift;
    my $their_flags = $obj->{flags} or return;
    my %remove = map { $_ => 1 } @_;
    my (@new, @removed);
    foreach my $flag (@$their_flags) {
        if ($remove{$flag}) {
            push @removed, $flag;
            next;
        }
        push @new, $flag;
    }
    @$their_flags = @new;
    return @removed;
}

# clear all flags
sub clear_flags {
    my $obj = shift;
    return $obj->remove_flags($obj->flags);
}

###############
### CLASSES ###
###############

our %class_cache;

# fetch connection class options
#
# my %opts = $conn->class_conf
# my $val  = $conn->class_conf($key)
# my %opts = connection::class_conf($class)
# my $val  = connection::class_conf($class, $key)
#
sub class_conf {
    my ($conn, $key) = @_;
    
    # determine class name
    my $class = blessed $conn ? $conn->class_name : $conn;
    if (!$class) {
        return if !$key;
        return undef;
    }
    
    # check for cached version
    my %h;
    if (my $cached = $class_cache{$class}) {
        %h = %$cached;
    }
    
    # fetch from config
    else {
        %h = $conf->hash_of_block([ 'class', $class ]);
        my $extends = $h{extends} || 'default';
        undef $extends if $class eq 'default';
        if ($extends) {
            %h = (class_conf($extends), %h);
            $h{priority}++;
        }
        $class_cache{$class} = \%h;
    }
    
    return $h{$key} if $key;
    return %h;
}

# fetch connection class limits
sub class_max {
    my ($conn, $name) = @_;
    
    # prefer the one defined in the class if possible
    my $max = $conn->class_conf("max_$name");
    return $max if defined $max;
    
    # fall back to the one defined in [limit]
    # this likely comes from default.conf
    return conf('limit', $name);
}

# fetch flags for a class
# connection::class_flags($class, $type)
sub class_flags {
    my ($class, $type) = @_;
    my %h = class_conf($class);
    return grep { $h{$_} && s/^\Q$type\E_// } keys %h;
}

# returns the class name for the connection
sub class_name {
    my $conn = shift;
    return $conn->{class_name} if $conn->{class_name};
    
    # determine the class
    my ($class_chosen, $class);
    foreach my $maybe ($conf->names_of_block('class')) {
        my $class_ref = { class_conf($maybe) };
        my @used_bits;
        
        # skip oper classes here
        next if $class_ref->{requires_oper};
        
        # find allowed server and user masks
        my @servers = ref_to_list($class_ref->{allow_servers});
        my @users   = ref_to_list($class_ref->{allow_users});
        my @conns   = ref_to_list($class_ref->{allow_anons});
        
        # server
        if (@servers) {
            next if !$conn->{looks_like_server};
            
            # neither hostname nor IP match
            next if !irc_match($conn->{host}, @servers)
                 && !irc_match($conn->{ip},   @servers);
                 
            push @used_bits, @servers;
        }
        
        # user
        elsif (@users) {
            next if !$conn->{looks_like_user};
            
            # neither user@hostname nor user@IP match
            my $prefix = ($$conn{ident} // '*').'@';
            next if !irc_match($prefix.$conn->{host}, @users)
                 && !irc_match($prefix.$conn->{ip},   @users);
                 
            push @used_bits, @users;
        }
        
        # unregistered connection
        elsif (@conns) {
            
            # neither hostname nor IP match
            next if !irc_match($conn->{host}, @conns)
                 && !irc_match($conn->{ip},   @conns);
                 
            push @used_bits, @conns;
        }
        
        # class has no allow options
        else {
            L("'$maybe' has none of allow_anons, allow_users, allow_servers");
            next;
        }
        
        # nothing matched
        next if !@used_bits;

        # determine priority
        my $priority = $class_ref->{priority} += _get_priority(@used_bits);
        
        # current chosen one has higher priority
        if ($class_chosen) {
            next if $class_chosen->{priority} > $priority;
        
            # equal priorities...
            L("'$class' and '$maybe' have same priority! ($priority)")
                if $class_chosen->{priority} == $priority;
        }
        
        $class_chosen = $class_ref;
        $class = $maybe;
    }
    
    D("Using class '$class' for $$conn{ip}");
    return $conn->{class_name} = $class;
}

sub _get_priority {
    my @chars = map { split // } @_;
    return scalar grep { $_ ne '*' && $_ ne '?' } @chars;
}

###############
### FUTURES ###
###############

# add a future which represents a pending operation related to the connection.
# it will automatically be removed when it completes or fails.
sub adopt_future {
    my ($conn, $name, $f) = @_;
    $conn->{futures}{$name} = $f;
    weaken(my $weak_conn = $conn);
    $f->on_ready(sub { $weak_conn->abandon_future($name) });
}

# remove a future. this is only necessary if you want to cancel a future which
# has not finished. however, calling it with an expired one produces no error.
sub abandon_future {
    my ($conn, $name) = @_;
    my $f = delete $conn->{futures}{$name} or return;
    $f->cancel; # it may already be canceled, but that's ok
}

# clear all futures associated with a connection.
sub clear_futures {
    my $conn = shift;
    my $count = 0;
    $conn->{futures} or return $count;
    foreach my $name (keys %{ $conn->{futures} }) {
        $conn->abandon_future($name);
        $count++;
    }
    return $count;
}

#############
### TYPES ###
#############

# user or server associated with this connection
sub type { shift->{type} }

# user associated with this connection, if any
sub user {
    my $type = shift->type;
    blessed $type && $type->isa('user') or return;
    return $type;
}

# server associated with this connection, if any
sub server {
    my $type = shift->type;
    blessed $type && $type->isa('server') or return;
    return $type;
}

$mod
