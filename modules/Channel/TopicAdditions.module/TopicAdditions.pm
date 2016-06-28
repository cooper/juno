# Copyright (c) 2016, Mitchell Cooper
#
# Created on Mitchells-MacBook-Pro.local
# Tue Dec 30 21:42:38 EST 2014
# TopicAdditions.pm
#
# @name:            'Channel::TopicAdditions'
# @package:         'M::Channel::TopicAdditions'
# @description:     'additional topic management commands'
#
# @depends.modules: ['Core::UserCommands', 'Base::UserCommands']
#
# @author.name:     'Mitchell Cooper'
# @author.website:  'https://github.com/cooper'
#
package M::Channel::TopicAdditions;

use warnings;
use strict;
use 5.010;

our ($api, $mod, $pool);

our %user_commands = (
    TOPICPREPEND => {
        desc   => 'add a phrase to the beginning of the topic',
        params => 'channel :rest',
        code   => \&cmd_prepend,
        fntsy  => 1
    },
    TOPICAPPEND => {
        desc   => 'add a phrase to the end of a topic',
        params => 'channel :rest',
        code   => \&cmd_append,
        fntsy  => 1
    }
);

sub cmd_prepend {
    my ($user, $event, $channel, $new) = @_;
    $new = "$new | $$channel{topic}{topic}" if $channel->{topic};
    return $user->handle_unsafe("TOPIC $$channel{name} :$new");
}

sub cmd_append {
    my ($user, $event, $channel, $new) = @_;
    $new = "$$channel{topic}{topic} | $new" if $channel->{topic};
    return $user->handle_unsafe("TOPIC $$channel{name} :$new");
}

$mod
