# Copyright (c) 2010-12, Mitchell Cooper
package ircd;

use warnings;
use strict;
use 5.010;

use utils qw(conf lconf log2 fatal v set trim);

our ($VERSION, $API, $conf, $loop, $pool, $timer, %global);
$VERSION = get_version();

# all non-module packages always loaded in the IRCd.
our @always_loaded = qw(

    utils       pool
    user        user::mine
    server      server::mine    server::linkage
    channel     channel::mine
    connection  ircd

); # ircd must be last

# these might be loaded, but don't load them if they're not.
our @maybe_loaded = qw(

    API::Base::Events               API::Base::ChannelModes
    API::Base::OutgoingCommands     API::Base::ServerCommands
    API::Base::UserCommands         API::Base::UserModes
    API::Base::UserNumerics

);

sub start {
    my $boot = shift;
    
    log2('Started server at '.scalar(localtime v('START')));
    $utils::v{VERSION} = $VERSION;
    
    # add these to @INC if they are not there already.
    my @add_inc = (
        "$::run_dir/lib/api-engine",
        "$::run_dir/lib/evented-object/lib",
        "$::run_dir/lib/evented-configuration/lib",
        "$::run_dir/lib/evented-database"
    ); foreach (@add_inc) { unshift @INC, $_ unless $_ ~~ @INC }
    
    # load or reload all dependency packages.
    load_dependencies($boot);
    
    # set up the configuration/database.
    # TEMPORARILY use no database until we read [database] block.
    $conf = $main::conf = Evented::Database->new(
        db       => undef,
        conffile => "$main::run_dir/etc/ircd.conf"
    );
    
    # parse the configuration.
    $conf->parse_config or die "can't parse configuration.\n";

    # load or reload optional packages.
    load_optionals($boot);
    
    # create the database object.
    if (conf('database', 'type') eq 'sqlite') {
        my $dbfile  = "$main::run_dir/db/conf.db";
        $conf->{db} = DBI->connect("dbi:SQLite:dbname=$dbfile", '', '');
        $conf->create_tables_maybe;
    }

    # create the pool.
    if (!$main::pool) {
        $pool = $main::pool = pool->new();
    }

    # create the main server object.
    my $server = $utils::v{SERVER};
    if (!$server) {
    
        $server = $pool->new_server(
            source => conf('server', 'id'),
            sid    => conf('server', 'id'),
            name   => conf('server', 'name'),
            desc   => conf('server', 'description'),
            proto  => v('PROTO'),
            ircd   => v('VERSION'),
            time   => v('START'),
            parent => { name => 'self' } # temporary for logging
        );

        # how is this possible?!?!
        $server->{parent}  =
        $utils::v{SERVER} = $server;
        
    }

    # register modes.
    # TODO: delete then re-add.
    add_internal_channel_modes($server);
    add_internal_user_modes($server);
    
    # create API engine manager.
    $API ||= $main::API ||= API->new(
        log_sub  => \&api_log,
        mod_dir  => "$main::run_dir/modules",
        base_dir => "$main::run_dir/lib/API/Base"
    );

    # load API modules.
    # FIXME: is this safe to call multiple times?
    log2('Loading API configuration modules');
    if (my $mods = conf('api', 'modules')) {
        $API->load_module($_, "$_.pm") foreach @$mods;
    }
    log2('Done loading modules');

    # listen.
    create_sockets();

    # ping timer.
    $loop->remove($timer) if $timer;
    $timer = IO::Async::Timer::Periodic->new(
        interval       => 30,
        on_tick        => \&ping_check
    );
    $loop->add($timer);
    $timer->start;

    log2("server initialization complete");

    # auto server connect.
    # FIXME: don't try to connect during reload if already connected.
    # honestly this needs to be moved to an event for after loading the configuration;
    # even if it's a rehash or something it should check for this.
    foreach my $name ($conf->names_of_block('connect')) {
        if (conf(['connect', $name], 'autoconnect')) {
            log2("autoconnecting to $name...");
            server::linkage::connect_server($name)
        }
    }

}

