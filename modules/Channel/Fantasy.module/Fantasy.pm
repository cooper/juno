# Copyright (c) 2012-14, Mitchell Cooper
#
# @name:            "Channel::Fantasy"
# @package:         "M::Channel::Fantasy"
# @description:     "channel fantasy commands"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Channel::Fantasy;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

sub init {

    # all local commands. cancel if using fantasy and fantasy isn't allowed.
    $pool->on('connection.message' => \&local_message,
        name     => 'fantasy.stopper',
        priority => 100     # this is higher than the normal handler priority 0
    );

    # catch local PRIVMSGs after the main handler.
    $pool->on('user.message_PRIVMSG' => \&local_privmsg,
        with_eo => 1,
        after   => 'PRIVMSG',
        name    => 'fantasy.privmsg'
    );

    return 1;
}

sub local_message {
    my ($event, $msg) = @_;

    # this was not a fantasy command.
    return 1 if !$event->data('is_fantasy');

    # fantasy commands are permitted.
    return 1 if $event->data('allow_fantasy');

    # otherwise, stop the execution of the command.
    $event->stop('Fantasy not permitted for this command');
    return;

}

sub local_privmsg {
    my ($user, $event, $msg) = @_;

    # the PRIVMSG must have been successful.
    return unless $event->return_of('PRIVMSG');

    # only care about channels.
    my ($channel, $message) = @$msg{'target', 'message'};
    return if !$channel || !$channel->isa('channel');

    # only care about messages starting with !.
    $message =~ m/^!(\w+)\s*(.*)$/ or return;
    my ($cmd, $args) = (lc $1, $2);

    # prevents e.g. !privmsg !privmsg or !lolcat !kick.
    # I doubt this is needed anymore since we use message_PRIVMSG now.
    my $second_p = (split /\s+/, $message, 2)[1];
    return if defined $second_p && substr($second_p, 0, 1) eq '!';

    # handle the command.
    return $user->handle_with_opts(
        "$cmd $$channel{name} $args",
        is_fantasy => 1
    );

}

$mod
