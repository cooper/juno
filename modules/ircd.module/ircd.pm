# Copyright (c) 2009-16, Mitchell Cooper
#
# @name:            "ircd"
# @package:         "ircd"
# @description:     "main IRCd module"
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
use Scalar::Util   qw(weaken blessed openhandle);
use POSIX          ();

our ($api, $mod, $me, $pool, $loop, $conf, $boot, $timer, $VERSION);
our (%channel_mode_prefixes, %listeners, %listen_protocol, $disable_warnings);

#############################
### Module initialization ###
################################################################################

sub init {

    # PHASE 1: Load utilities
    #
    #   utils is used everywhere, including this ircd package. we must treat it
    #   specially and load it manually before doing anything else. we also
    #   call ->import() directly because utils is not a formal dependency.
    #

    &setup_utils;           # load utils module

    # PHASE 2: Prepare for boot
    #
    #   here we prepare for boot by reading the VERSION file and setting
    #   $ircd::VERSION. we then set up the global variable map which contains
    #   additional version information and default values for statistics.
    #

    &set_version;           # set $VERSION to VERSION file
    &set_variables;         # set default global variables

    # PHASE 3: Boot
    #
    #   finally, we boot(), which requires the most basic of our dependencies,
    #   daemonizes, and initializes the IO::Async loop. boot() has no effect
    #   during reload; it only applies to the initial startup.
    #

    L('this is '.v('NAME')." version $VERSION");

    &boot;                  # boot if we haven't already

    L('started server at '.scalar(localtime v('START')));

    # PHASE 4: Setup dependencies
    #
    #   after booting, we execute several routines which load dependencies and
    #   set up the configuration.
    #

    &setup_inc;             # add things to @INC
    &load_dependencies;     # load or reload all dependency packages
    &setup_config;          # parse the configuration
    &setup_logging;         # open the logging handle

    # PHASE 5: Server creation
    #
    #   the local server object is used all throughout the program. it is
    #   exported to modules as the package variable $me. for this reason, it
    #   must be available at this point, but we are not quite ready to call
    #   $pool->new_server() because nothing is yet loaded to respond to that.
    #
    #   here we create the local server object manually. we use neither
    #   $pool->new_server() nor server->new(); we instead bless a hash reference
    #   with only the skeleton of the server. the default values below will also
    #   be injected to the existing server during reload if they are undefined.
    #

    &create_server;         # create the server object

    # PHASE 6: API setup
    #
    #   here we set up the Evented API Engine and load the submodules of ircd.
    #   pool is loaded first and then created before creating the rest because
    #   the pool object is exported to all modules besides utils.
    #
    #   we do not load any non-ircd modules yet. those are postponed until
    #   setup_server() and setup_modes() have completed in phase 7 below.
    #

    &setup_api;

    # PHASE 7: Server setup
    #
    #   now that all dependencies are loaded, the configuration is ready, the
    #   server object has been created, and the ircd submodules have been
    #   loaded, we are ready to do the "real setup."
    #
    #   this includes adding mode definitions to the local server, loading
    #   all API modules specified in the configuration, setting up listening
    #   sockets, starting ping and autoconnect timers.
    #

    &setup_server;          # call ->new_server() with skeleton server object
    &setup_modes;           # set up local server modes
    &setup_modules;         # load API modules
    &setup_sockets;         # start listening
    &setup_timer;           # set up ping timer
    &setup_autoconnect;     # connect to servers with autoconnect enabled

    # PHASE 8: Miscellaneous upgrades
    #
    #   this is where code can be placed in case a certain upgrade requires
    #   manual fixes.
    #

    &misc_upgrades;         # miscellaneous upgrade fixes

    L('server initialization complete');
    return 1;
}

# refuse unload unless reloading.
sub void {
    return $mod->{reloading};
}

############################
### PHASE 1: Setup utils ###
################################################################################

# load utils before anything else
sub setup_utils {
    $mod->load_submodule('utils') or return;
    utils->import(qw|conf fatal v trim notice gnotice ref_to_list|);
}