# load or reload a package.
sub load_or_reload {
    my ($name, $min_v, $boot, $set_v, $dont_load) = @_;
    (my $file = "$name.pm") =~ s/::/\//g;
    
    # not loaded; don't load it.
    return if !$INC{$file} && $dont_load;
    
    # it might be loaded with an appropriate version already.
    if ((my $v = $name->VERSION // -1) >= $min_v) {
        log2("$name is loaded and up-to-date ($v)");
        return;
    }
    
    # set package version.
    if ($set_v) {
        no strict 'refs';
        ${"${name}::VERSION"} = $set_v;
    }
    
    # it hasn't been loaded yet at all.
    # use require to load it the first time.
    if ($boot || !$INC{$file}) {
        log2("Loading $name");
        require $file or log2("Very bad error: could not load $name!".($@ || $!));
        return;
    }
    
    # load it.
    log2("Reloading package $name");
    do $file or log2("Very bad error: could not load $name! ".($@ || $!)) and return;
    
    # version check.
    if ((my $v = $name->VERSION // -1) < $min_v) {
        log2("Very bad error: $name is outdated ($min_v required, $v loaded)");
        return;
    }
    
    return 1;
}

# load our package dependencies.
sub load_dependencies {
    my $boot = shift;
    
    # main dependencies.
    load_or_reload('IO::Async::Loop',               0.60, $boot);
    load_or_reload('IO::Async::Stream',             0.60, $boot);
    load_or_reload('IO::Async::Listener',           0.60, $boot);
    load_or_reload('IO::Async::Timer::Periodic',    0.60, $boot);
    load_or_reload('IO::Async::Timer::Countdown',   0.60, $boot);
    load_or_reload('IO::Socket::IP',                0.25, $boot);
    load_or_reload('API',                           2.23, $boot);
    load_or_reload('Evented::Object',               3.90, $boot);
    load_or_reload('Evented::Configuration',        3.30, $boot);
    load_or_reload('Evented::Database',             0.50, $boot);
    
    # juno components.
    my $v = get_version();
    load_or_reload($_, $v, $boot, $v, undef) foreach @always_loaded;
    load_or_reload($_, $v, $boot, $v, 1    ) foreach @maybe_loaded;
    
}

# load configured optional packages.
sub load_optionals {
    my $boot = shift;
    
    # encryption.
    load_or_reload('Digest::SHA', 0, $boot) if conf qw[enabled sha];
    load_or_reload('Digest::MD5', 0, $boot) if conf qw[enabled md5];
    load_or_reload('DBD::SQLite', 0, $boot) if conf('database', 'type') eq 'sqlite';

}

sub create_sockets {

    # TODO: keep track of these, and allow rehashing to change this.
    return if $main::sockets_done;
        # FIXME: do the above and ignore anything that hasn't changed
        # when reloading because this will be called multiple times.
    
    foreach my $addr ($conf->names_of_block('listen')) {
      foreach my $port (@{$conf->get(['listen', $addr], 'port')}) {

        # create the loop listener
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
        ) or fatal("Couldn't listen on [$addr]:$port: $!");

        # add to looped listener
        $listener->listen(handle => $socket);

        log2("Listening on [$addr]:$port");
    } }
    
    $main::sockets_done = 1;
    return 1;
}

# stop the ircd
sub terminate {

    log2("removing all connections for server shutdown");

    # delete all users/servers/other
    foreach my $connection ($main::pool->connections) {
        $connection->done('Shutting down');
    }

    log2("deleting PID file");

    # delete the PID file
    unlink 'etc/juno.pid' or fatal("Can't remove PID file");

    log2("shutting down");
    exit
}

# handle a HUP
sub signalhup { }

sub signalpipe {
}

# handle warning
sub WARNING { log2(shift) }

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
    if (scalar(grep { $_->{ip} eq $ip } $main::pool->connections) >= conf('limit', 'perip')) {
        $stream->close_now;
        return
    }

    # if the global user IP limit has been reached, disconnect
    if (scalar(grep { $_->{ip} eq $ip } $main::pool->users) >= conf('limit', 'globalperip')) {
        $stream->close_now;
        return
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

    $loop->add($stream)
}

# handle incoming data
sub handle_data {
    my ($stream, $buffer) = @_;
    my $connection = $main::pool->lookup_connection($stream) or return;
    while ($$buffer =~ s/^(.*?)\n//) {
        $connection->handle($1);
    }
}

# send out PINGs and check for timeouts
sub ping_check {
    foreach my $connection ($main::pool->connections) {
        if (!$connection->{type}) {
            $connection->done('Registration timeout') if time - $connection->{time} > 30;
            next
        }
        my $type = $connection->isa('user') ? 'user' : 'server';
        if (time - $connection->{last_ping} >= lconf('ping', $type, 'frequency')) {
            $connection->send('PING :'.v('SERVER')->{name}) unless $connection->{ping_in_air};
            $connection->{ping_in_air} = 1
        }
        if (time - $connection->{last_response} >= lconf('ping', $type, 'timeout')) {
            $connection->done('Ping timeout: '.(time - $connection->{last_response}).' seconds')
        }
    }
}

sub boot {

    # load mandatory boot stuff.
    require POSIX;
    require IO::Async;
    require IO::Async::Loop;

    log2("this is $global{NAME} version $global{VERSION}");
    $main::loop = $loop = IO::Async::Loop->new;
    %utils::v = %global;
    undef %global;

    start(1);
    become_daemon();
}

sub loop {
    $loop->loop_forever
}

sub become_daemon {
    # become a daemon
    if (!v('NOFORK')) {
        log2('Becoming a daemon...');

        # since there will be no input or output from here on,
        # open the filehandles to /dev/null
        open STDIN,  '<', '/dev/null' or fatal("Can't read /dev/null: $!");
        open STDOUT, '>', '/dev/null' or fatal("Can't write /dev/null: $!");
        open STDERR, '>', '/dev/null' or fatal("Can't write /dev/null: $!");

        # write the PID file that is used by the start/stop/rehash script.
        open my $pidfh, '>', "$main::run_dir/etc/juno.pid" or fatal("Can't write $main::run_dir/etc/juno.pid");
        $utils::v{PID} = fork;
        say $pidfh v('PID') if v('PID');
        close $pidfh;
        
    }

    exit if v('PID');
    POSIX::setsid();
}

sub begin {

    # set global variables
    # that will eventually be moved to v after startup

    %global = (
        NAME    => 'kedler',      # short name
        LNAME   => 'kedler-ircd', # long name
        VERSION => $VERSION,
        PROTO   => '6.1',
        START   => time,
        NOFORK  => 'NOFORK' ~~ @ARGV,

        # vars that need to be set
        connection_count      => 0,
        max_connection_count  => 0,
        max_global_user_count => 0,
        max_local_user_count  => 0
    )
}

# API engine logging.
sub api_log {
    log2('[API] '.shift());
}

# get version from VERSION file.
# $main::VERSION = version of IRCd when it was started; version of static code
# $ircd::VERSION = version of ircd.pm and all reloadable packages at last reload
# $API::Module::Core::VERSION = version of the core module currently
# v('VERSION') = same as $ircd::VERSION
sub get_version {
    open my $fh, '<', "$::run_dir/VERSION" or log2("Cannot open VERSION: $!") and return;
    my $version = trim(<$fh>);
    close $fh;
    return $version;
}

#####################
### CHANNEL MODES ###
#####################

our %channel_mode_prefixes;

# this just tells the internal server what
# mode is associated with what letter and type by configuration
sub add_internal_channel_modes {
    my $server = shift;
    log2('registering channel status modes');

    # [letter, symbol, name]
    foreach my $name ($ircd::conf->keys_of_block('prefixes')) {
        my $p = conf('prefixes', $name);
        $server->add_cmode($name, $p->[0], 4);
        $channel_mode_prefixes{$p->[2]} = [ $p->[0], $p->[1], $name ]
    }

    log2("registering channel mode letters");

    foreach my $name ($ircd::conf->keys_of_block(['modes', 'channel'])) {
        $server->add_cmode(
            $name,
            (conf(['modes', 'channel'], $name))->[1],
            (conf(['modes', 'channel'], $name))->[0]
        );

    }

    log2("end of internal modes");
}

# get a +modes string
sub channel_mode_string {
    my @modes = sort { $a cmp $b } map { $_->[1] } $ircd::conf->values_of_block('modes', 'channel');
    return join '', @modes
}

##################
### USER MODES ###
##################

# this just tells the internal server what
# mode is associated with what letter as defined by the configuration
sub add_internal_user_modes {
    my $server = shift;
    return unless $ircd::conf->has_block(['modes', 'user']);
    log2("registering user mode letters");
    foreach my $name ($ircd::conf->keys_of_block(['modes', 'user'])) {
        $server->add_umode($name, conf(['modes', 'user'], $name));
    }
    log2("end of user mode letters");
}

# returns a string of every mode
sub user_mode_string {
    my @modes = sort { $a cmp $b } $ircd::conf->values_of_block(['modes', 'user']);
    return join '', @modes
}

1
