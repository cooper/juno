# Copyright (c) 2010-12, Mitchell Cooper
package ircd;

use warnings;
use strict;
use feature qw(switch say);

use utils qw(conf lconf log2 fatal v set);

our ($VERSION, $API, $conf, %global) = '6.21';

sub start {

    log2('Started server at '.scalar(localtime v('START')));

    # add these to @INC if they are not there already.
    my @add_inc = (
        "$::run_dir/lib/api-engine",
        "$::run_dir/lib/evented-object/lib",
        "$::run_dir/lib/evented-configuration/lib",
        "$::run_dir/lib/evented-database"
    ); foreach (@add_inc) { unshift @INC, $_ unless $_ ~~ @INC }

    # IO::Async and friends
    require IO::Async::Listener;
    require IO::Async::Timer::Periodic;
    require IO::Socket::IP;

    # juno components
    require connection;
    require server;
    require user;
    require channel;
    
    # API Engine
    require API;
    
    # Evented::Object and friends
    require Evented::Object;
    require Evented::Configuration;
    require Evented::Database;
    
    # set up the configuration/database.
    # TEMPORARILY use no database until we read [database] block.
    $conf = $main::conf = Evented::Database->new(
        db       => undef,
        conffile => "$main::run_dir/etc/ircd.conf"
    );
    
    # parse the configuration.
    $conf->parse_config or die "can't parse configuration.\n";

    # create the main server object
    my $server = $utils::v{SERVER};
    if (!$server) {
    
        $server = server->new({
            source => conf('server', 'id'),
            sid    => conf('server', 'id'),
            name   => conf('server', 'name'),
            desc   => conf('server', 'description'),
            proto  => v('PROTO'),
            ircd   => v('VERSION'),
            time   => v('START'),
            parent => { name => 'self' } # temporary for logging
        });

        # how is this possible?!?!
        $server->{parent}  =
        $utils::v{SERVER} = $server;
        
    }

    # register modes
    $server->user::modes::add_internal_modes();
    $server->channel::modes::add_internal_modes();

    # load required modules
    load_requirements();

    # create the evented object.
    $main::eo = Evented::Object->new;

    # create API engine manager.
    $API = $main::API = API->new(
        log_sub  => \&api_log,
        mod_dir  => "$main::run_dir/modules",
        base_dir => "$main::run_dir/lib/API/Base"
    );

    # load API modules
    log2('Loading API configuration modules');
    if (my $mods = conf('api', 'modules')) {
        $API->load_module($_, "$_.pm") foreach @$mods;
    }
    log2('Done loading modules');

    # listen
    create_sockets();

    # ping timer
    my $freq = lconf('ping', 'user', 'frequency');
    my $timer = IO::Async::Timer::Periodic->new( 
        interval       => 30,
        on_tick        => \&ping_check
    );
    $main::loop->add($timer);
    $timer->start;

    log2("server initialization complete");

    # auto server connect
    foreach my $name ($conf->names_of_block('connect')) {
        if (conf(['connect', $name], 'autoconnect')) {
            log2("autoconnecting to $name...");
            server::linkage::connect_server($name)
        }
    }

}

sub load_requirements {

    if (defined( my $pkg = conf qw[class normal_package] )) {
        log2('Loading '.$pkg);
        $pkg =~ s/::/\//g;
        require "$pkg.pm"
    }

    if (conf qw[enabled sha]) {
        log2('Loading Digest::SHA');
        require Digest::SHA
    }

    if (conf qw[enabled md5]) {
        log2('Loading Digest::MD5');
        require Digest::MD5
    }

    #if (conf qw[enabled resolve]) {
    #    log2('Loading res, Net::IP, Net::DNS');
    #    require res
    #}

}

sub create_sockets {
    foreach my $addr ($conf->names_of_block('listen')) {
      foreach my $port (@{$conf->get(['listen', $addr], 'port')}) {

        # create the loop listener
        my $listener = IO::Async::Listener->new(on_stream => \&handle_connect);
        $main::loop->add($listener);

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
    return 1
}

# stop the ircd
sub terminate {

    log2("removing all connections for server shutdown");

    # delete all users/servers/other
    foreach my $connection (values %connection::connection) {
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
    if (scalar(grep { $_->{ip} eq $ip } values %connection::connection) >= conf('limit', 'perip')) {
        $stream->close_now;
        return
    }

    # if the global user IP limit has been reached, disconnect
    if (scalar(grep { $_->{ip} eq $ip } values %user::user) >= conf('limit', 'globalperip')) {
        $stream->close_now;
        return
    }

    # create connection object
    my $conn = connection->new($stream);

    $stream->configure(
        read_all       => 0,
        read_len       => POSIX::BUFSIZ(),
        on_read        => \&handle_data,
        on_read_eof    => sub { $conn->done('Connection closed'); $stream->close_now   },
        on_write_eof   => sub { $conn->done('Connection closed'); $stream->close_now   },
        on_read_error  => sub { $conn->done('Read error: ' .$_[1]); $stream->close_now },
        on_write_error => sub { $conn->done('Write error: '.$_[1]); $stream->close_now }
    );

    $main::loop->add($stream)
}

# handle incoming data
sub handle_data {
    my ($stream, $buffer) = @_;
    my $connection = connection::lookup_by_stream($stream);
    while ($$buffer =~ s/^(.*?)\n//) {
        $connection->handle($1)
    }
}

# send out PINGs and check for timeouts
sub ping_check {
    foreach my $connection (values %connection::connection) {
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
    $main::loop = IO::Async::Loop->new;
    %utils::v = %global;
    undef %global;

    start();
    become_daemon();
}

sub loop {
    $main::loop->loop_forever
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
        NAME    => 'kedler-ircd',  # long name
        SNAME   => 'kedler',       # short name
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

1
