# Copyright (c) 2009-14, Mitchell Cooper
#
# @name:            "ircd"
# @package:         "ircd"
# @description:     "main IRCd module"
# @version:         $ircd::VERSION || $main::VERSION
# @no_bless:        1
# @preserve_sym:    1
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package ircd;

use warnings;
use strict;
use 5.010;
use Module::Loaded qw(is_loaded);

our ($api, $mod, $me, $pool, $loop, $conf, $boot, $timer, $VERSION, %channel_mode_prefixes);

######################
### INITIALIZATION ###
######################

sub init {

    # load utils immediately.
    $mod->load_submodule('utils') or return;
    utils->import(qw|conf fatal v trim|);
    $VERSION = get_version();
    
    &set_variables;         # set default global variables.
    &boot;                  # boot if we haven't already.
    
    L('Started server at '.scalar(localtime v('START')));
    
    # TODO: check @INC.
    &load_dependencies;     # load or reload all dependency packages.
    &setup_config;          # parse the configuration.
    &load_optionals;        # load or reload optional packages.
    &setup_database;        # set up SQLite if necessary.

    # create the server before the server module is loaded.
    # these default values will be added if not present,
    # even when reloading the ircd module.
    $me = $::v{SERVER} ||= bless {}, 'server';
    $me->{ $_->[0] } //= $_->[1] foreach (
        [ umodes   => {} ],
        [ cmodes   => {} ],
        [ users    => [] ],
        [ children => [] ]
    );
    $me->{parent} = $me; # looping reference, but it'll never be disposed of.

    # exported variables in modules.
    # note that these will not be available in the utils module.
    $api->on('module.set_variables' => sub {
        my ($event, $pkg) = @_;
        my $obj = $event->object;
        Evented::API::Hax::set_symbol($pkg, {
            '$me'   => $me,
            '$pool' => $pool,
            '*L'    => sub { _L($obj, [caller 1], @_) }
        });
    });

    # load submodules. create the pool.
    # utils pool user(::mine) server(::mine,::linkage) channel(::mine) connection
    $mod->load_submodule('pool') or return;
    $ircd::pool = $::pool ||= pool->new; # must be ircd::pool; don't change.
    $mod->load_submodule($_) or return foreach qw(user server channel connection);

    # TODO: new values are NOT inserted after reloading.
    # I had an idea once upon a time to make $server->configure(%opts)
    # which would optionally only set the values if nothing exists there.
    # but this works for now.
    $pool->new_server($me,
        source => conf('server', 'id'),
        sid    => conf('server', 'id'),
        name   => conf('server', 'name'),
        desc   => conf('server', 'description'),
        proto  => v('PROTO'),
        ircd   => v('VERSION'),
        time   => v('START')
    ) if not exists $me->{source};


    &setup_modes;           # set up local server modes.
    &setup_modules;         # load API modules.
    &setup_sockets;         # start listening.
    &setup_timer;           # set up ping timer.
    &setup_autoconnect;     # connect to servers with autoconnect enabled.
    
    L("server initialization complete");
    return 1;
}

sub setup_modules {
    return if $mod->{loading};
    
    # load API modules unless we're reloading.
    L('Loading API configuration modules');
    $api->load_modules(@{ conf('api', 'modules') || [] });
    L('Done loading modules');
    
}

sub setup_config {

    # set up the configuration/database.
    # TEMPORARILY use no database until we read [database] block.
    $conf = Evented::Database->new(
        db       => undef,
        conffile => "$::run_dir/etc/ircd.conf"
    );
        
    # parse the configuration.
    $conf->parse_config or return;
    
    return 1;
}

sub setup_modes {

    # register modes.
    &add_internal_channel_modes;
    &add_internal_user_modes;

}

sub setup_timer {

    # delete the existing timer if there is one.
    if ($timer = $::timer) {
        $loop->remove($timer) if $timer->is_running;
    }
    
    # create a new timer.
    $timer = $::timer = IO::Async::Timer::Periodic->new(
        interval => 30,
        on_tick  => \&ping_check
    );
    $loop->add($timer);
    $timer->start;
        
}

sub setup_database {

    # create the database object.
    if (conf('database', 'type') eq 'sqlite') {
        my $dbfile  = "$::run_dir/db/conf.db";
        $conf->{db} = DBI->connect("dbi:SQLite:dbname=$dbfile", '', '');
        $conf->create_tables_maybe;
    }
    
}