#################################
### PHASE 2: Prepare for boot ###
################################################################################

# set $VERSION to VERSION file
sub set_version {
    $VERSION = get_version();
    $mod->{version} = $VERSION;
}

# get version from VERSION file.
# $::VERSION = version of IRCd when it was started; version of static code
# $ircd::VERSION = version of ircd.pm and all reloadable packages at last reload
# $API::Module::Core::VERSION = version of the core module currently
# v('VERSION') = same as $ircd::VERSION
sub get_version {
    open my $fh, '<', "$::run_dir/VERSION"
        or L("Cannot open VERSION: $!") and return;
    my $version = trim(<$fh>);
    close $fh;
    return $version;
}

# set global variables
sub set_variables {

    # defaults; replace current values.
    my %v_replace = (
        NAME    => 'mihret',        # major version name
        SNAME   => 'juno',          # short ircd name
        LNAME   => 'juno-ircd',     # long ircd name
        VERSION => $VERSION,        # combination of these 3 in VERSION command
        PROTO   => '20.00'
    );
    $v_replace{TNAME} = $v_replace{SNAME}.'-'.$v_replace{NAME};

    # defaults; only set if not existing already.
    my %argv_has = map { $_ => 1 } @ARGV;
    my %v_insert = (
        START   => time,
        NOFORK  => $argv_has{NOFORK},
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

#####################
### PHASE 3: Boot ###
################################################################################

# boot
sub boot {
    return if $::has_booted;
    $boot = 1;
    $::VERSION = $VERSION;
    $::notice_warnings = 1;

    # load mandatory boot stuff.
    require POSIX;
    require IO::Async;
    require IO::Async::Loop;

    $::loop = $loop = IO::Async::Loop->new;

    become_daemon();

    undef $boot;
    $::has_booted = 1;
}

# daemonize
sub become_daemon {

    # open PID file
    open my $pidfh, '>', "$::run_dir/etc/juno.pid"
        or fatal("Can't write $::run_dir/etc/juno.pid");

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
    }

    # don't become a daemon.
    else {
        $::v{PID} = $$;
        say $pidfh $$;
    }

    close $pidfh;

    # exit if daemonization was successful.
    if (v('DAEMON')) {
        exit;
        POSIX::setsid();
    }
}

# loop indefinitely
sub loop {
    $loop->loop_forever;
}

###################################
### PHASE 4: Setup dependencies ###
################################################################################

# inject directories into @INC
sub setup_inc {
    my %inc = map { $_ => 1 } @INC;
    foreach (qw(
        lib/evented-object/lib
        lib/evented-properties/lib
        lib/evented-configuration/lib
        lib/evented-api-engine/lib
        lib/evented-database/lib
    )) { unshift @INC, $_ unless $inc{$_} }
}

# load our package dependencies
sub load_dependencies {
    load_or_reload(@$_) foreach (

        [ 'DBD::SQLite',                   0.00 ],

        [ 'IO::Async::Loop',               0.60 ],
        [ 'IO::Async::Stream',             0.60 ],
        [ 'IO::Async::Listener',           0.60 ],
        [ 'IO::Async::Timer::Periodic',    0.60 ],
        [ 'IO::Async::Timer::Countdown',   0.60 ],

        [ 'IO::Socket::IP',                0.25 ],

        [ 'Evented::Object',               5.59 ],
        [ 'Evented::Object::Collection',   5.59 ],
        [ 'Evented::Object::EventFire',    5.59 ],

        [ 'Evented::API::Engine',          3.99 ],
        [ 'Evented::API::Module',          3.99 ],
        [ 'Evented::API::Hax',             3.99 ],

        [ 'Evented::Configuration',        3.96 ],

        [ 'Evented::Database',             1.12 ],
        [ 'Evented::Database::Rows',       1.12 ],
        [ 'Evented::Database::Table',      1.12 ],

        [ 'Scalar::Util',                  1.00 ],
        [ 'List::Util',                    1.00 ]

    );
}

# load configuration
sub setup_config {
    require DBI;
    my $dbfile = "$::run_dir/db/conf.db";
    my $dbh    = DBI->connect("dbi:SQLite:dbname=$dbfile", '', '');

    # set up the configuration/database.
    $conf = Evented::Database->new(
        db       => $dbh,
        conffile => "$::run_dir/etc/default.conf"
    );

    my $new = !$conf->table('configuration')->exists;
    $conf->create_tables_maybe;

    # parse the default configuration.
    unless ($new) {
        $conf->{conffile} = "$::run_dir/etc/default.conf";
        $conf->parse_config or return;
    }

    # parse the actual configuration.
    $conf->{conffile} = "$::run_dir/etc/ircd.conf";
    $conf->parse_config or return;

    # if upgrading, parse default configuration after.
    if ($new) {
        $conf->{conffile} = "$::run_dir/etc/default.conf";
        $conf->parse_config or return;
        $conf->{conffile} = "$::run_dir/etc/ircd.conf";
    }

    # developer mode?
    $api->{developer} = conf('server', 'developer');

    # casemapping - only set ONCE.
    $::casemapping ||= conf('server', 'casemapping');

    # remove expired RESVs.
    $pool->expire_resvs() if $pool;

    return 1;
}

# setup logging handle
sub setup_logging {

    # close the old filehandle.
    close $::log_fh if $::log_fh && openhandle($::log_fh);
    my $logfile = conf('file', 'log');
    return if !length $logfile;

    # open the filehandle.
    open $::log_fh, '>>', $logfile or return;
    $::log_fh->autoflush(1);

    # register the callback.
    $api->delete_callback('log', 'log.to.file');
    $api->on(log => sub {
        my (undef, $line) = @_;

        # write to file maybe.
        if ($::log_fh && openhandle($::log_fh)) {
            print $::log_fh "$line\n";
        }

    }, name => 'log.to.file');
}

################################
### PHASE 5: Server creation ###
################################################################################

# precreate server object
sub create_server {
    $me = $::v{SERVER} ||= bless {}, 'server';
    $me->{ $_->[0] } //= $_->[1] foreach (
        [ umodes   => {} ],
        [ cmodes   => {} ],
        [ users    => [] ],
        [ children => [] ]
    );
    $me->{parent} = $me;
}

