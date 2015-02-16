# Copyright (c) 2014, Mitchell Cooper
#
# @name:            "Git"
# @package:         "M::Git"
# @description:     "git repository management"
#
# @depends.modules: ['Base::UserCommands', 'JELP::Base']
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Git;

use warnings;
use strict;
use 5.010;

use IO::Async::Process;
use utils qw(col gnotice);

our ($api, $mod, $pool, $me);

our %user_commands = (update => {
    desc   => 'update the IRCd git repository',
    params => '-oper(git) any(opt)',
    code   => \&ucmd_update,
    fntsy  => 1
});

our %oper_notices = (
    update         => '%s (%s@%s) is updating %s',
    update_fail    => 'update to %s by %s (%s@%s) failed',
    update_success => '%s updated successfully by %s (%s@%s)'
);

sub init {
    
    # allow UPDATE to work remotely.
    $mod->register_global_command(name => 'update') or return;
    
    return 1;
}

sub ucmd_update {
    #my ($user, $event
    my ($user, $event, $server_mask_maybe) = @_;
    
    
    if (length $server_mask_maybe) {
        my @servers = $pool->lookup_server_mask($server_mask_maybe);
        
        # no priv.
        if (!$user->has_flag('gupdate')) {
            $user->numeric(ERR_NOPRIVILEGES => 'gupdate');
            return;
        }
        
        # no matches.
        if (!@servers) {
            $user->numeric(ERR_NOSUCHSERVER => $server_mask_maybe);
            return;
        }
        
        # wow there are matches.
        my %done;
        foreach my $serv (@servers) {
            
            # already did this one!
            next if $done{$serv};
            $done{$serv} = 1;
            
            # if it's $me, skip.
            # if there is no connection (whether direct or not),
            # uh, I don't know what to do at this point!
            next if $serv->is_local;
            next unless $serv->{location};
            
            # pass it on :)
            $user->server_notice(update => "Sending update command to $$serv{name}")
                if $user->is_local;
            $serv->{location}->fire_command_data(update => $user, "UPDATE $$serv{name}");
            
        }
        
        # if $me is done, just keep going.
        return 1 unless $done{$me};
        
    }
    
    $user->server_notice(update => "Updating $$me{name}");
    gnotice(update => $user->notice_info, $me->name);
    
    # git pull
    command([ 'git', 'pull' ], undef,
    
        # success
        sub {
            git_pull_succeeded($user, $event);
        },
        
        # error
        sub {
            my @lines = split /\n/, shift;
            $user->server_notice(update => "$$me{name} pull failed: $_") foreach @lines;
            gnotice(update_fail => $me->name, $user->notice_info);
        }
    );
}

sub git_pull_succeeded {
    my ($user, $event) = @_;
    
    # git submodule update --init
    command(['git', 'submodule', 'update', '--init'], undef,
    
        # success
        sub {
            git_submodule_succeeded($user, $event);
        },
        
        # error
        sub {
            my @lines = split /\n/, shift;
            $user->server_notice(update => "$$me{name} submodule failed: $_") foreach @lines;
            gnotice(update_fail => $me->name, $user->notice_info);
        }
    );
}

sub git_submodule_succeeded {
    my ($user, $event) = @_;
    $user->server_notice(update => "$$me{name} updated successfully");
    gnotice(update_success => $me->name, $user->notice_info);
}

sub command {
    my ($command, $stdout_cb, $finish_cb, $error_cb) = @_;
    my $command_name = ref $command eq 'ARRAY' ? join ' ', @$command : $command;
    my $error_msg    = '';
    my $process      = IO::Async::Process->new(
        command => $command,
    
        # call stdout callback for each line
        stdout => {
            on_read => sub {
                my ($stream, $buffref) = @_;
                while ($$buffref =~ s/^(.*)\n//) {
                    L("$command_name: $1");
                    $stdout_cb->($1) if $stdout_cb;
                }
            }
        },
    
        # add stderr to error message
        stderr => {
            on_read => sub {
                my ($stream, $buffref) = @_;
                while ($$buffref =~ s/^(.*)\n//) {
                    L("$command_name error: $1");
                    $error_msg .= "$$buffref\n";
                }
            }
        },
    
        on_finish => sub {
            my ($self, $exitcode) = @_;
            
            # error
            if ($exitcode) {
                L("Exception: $command_name: $error_msg");
                $error_cb->($error_msg) if $error_cb;
                return;
            }
            
            L("Finished: $command_name");
            $finish_cb->() if $finish_cb;
        }
    );
    L("Running: $command_name");
    $::loop->add($process);
}

$mod