sub setup_autoconnect {

    # auto server connect.
    # FIXME: don't try to connect during reload if already connected.
    # honestly this needs to be moved to an event for after loading the configuration;
    # even if it's a rehash or something it should check for this.
    foreach my $name ($conf->names_of_block('connect')) {
        next unless conf(['connect', $name], 'autoconnect');
        server::linkage::connect_server($name);
    }
    
}

sub set_variables {

    # defaults; replace current values.
    my %v_replace = (
        NAME    => 'kylie',         # major version name
        SNAME   => 'juno',          # short ircd name
        LNAME   => 'juno-ircd',     # long ircd name
        VERSION => $VERSION,        # combination of these 3 in VERSION command
        PROTO   => '6.1',
    );

    # defaults; only set if not existing already.
    my %v_insert = (
        START   => time,
        NOFORK  => 'NOFORK' ~~ @ARGV,
        connection_count      => 0,
        max_connection_count  => 0,
        max_global_user_count => 0,
        max_local_user_count  => 0
    );

    # replacements.
    @::v{keys %v_replace} = values %v_replace;
    
    # insertions.
    my @missing_keys    = grep { not exists $::v{$_} } keys %v_insert;
    @::v{@missing_keys} = @v_insert{@missing_keys};
    
}

sub setup_sockets {

    # start listeners.
    foreach my $addr ($conf->names_of_block('listen')) {
        my @ports = @{ $conf->get(['listen', $addr], 'port') || [] };
        listen_addr_port($addr, $_) foreach @ports;
    }
    
    # remove dead listeners.
    foreach my $listener (grep { $_->isa('IO::Async::Listener') } $loop->notifiers) {
        next if $listener->read_handle;
        $loop->remove($listener);
    }
    
}

sub listen_addr_port {
    my ($addr, $port) = @_;
    
    # create the loop listener.
    my $listener = IO::Async::Listener->new(on_stream => \&handle_connect);
    $loop->add($listener);

    # create the socket
    my $socket = IO::Socket::IP->new(
        LocalAddr => $addr,
        LocalPort => $port,
        Listen    => 1,
        ReuseAddr => 1,
        Type      => Socket::SOCK_STREAM(),
        Proto     => 'tcp'
    ) or L("Couldn't listen on [$addr]:$port: $!") and return;

    # add to looped listener
    $listener->listen(handle => $socket);

    L("Listening on [$addr]:$port");
}

# refuse unload unless reloading.
sub void {
    return $mod->{reloading};
}

##########################
### PACKAGE MANAGEMENT ###
##########################