##########################
### PHASE 6: API setup ###
################################################################################

# setup API Engine
sub setup_api {

    # exported variables in modules.
    # note that these will not be available in the utils module.
    $api->on('module.set_variables' => sub {
        my ($event, $pkg) = @_;
        my $obj = $event->object;
        Evented::API::Hax::set_symbol($pkg, {
            '$me'   => $me,
            '$pool' => $pool,
            '$conf' => $conf,
            '*L'    => sub { _L($obj, [caller 1], @_) }
        });
    });

    # load submodules. create the pool.
    $mod->load_submodule('pool') or return;
    $ircd::pool = $::pool ||= pool->new; # must be ircd::pool; don't change.
    $mod->load_submodule($_) or return
        foreach qw(message user server channel connection);

}

#############################
### PHASE 7: Server setup ###
################################################################################

# setup precreated server object
sub setup_server {
    # consider: new values are NOT inserted after reloading.
    $pool->new_server($me,
        source => conf('server', 'id'),
        sid    => conf('server', 'id'),
        name   => conf('server', 'name'),
        desc   => conf('server', 'description'),
        proto  => v('PROTO'),
        ircd   => v('VERSION'),
        time   => v('START')
    ) if not exists $me->{source};
}

# setup user and channel modes
sub setup_modes {
    &add_internal_channel_modes;
    &add_internal_user_modes;
}

# load API modules
sub setup_modules {
    return if $mod->{loading};

    # the old way: modules key.
    my %mods = $conf->hash_of_block('api');
    my @modules = ref_to_list(delete $mods{modules});

    # the new way: other keys.
    foreach my $mod_name (keys %mods) {
        next unless $mods{$mod_name};
        push @modules, $mod_name;
    }

    L('Loading API configuration modules');
    $api->load_modules(@modules);
    L('Done loading modules');
}

