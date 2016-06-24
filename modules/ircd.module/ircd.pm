# Copyright (c) 2009-14, Mitchell Cooper
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
use Scalar::Util   qw(weaken blessed);

our ($api, $mod, $me, $pool, $loop, $conf, $boot, $timer, $VERSION);
our (%channel_mode_prefixes, %listeners, %listen_protocol);

######################
### INITIALIZATION ###
######################

sub init {

    # load utils immediately.
    $mod->load_submodule('utils') or return;
    utils->import(qw|conf fatal v trim notice gnotice ref_to_list|);
    $VERSION = get_version();
    $mod->{version} = $VERSION;

    &set_variables;         # set default global variables.
    &boot;                  # boot if we haven't already.

    L('Started server at '.scalar(localtime v('START')));

    &setup_inc;             # add things to @INC.
    &load_dependencies;     # load or reload all dependency packages.
    &setup_config;          # parse the configuration.
    &load_optionals;        # load or reload optional packages.

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
    $me->{parent} = $me;

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
    # utils pool user(::mine) server(::mine,::linkage) channel(::mine) connection
    $mod->load_submodule('pool') or return;
    $ircd::pool = $::pool ||= pool->new; # must be ircd::pool; don't change.
    $mod->load_submodule($_) or return foreach qw(message user server channel connection);

    # consider: new values are NOT inserted after reloading.
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
    &misc_upgrades;         # miscellaneous upgrade fixes

    L("server initialization complete");
    return 1;
}

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

sub setup_modules {
    return if $mod->{loading};

    # the old way: modules key.
    my @modules = ref_to_list(conf('api', 'modules'));

    # the new way: other keys.
    my %mods = $conf->hash_of_block('api');
    foreach my $mod_name (keys %mods) {
        next if $mod_name eq 'modules';
        next unless $mods{$mod_name};
        push @modules, $mod_name;
    }

    L('Loading API configuration modules');
    $api->load_modules(@modules);
    L('Done loading modules');
}