# load or reload a package.
sub load_or_reload {
    my ($name, $min_v) = @_;
    (my $file = "$name.pm") =~ s/::/\//g;

    # it might be loaded with an appropriate version already.
    if ((my $v = $name->VERSION // -1) >= $min_v) {
        L("$name is loaded and up-to-date ($v)");
        return;
    }
    
    # at this point, we're going to load it.
    # if it's loaded already, we should unload it now.
    Evented::API::Hax::package_unload($name) if is_loaded($name);
    
    # it hasn't been loaded yet at all.
    # use require to load it the first time.
    if (!is_loaded($name) && !$name->VERSION) {
        L("Loading $name");
        require $file or L("Very bad error: could not load $name!".($@ || $!));
        return;
    }
    
    # load it.
    L("Reloading package $name");
    do $file or L("Very bad error: could not load $name! ".($@ || $!)) and return;
    
    # version check.
    if ((my $v = $name->VERSION // -1) < $min_v) {
        L("Very bad error: $name is outdated ($min_v required, $v loaded)");
        return;
    }
    
    return 1;
}

# load our package dependencies.
sub load_dependencies {

    # main dependencies.
    load_or_reload(@$_) foreach (
    
        [ 'Evented::API::Engine',          3.40 ],
        [ 'Evented::API::Module',          3.40 ],
        [ 'Evented::API::Hax',             3.40 ],
        
        [ 'IO::Async::Loop',               0.60 ],
        [ 'IO::Async::Stream',             0.60 ],
        [ 'IO::Async::Listener',           0.60 ],
        [ 'IO::Async::Timer::Periodic',    0.60 ],
        [ 'IO::Async::Timer::Countdown',   0.60 ],
        [ 'IO::Socket::IP',                0.25 ],
        [ 'Evented::Object',               4.50 ],
        [ 'Evented::Configuration',        3.40 ],
        [ 'Evented::Database',             0.50 ]
    );
    
}

# load configured optional packages.
sub load_optionals {
    
    #load_or_reload('Digest::SHA', 0) if conf qw[enabled sha];
    #load_or_reload('Digest::MD5', 0) if conf qw[enabled md5];
    load_or_reload('DBD::SQLite', 0) if conf('database', 'type') eq 'sqlite';

}

###############
### SIGNALS ###
###############

# handle a HUP
# TODO: do something. LOL
sub signalhup  { }
sub signalpipe { }

# handle warning
sub WARNING { L(shift) }

#####################
### INCOMING DATA ###
#####################

# handle connecting user or server
sub handle_connect {
    my ($listener, $stream) = @_;

    # if the connection limit has been reached, disconnect
    if (scalar keys %connection::connection >= conf('limit', 'connection')) {
        $stream->close_now;
        return
    }

    # if the connection IP limit has been reached, disconnect
    my $ip = $stream->{write_handle}->peerhost;
    if (scalar(grep { $_->{ip} eq $ip } $pool->connections) >= conf('limit', 'perip')) {
        $stream->close_now;
        return
    }

    # if the global user IP limit has been reached, disconnect
    if (scalar(grep { $_->{ip} eq $ip } $pool->actual_users) >= conf('limit', 'globalperip')) {
        $stream->close_now;
        return;
    }

    # create connection object
    my $conn = $pool->new_connection(stream => $stream);

    $stream->configure(
        read_all       => 0,
        read_len       => POSIX::BUFSIZ(),
        on_read        => \&handle_data,
        on_read_eof    => sub { $conn->done('Connection closed');   $stream->close_now },
        on_write_eof   => sub { $conn->done('Connection closed');   $stream->close_now },
        on_read_error  => sub { $conn->done('Read error: ' .$_[1]); $stream->close_now },
        on_write_error => sub { $conn->done('Write error: '.$_[1]); $stream->close_now }
    );

    $loop->add($stream);
}

# handle incoming data
sub handle_data {
    my ($stream, $buffer) = @_;
    my $connection = $pool->lookup_connection($stream) or return;
    my $is_server  = $connection->{type} && $connection->{type}->isa('server');
    
    # fetch the values at which the limit was exceeded.
    my $overflow_1line = (my $max_in_line = conf('limit', 'bytes_line')  // 2048) + 1;
    my $overflow_lines = (my $max_lines   = conf('limit', 'lines_sec')   // 30  ) + 1;
    
    foreach my $char (split '', $$buffer) {
        my $length = length $connection->{current_line} || 0;
    
        # end of line.
        if ($char eq "\n") {
            
            # a line other than the first of this second.
            my $time = int time;
            if (exists $connection->{lines_sec}{$time}) {
                $connection->{lines_sec}{$time}++;
            }
            
            # first line of this second; overwrite entire hash.
            else {
                $connection->{lines_sec} = { $time => 1 };
            }
            
            # too many lines!
            my $num_lines = $connection->{lines_sec}{$time};
            if ($num_lines == $overflow_lines && !$is_server) {
                $connection->done("Exceeded $max_lines lines per second");
                return;
            }
            
            # no error. handle this data.
            $connection->handle(delete $connection->{current_line});
            $length = 0;
            
            next;
        }
        
        # even if this is an unwanted character, count it toward limit.
        $length++;
        
        # line too long.
        if ($length == $overflow_1line && !$is_server) {
            $connection->done("Exceeded $max_in_line bytes in line");
            return;
        }
        
        # unwanted characters.
        next if $char eq "\0" || $char eq "\r";
        
        # regular character;
        ($connection->{current_line} //= '') .= $char;
        
    }
    
    $$buffer = '';
}

# send out PINGs and check for timeouts
sub ping_check {
    foreach my $connection ($pool->connections) {
    
        # not yet registered.
        # if they have been connected for 30 secs without registering, drop.
        if (!$connection->{type}) {
            $connection->done('Registration timeout') if time - $connection->{time} > 30;
            next;
        }
        
        my $type = $connection->{type}->isa('user') ? 'user' : 'server';
        my $since_last = time - $connection->{last_response};
        
        # no incoming data for configured frequency.
        next unless $since_last >= conf(['ping', $type], 'frequency');
        
        # send a ping if we haven't already.
        if (!$connection->{ping_in_air}) {
            $connection->send("PING :$$me{name}");
            $connection->{ping_in_air} = 1;
        }
    
        # ping timeout.
        $connection->done("Ping timeout: $since_last seconds")
          if $since_last >= conf(['ping', $type], 'timeout');
        
    }
}

####################
### IRCD ACTIONS ###
####################

# stop the ircd
sub terminate {

    L("removing all connections for server shutdown");

    # delete all users/servers/other
    foreach my $connection ($pool->connections) {
        $connection->done('Shutting down');
    }

    L("deleting PID file");

    # delete the PID file
    unlink 'etc/juno.pid' or fatal("Can't remove PID file");

    L("shutting down");
    exit;
}

# rehash the server.
sub rehash {
    eval { $conf->parse_config } or L("Configuration error: ".($@ || $!)) and return;
    setup_sockets();
}

sub boot {
    return if $::has_booted;
    $boot = 1;
    $::VERSION = $VERSION;
    
    # load mandatory boot stuff.
    require POSIX;
    require IO::Async;
    require IO::Async::Loop;

    L("this is $::v{NAME} version $VERSION");
    $::loop = $loop = IO::Async::Loop->new;

    become_daemon();
    
    undef $boot;
    $::has_booted = 1;
}

sub loop {
    $loop->loop_forever;
}

sub become_daemon {
    open my $pidfh, '>', "$::run_dir/etc/juno.pid" or fatal("Can't write $::run_dir/etc/juno.pid");

    # become a daemon.
    if (!v('NOFORK')) {
        L('Becoming a daemon...');

        # since there will be no input or output from here on,
        # open the filehandles to /dev/null
        open STDIN,  '<', '/dev/null' or fatal("Can't read /dev/null: $!");
        open STDOUT, '>', '/dev/null' or fatal("Can't write /dev/null: $!");
        open STDERR, '>', '/dev/null' or fatal("Can't write /dev/null: $!");

        # try to fork.
        $::v{PID} = fork;
        
        # it worked.
        if (v('PID')) {
            say $pidfh v('PID');
            $::v{DAEMON} = 1;
        }

        close $pidfh;
        
    }
    
    # don't become a daemon.
    else {
        $::v{PID} = $$;
        say $pidfh $$;
        close $pidfh;
    }

    # exit if daemonization was successful.
    if (v('DAEMON')) {
        exit;
        POSIX::setsid();
    }
    
}   

# get version from VERSION file.
# $::VERSION = version of IRCd when it was started; version of static code
# $ircd::VERSION = version of ircd.pm and all reloadable packages at last reload
# $API::Module::Core::VERSION = version of the core module currently
# v('VERSION') = same as $ircd::VERSION
sub get_version {
    open my $fh, '<', "$::run_dir/VERSION" or L("Cannot open VERSION: $!") and return;
    my $version = trim(<$fh>);
    close $fh;
    return $version;
}

#####################
### CHANNEL MODES ###
#####################

# this just tells the internal server what
# mode is associated with what letter and type by configuration
sub add_internal_channel_modes {
    
    L('registering channel status modes');
    $me->{cmodes}      = {};
    %channel_mode_prefixes = ();

    # [letter, symbol, name]
    foreach my $name ($conf->keys_of_block('prefixes')) {
        my $p = conf('prefixes', $name);
        $me->add_cmode($name, $p->[0], 4);
        $channel_mode_prefixes{$p->[2]} = [ $p->[0], $p->[1], $name ]
    }

    L("registering channel mode letters");

    foreach my $name ($conf->keys_of_block(['modes', 'channel'])) {
        $me->add_cmode(
            $name,
            (conf(['modes', 'channel'], $name))->[1],
            (conf(['modes', 'channel'], $name))->[0]
        );

    }

    L("end of channel modes");
}

# get a +modes string
sub channel_mode_string {
    my @modes = sort { $a cmp $b } map { $_->[1] } $conf->values_of_block('modes', 'channel');
    return join '', @modes;
}

##################
### USER MODES ###
##################

# this just tells the internal server what
# mode is associated with what letter as defined by the configuration
sub add_internal_user_modes {    
    $me->{umodes} = {};
    return unless $conf->has_block(['modes', 'user']);
    L("registering user mode letters");
    foreach my $name ($conf->keys_of_block(['modes', 'user'])) {
        $me->add_umode($name, conf(['modes', 'user'], $name));
    }
    L("end of user mode letters");
}

# returns a string of every mode
sub user_mode_string {
    my @modes = sort { $a cmp $b } $conf->values_of_block(['modes', 'user']);
    return join '', @modes;
}

###############
### LOGGING ###
###############

# L() must be explicitly defined in ircd.pm only.
sub L { _L($mod, [caller 1], @_) }

# this is called by L() throughout. it can be modified safely
# past the $caller argument only.
sub _L {
    my ($obj, $caller, $line) = (shift, shift, shift);
   (my $sub  = shift // $caller->[3]) =~ s/(.+)::(.+)/$2/;
    my $info = $sub && $sub ne '(eval)' ? "$sub()" : $caller->[0];
    return unless $obj->can('_log');
    $obj->_log("$info: $line");
}

$mod