# setup listening sockets
sub setup_sockets {

    # start listeners.
    # ex:
    #
    # [ listen: 0.0.0.0 ]
    #
    # port     = [6667..6669]
    # sslport  = [6697, 7000]
    # jelpport = [7001]
    #
    ADDR: foreach my $addr ($conf->names_of_block('listen')) {
        my %listen = $conf->hash_of_block(['listen', $addr]);

        KEY: foreach my $key (keys %listen) {
            $key =~ m/^(.*?)(ssl)?port$/ or next;
            my ($prefix, $is_ssl) = ($1, $2);
            my @ports  = ref_to_list($listen{$key});

            # SSL?
            if ($is_ssl) {
                load_or_reload('IO::Async::SSL',       0.14) or next;
                load_or_reload('IO::Async::SSLStream', 0.14) or next;
            }

             # listen.
            foreach (@ports) {
                listen_addr_port($addr, $_, $is_ssl);
                $listen_protocol{$_} = $prefix if length $prefix;
            }

        }
    }

    # reconfigure existing notifiers.
    foreach ($loop->notifiers) {
        configure_listener($_) if $_->isa('IO::Async::Listener');
        configure_stream($_)   if $_->isa('IO::Async::Stream');

        # dead timer.
        if ($_->isa('IO::Async::Timer::Periodic')) {
            next unless $timer->loop;
            next if $timer->parent;
            next if $timer->is_running;
            $loop->remove($timer);
        }
    }

}

# setup ping timer
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

# setup autoconnect timers
sub setup_autoconnect {

    # auto server connect.
    # honestly this needs to be moved to an event for after loading the configuration;
    # even if it's a rehash or something it should check for this.
    foreach my $name ($conf->names_of_block('connect')) {
        next unless conf(['connect', $name], 'autoconnect');
        server::linkage::connect_server($name);
    }

}

#######################################
### PHASE 8: Miscellaneous upgrades ###
################################################################################

# miscellaneous upgrade fixes.
# TODO: I want each instance to be able to track which upgrades have been done
# already to improve the efficiency of this.
sub misc_upgrades {

    # inject missing server information.
    foreach my $server ($pool->servers) {

        # servers with connections need a link_type.
        # all connected servers without link_type are JELP.
        next unless $server->{conn};
        $server->{link_type} //= 'jelp';
    }

    # inject missing local user information.
    foreach my $user ($pool->local_users) {
        next unless $user->{conn};

        # if the conn exists but is not an object, it's a ghost.
        if (!blessed $user->{conn}) {
            delete $user->{conn};
            $user->quit('Ghost');
            next;
        }

        # local users need a last_command time.
        $user->{conn}{last_command} ||= time;
    }

    # inject missing user information.
    foreach my $user ($pool->all_users) {

        # nickTS otherwise equals connectTS.
        $user->{nick_time} //= $user->{time} // time();

        # check for ghosts on nonexistent servers.
        next if !$user->{server};
        next if $pool->lookup_server($user->{server}{sid});
        if ($user->conn) { $user->conn->done('Ghost')   }
                    else { $user->quit('Ghost')         }

        # account name cannot be *
        $user->do_logout() if $user->{account} && $user->{account}{name} eq '*';

    }

}

##########################
### PACKAGE MANAGEMENT ###
##########################

