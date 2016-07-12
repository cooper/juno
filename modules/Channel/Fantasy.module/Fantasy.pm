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

use utils qw(conf);

our ($api, $mod, $pool);

sub init {

    # all local commands. cancel if using fantasy and fantasy isn't allowed.
    $pool->on('user.message' => \&local_message,
        with_eo  => 1,
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

my $FANTASY_OK = 1;

# called on all user messages
sub local_message {
    my ($user, $event, $msg) = @_;
    return unless $user->is_local;

    # this was not a fantasy command.
    return $FANTASY_OK
        if !$event->data('is_fantasy');

    # fantasy commands are permitted by the configuration,
    # and the client is not marked as a bot.
    return $FANTASY_OK
        if conf(['channels', 'fantasy'], lc $msg->command)
        && !$user->is_mode('bot');

    # otherwise, stop the execution of the command.
    $event->stop('fantasy_not_allowed');
    return;

}

# called on local PRIVMSG message
sub local_privmsg {
    my ($user, $event, $msg) = @_;
    return unless $user->is_local;

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
    # surely we could detect is_fantasy from the $event instead. that's how
    # we'll do it once the prefix is customizable.
    my $second_p = (split /\s+/, $message, 2)[1];
    return if defined $second_p && substr($second_p, 0, 1) eq '!';

    # handle the command.
    return $user->handle_with_opts(
        "$cmd $$channel{name} $args",
        is_fantasy => 1
    );

}

$mod