sub setup_config {
    require DBI;
    my $dbfile = "$::run_dir/db/conf.db";
    my $dbh    = DBI->connect("dbi:SQLite:dbname=$dbfile", '', '');

    # set up the configuration/database.
    $conf ||= Evented::Database->new(
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

sub setup_autoconnect {

    # auto server connect.
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
        NAME    => 'yiria',         # major version name
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

# this is called for both new and
# existing listeners, even during reload.
sub configure_listener {
    my $listener = shift;

    # if there is no read handle, this is dead.
    if ($listener->loop && !$listener->read_handle && !$listener->parent) {
        $loop->remove($listener);
    }

    $listener->{on_accept} = sub { &handle_connect };
    $listener->{ssl} = $listener->{handle_class} eq 'IO::Async::SSLStream';
}

# this is called for both new and
# existing streams,  even during reload.
sub configure_stream {
    my $stream = shift;

    # if there is no read handle, this is dead.
    if ($stream->loop && !$stream->read_handle && !$stream->parent) {
        $loop->remove($stream);
    }

    $stream->{on_read} = sub { &handle_data };
}

sub listen_addr_port {
    my ($addr, $port, $ssl) = @_;
    my $ipv6 = $addr =~ m/:/;
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
            SSL_server    => 1,
            on_ssl_error  => sub { L("SSL error: @_") }
        );

    }

    # create a listener object.
    # as of IO::Async 0.62, ->listen on its own does not work with
    # handle_class or handle_constructor and on_accept.
    my $listener = IO::Async::Listener->new(
        handle_class => $ssl ? 'IO::Async::SSLStream' : 'IO::Async::Stream',
        on_accept    => sub { &handle_connect },
    );
    $loop->add($listener);

    # call ->listen() or ->SSL_listen() on the loop.
    my $f = $listeners{$l_key}{future} = $loop->$method(
        addr => {
            family   => $ipv6 ? 'inet6' : 'inet',
            socktype => 'stream',
            port     => $port,
            ip       => $addr
        },
        listener => $listener,
        %sslopts
    );

    # when the listener is ready.
    $f->on_ready(sub {
        my $f = shift;
        delete $listeners{$l_key}{future};

        # failed.
        if (my $err = $f->failure) {
            L("Listen on $l_key failed: $err");
            return;
        }

        # store the listener.
        my $listener = $listeners{$l_key}{listener} = $f->get;
        configure_listener($listener);
        L("Listening on $l_key");

    });

    return 1;
}

# refuse unload unless reloading.
sub void {
    return $mod->{reloading};
}

# miscellaneous upgrade fixes.
# TODO: I want each instance to be able to track which upgrades have been done
# already to improve the efficiency of this.
sub misc_upgrades {

    # all connected servers without link_type are JELP.
    foreach my $server ($pool->servers) {
        next unless $server->{conn};
        $server->{link_type} //= 'jelp';
    }

    # local users need a last_command time.
    foreach my $user ($pool->local_users) {
        next unless $user->{conn};
        $user->{conn}{last_command} ||= time;
    }

    foreach my $user ($pool->all_users) {

        # nickTS otherwise equals connectTS.
        $user->{nick_time} //= $user->{time};

        # check for ghosts on nonexistent servers.
        next if !$user->{server};
        next if $pool->lookup_server($user->{server}{sid});
        if ($user->conn) { $user->conn->done('Ghost')   }
                    else { $user->quit('Ghost')         }
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

# load our package dependencies.
sub load_dependencies {

    # main dependencies.
    load_or_reload(@$_) foreach (

        [ 'IO::Async::Loop',               0.60 ],
        [ 'IO::Async::Stream',             0.60 ],
        [ 'IO::Async::Listener',           0.60 ],
        [ 'IO::Async::Timer::Periodic',    0.60 ],
        [ 'IO::Async::Timer::Countdown',   0.60 ],

        [ 'IO::Socket::IP',                0.25 ],

        [ 'Evented::Object',               5.50 ],
        [ 'Evented::Object::Collection',   5.50 ],
        [ 'Evented::Object::EventFire',    5.50 ],

        [ 'Evented::API::Engine',          3.94 ],
        [ 'Evented::API::Module',          3.94 ],
        [ 'Evented::API::Hax',             3.94 ],

        [ 'Evented::Configuration',        3.90 ],

        [ 'Evented::Database',             1.09 ],
        [ 'Evented::Database::Rows',       1.09 ],
        [ 'Evented::Database::Table',      1.09 ],

        [ 'Scalar::Util',                  1.00 ],
        [ 'List::Util',                    1.00 ]

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
sub signalhup {
    notice(rehash => 'HUP signal', 'someone', 'localhost');
    rehash();
}

# handle a PIPE
sub signalpipe { }

# handle warning
sub WARNING {
    ircd->can('notice') && $::notice_warnings ?
    notice(perl_warning => shift)             :
    L(shift);
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
    $stream->configure(
        read_all       => 0,
        read_len       => POSIX::BUFSIZ(),
        on_read        => sub { &handle_data },
        on_read_eof    => sub { $stream->close_now; $conn->done('Connection closed')    },
        on_write_eof   => sub { $stream->close_now; $conn->done('Connection closed')    },
        on_read_error  => sub { $stream->close_now; $conn->done('Read error: ' .$_[1])  },
        on_write_error => sub { $stream->close_now; $conn->done('Write error: '.$_[1])  }
    );

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
    if (scalar(grep { $_->{ip} eq $ip } $pool->connections) > conf('limit', 'perip')) {
        $conn->done('Connections per IP limit exceeded');
        return;
    }

    # if the global user IP limit has been reached, disconnect.
    if (scalar(grep { $_->{ip} eq $ip } $pool->actual_users) > conf('limit', 'globalperip')) {
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

        my $type = $connection->user ? 'user' : 'server';
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

    # rehash
    eval { &setup_config } or
        notice(rehash_fail => $@ || $!)
        and return;

    # set up other stuff
    setup_sockets();
    add_internal_user_modes();
    add_internal_channel_modes();

    notice('rehash_success');
    return 1;
}

sub boot {
    return if $::has_booted;
    $boot = 1;
    $::VERSION = $VERSION;
    $::notice_warnings = 1;

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

   (my $sub  = shift // $caller->[3]) =~ s/(.+)::(.+)/$2/;
    my $info = $sub && $sub ne '(eval)' ? "$sub()" : $caller->[0];
    return unless $obj->can('_log');
    $obj->_log("$info: $line");
}

$mod