# load or reload a package.
sub load_or_reload {
    my ($name, $min_v) = @_;
    (my $file = "$name.pm") =~ s/::/\//g;

    # it might be loaded with an appropriate version already.
    no warnings 'numeric';
    if ((my $v = $name->VERSION // -1) >= $min_v) {
        L("$name is loaded and up-to-date ($v)");
        return 1;
    }

    # it hasn't been loaded yet at all.
    # use require to load it the first time.
    if (!is_loaded($name) && !$name->VERSION) {
        L("Loading $name");
        require $file or L("Very bad error: could not load $name!".($@ || $!)) and return;
        return 1;
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

#################
### LISTENING ###
#################

# this is called for both new and
# existing listeners, even during reload.
my @listener_opts = (
    on_accept    => sub { &handle_connect },
    #on_error     => sub { &handle_listen_error }
    # see below hack
);
sub configure_listener {
    my $listener = shift;

    # if there is no read handle, this is dead.
    if (!$listener->loop && !$listener->read_handle && !$listener->parent) {
        $loop->remove($listener);
    }

    # HACK: this is the only way I can figure out how to fix uncaught errors
    # invoked upon the listener. 'on_error' is not accepted in ->configure().
    # it says: Cannot pass though configuration keys to underlying Handle -
    # on_error at /Library/Perl/5.18/IO/Async/Listener.pm line 246.
    # this is how I "fixed" issue #128.
    #
    # note that this will catch any error which is invoked on the listener.
    # in the case of the SSL issue (#128), this will be called several times,
    # maybe every time someone tries to connect via SSL.
    #
    $listener->{IO_Async_Notifier__on_error} = sub { &handle_listen_error };

    eval { $listener->configure(@listener_opts); 1 }
    or L("Configuring listener failed!");
}

# this is called for both new and
# existing streams, even during reload.
our @stream_opts = (
    read_all       => 0,
    read_len       => POSIX::BUFSIZ(),
    on_read        => sub { &handle_data },
    on_read_eof    => sub { _conn_close('Connection closed',   @_) },
    on_write_eof   => sub { _conn_close('Connection closed',   @_) },
    on_read_error  => sub { _conn_close('Read error: ' .$_[1], @_) },
    on_write_error => sub { _conn_close('Write error: '.$_[1], @_) }
);
sub configure_stream {
    my $stream = shift;

    # if there is no read handle, this is dead.
    if ($stream->loop && !$stream->read_handle && !$stream->parent) {
        $loop->remove($stream);
    }

    eval { $stream->configure(@stream_opts); 1 }
    or L("Configure stream failed!");
}

# listen on an address at a port
sub listen_addr_port {
    my ($addr, $port, $ssl) = @_;
    my $ipv6 = utils::looks_like_ipv6($addr);
    my ($p_addr, $p_port) = ($ipv6 ? "[$addr]" : $addr, $ssl ? "+$port" : $port);
    my $l_key = lc "$p_addr:$p_port";

    # use SSL.
    my ($method, %sslopts) = 'listen';
    if ($ssl) {
        $method  = 'SSL_listen';

        # ensure the key and certificate exist.
        my $ssl_cert = $::run_dir.q(/).conf('ssl', 'cert');
        my $ssl_key  = $::run_dir.q(/).conf('ssl', 'key');
        if (!-f $ssl_cert || !-f $ssl_key) {
            L("SSL key or certificate missing! Cannnot listen on $l_key");
            return;
        }

        # pass SSL options to ->SSL_listen().
        %sslopts = (
            SSL_cert_file => $ssl_cert,
            SSL_key_file  => $ssl_key,
            SSL_server    => 1
            #on_ssl_error  => sub { L("SSL error: @_") }
            # probably not needed when using a future
        );

    }

    # create a listener object.
    # as of IO::Async 0.62, ->listen on its own does not work with
    # handle_class or handle_constructor and on_accept.
    my $listener = IO::Async::Listener->new(
        handle_class => $ssl ? 'IO::Async::SSLStream' : 'IO::Async::Stream',
        @listener_opts
    );
    $listener->{l_key} = $l_key;
    $loop->add($listener);

    # call ->listen() or ->SSL_listen() on the loop.
    my $f = eval { $listeners{$l_key}{future} = $loop->$method(
        addr => {
            family   => $ipv6 ? 'inet6' : 'inet',
            socktype => 'stream',
            port     => $port,
            ip       => $addr
        },
        listener => $listener,
        %sslopts
    ) };

    # something happened.
    if (!$f) {
        L("->$method() for $l_key failed!");
        return;
    }

    # when the listener is ready.
    $f->on_ready(sub {
        my $f = shift;
        delete $listeners{$l_key}{future};

        # failed.
        if (my $err = $f->failure) {
            handle_listen_error(undef, $err, $l_key);
            return;
        }

        # store the listener.
        my $listener = $listeners{$l_key}{listener} = $f->get;
        configure_listener($listener);
        L("Listening on $l_key");

    });

    return 1;
}

# handle any uncaught exception in listening
sub handle_listen_error {
    my ($listener, $err, $l_key) = @_;
    $l_key = $listener ? $listener->{l_key} : $l_key || '(unknown)';
    L("Listen on $l_key failed: $err");
}

# handles a connection error or EOF
sub _conn_close {
    my ($err, $stream) = @_;
    my $conn = $pool->lookup_connection($stream);
    if ($conn) {
        $conn->done($err);
    }
    else {
        warn 'Closing a stream with no associated connection';
    }
    $stream->close_now;
}

#####################
### INCOMING DATA ###
#####################

# handle connecting user or server
sub handle_connect {
    my ($listener, $stream) = @_;
    return unless $stream->{write_handle};

    # create connection object.
    my $conn = $pool->new_connection(stream => $stream);
    weaken( $conn->{listener} = $listener );

    # set up stream.
    configure_stream($stream);
    $loop->add($stream);

    # if the connection limit has been reached, disconnect immediately.
    if (scalar $pool->connections > conf('limit', 'connection')) {
        $conn->done('Total connection limit exceeded');
        $stream->close_now; # don't even wait.
        return;
    }

    # if the connection IP limit has been reached, disconnect.
    my $ip = $conn->{ip};
    if (scalar(grep { $_->{ip} eq $ip } $pool->connections)
      > conf('limit', 'perip')) {
        $conn->done('Connections per IP limit exceeded');
        return;
    }

    # if the global user IP limit has been reached, disconnect.
    if (scalar(grep { $_->{ip} eq $ip } $pool->actual_users)
      > conf('limit', 'globalperip')) {
        $conn->done('Global connections per IP limit exceeded');
        return;
    }

    # Allow for modules to prevent a user from registering
    my $event = $conn->fire('can_continue');
    $conn->done($event->stop) if $event->stopper;

    return 1;
}

# handle incoming data
sub handle_data {
    my ($stream, $buffer) = @_;
    my $connection = $pool->lookup_connection($stream) or return;
    my $is_server  = $connection->server;

    # fetch the values at which the limit was exceeded.
    my $overflow_1line   =
        (my $max_in_line = conf('limit', 'bytes_line')  // 2048) + 1;
    my $overflow_lines   =
        (my $max_lines   = conf('limit', 'lines_sec')   // 30  ) + 1;

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

##############
### TIMERS ###
##############

# send out PINGs and check for timeouts
sub ping_check {
    foreach my $connection ($pool->connections) {

    # the socket is dead.
    if (!$connection->stream || !$connection->sock) {
        $connection->done('Dead socket');
        next;
    }

    # not yet registered.
    # if they have been connected for 30 secs without registering, drop.
    if (!$connection->{type}) {
        $connection->done('Registration timeout')
            if time - $connection->{time} > 30;
        next;
    }

    my $type = $connection->user ? 'users' : 'servers';
    my $since_last = time - $connection->{last_response};

    # this connection is OK - for now.
    if ($since_last < conf($type, 'ping_freq')) {

        # if it's a server, we might need to produce a warning.
        if ($type eq 'servers') {
            next if $connection->{warned_ping}++;
            my $needed_to_warn = conf($type, 'ping_warn') || 'inf';
            notice(server_not_responding =>
                $connection->server->notice_info,
                $since_last
            ) if $since_last >= $needed_to_warn;
        }

        next;
    }

    # send a ping if we haven't already.
    if (!$connection->{ping_in_air}) {
        $connection->send("PING :$$me{name}");
        $connection->{ping_in_air}++;
    }

    # ping timeout.
    $connection->done("Ping timeout: $since_last seconds")
        if $since_last >= conf($type, 'ping_timeout');

} }

#############
### MODES ###
#############

# this just tells the internal server what
# mode is associated with what letter and type by configuration
sub add_internal_channel_modes {
    L('registering channel status modes');

    # clear the old modes
    $me->{cmodes} = {};
    %channel_mode_prefixes = ();

    # FIXME: this is repulsive
    # store prefixes as [letter, symbol, name, set_weight]
    foreach my $name ($conf->keys_of_block('prefixes')) {
        my $p = conf('prefixes', $name) or next;
        next if !ref $p || ref $p ne 'ARRAY' || @$p < 3;
        $me->add_cmode($name, $p->[0], 4);
        $channel_mode_prefixes{ $p->[2] } = [
            $p->[0],    # (0) mode letter
            $p->[1],    # (1) nick prefix symbol
            $name,      # (2) mode name
            $p->[3]     # (3) weight needed to set/unset this mode
        ];
    }

    # add the new non-status modes
    L('registering channel mode letters');
    foreach my $name ($conf->keys_of_block(['modes', 'channel'])) {
        $me->add_cmode(
            $name,
            (conf(['modes', 'channel'], $name))->[1],
            (conf(['modes', 'channel'], $name))->[0]
        );
    }
}

# this just tells the internal server what
# mode is associated with what letter as defined by the configuration
sub add_internal_user_modes {
    L('registering user mode letters');

    # clear the previous ones
    $me->{umodes} = {};
    return unless $conf->has_block(['modes', 'user']);

    # add the new ones
    foreach my $name ($conf->keys_of_block(['modes', 'user'])) {
        $me->add_umode($name, conf(['modes', 'user'], $name));
    }
}

####################
### IRCD ACTIONS ###
####################

# stop the ircd
sub terminate {

    # delete all users/servers/other
    L('disposing of all connections');
    foreach my $connection ($pool->connections) {
        $connection->done('Shutting down');
    }

    # delete the PID file
    L('deleting PID file');
    unlink 'etc/juno.pid' or fatal("Can't remove PID file");

    L('shutting down');
    exit;
}

# rehash the server
sub rehash {
    L('rehashing');
    $pool->fire('rehash_before');

    # if a user is passed, use him for the notices.
    my $user_maybe = shift;
    my @arg = $user_maybe
        if blessed $user_maybe && $user_maybe->isa('user');

    # rehash
    if (!eval { &setup_config }) {
        $pool->fire('rehash_fail');
        $pool->fire('rehash_after');
        gnotice(@arg, rehash_fail => $@ || $!);
        return;
    }

    # set up other stuff
    %server::protocol::ircd_support = ();
    setup_sockets();
    add_internal_user_modes();
    add_internal_channel_modes();

    $pool->fire('rehash_after');
    gnotice(@arg, 'rehash_success');
    return 1;
}

###############
### SIGNALS ###
###############

# handle a HUP
sub signalhup {
    notice(rehash => 'HUP signal', 'someone', 'localhost');
    rehash();
}

# handle a PIPE
sub signalpipe { }

# handle a warning
sub WARNING {
    my $warn = shift;
    return if $disable_warnings;
    chomp $warn;
    ircd->can('notice') && $::notice_warnings ?
    notice(perl_warning => $warn)             :
    L($warn);
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

    # use a different object.
    if (blessed $line && $line->isa('Evented::API::Module')) {
        $obj  = $line;
        $line = shift;
    }

    # determine the source of the message.
   (my $sub  = shift // $caller->[3]) =~ s/(.+)::(.+)/$2/;
    my $info = $sub && $sub ne '(eval)' ? "$sub()" : $caller->[0];
    $line = "$info: $line";

    # this will call the log_sub which is an anonymous subroutine in
    # the main package which literally just calls say() and nothing else.
    return unless $obj->can('_log');
    $obj->_log($line);

}

$mod
