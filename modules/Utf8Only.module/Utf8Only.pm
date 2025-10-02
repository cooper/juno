# Copyright (c) 2025, Mitchell Cooper
#
# @name:            "Utf8Only"
# @package:         "M::Utf8Only"
# @description:     "Enforces UTF-8 encoding on the network"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Utf8Only;

use warnings;
use strict;
use 5.010;

use Encode qw(decode FB_DEFAULT);

our ($api, $mod, $pool, $me);

sub init {
    # add UTF8ONLY to ISUPPORT
    $me->on(supported => sub {
        my ($me, $event, $supported, $yes, $user) = @_;
        $supported->{UTF8ONLY} = $yes;
    }, name => 'utf8only.supported');

    # validate UTF-8 in incoming messages
    $pool->on('connection.message' => \&validate_utf8,
        name => 'utf8only.validate', priority => 100);

    return 1;
}

# validate UTF-8 in incoming messages
sub validate_utf8 {
    my ($conn, $event, $msg) = @_;
    my $data = $msg->{data};

    # skip if already validated or if it's a server connection
    return if $msg->{utf8_validated} || $conn->server;

    # attempt to decode as UTF-8
    my $decoded = eval { decode('UTF-8', $data, FB_DEFAULT) };

    # if decoding failed or was modified, it contained invalid UTF-8
    if ($@ || $decoded ne $data) {

        # remove invalid sequences
        $msg->{data} = $decoded;
        $msg->{utf8_modified} = 1;

        # send WARN message
        $conn->sendwarn($msg->{command}, 'INVALID_UTF8', 'Your message contained invalid UTF-8 and was modified');

        # reparse with cleaned data
        $msg->parse;
    }

    $msg->{utf8_validated} = 1;
    return;
}

$mod