# Copyright (c) 2009-16, Mitchell Cooper
#
# @name:            "Core::UserNumerics"
# @package:         "M::Core::UserNumerics"
# @description:     "the core set of user numerics"
#
# @depends.bases+   'UserNumerics'
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Core::UserNumerics;

use warnings;
use strict;
use 5.010;

use modes;
use utils qw(conf v);

our ($api, $mod, $me, $pool);

our %user_numerics = (
                          #################################################################################
                          ###============================= IRC Numerics List ===========================###
                          #################################################################################
                          # [                                                                             ],
                          # [============================= DIRECT CONNECTION =============================],
                          # [                                                                             ],
    RPL_WELCOME          => ['001', ':Welcome to the %s IRC Network %s!%s@%s'                             ],
    RPL_YOURHOST         => ['002', ':Your host is %s, running version %s'                                ],
    RPL_CREATED          => ['003', ':This server was created %s'                                         ],
    RPL_MYINFO           => ['004', '%s %s %s %s'                                                         ],
    RPL_ISUPPORT         => ['005', \&rpl_isupport                                                        ],
    RPL_MAP              => ['015', ':%s- %s: %d users (%d%%)'                                            ],
    RPL_MAP_TOTAL        => ['015', ':- Total of %d users on %d servers, average %d users per server'     ],
    RPL_MAPEND           => ['017', ':End of MAP'                                                         ],
    RPL_YOURID           => ['042', '%s :your unique ID'                                                  ],
    RPL_SAVENICK         => ['043', '%s :Nick collision, forcing nick change to your unique ID'           ],
                          # [                                                                             ],
                          # [============================== NORMAL REPLIES ===============================],
                          # [                                                                             ],
    RPL_UMODEIS          => [221, '%s'                                                                    ],
    RPL_STATSCONN        => [250, ':Highest connection count: %d (%d clients) (%d connections received)'  ],
    RPL_LUSERCLIENT      => [251, ':There are %d users and %d invisible on %d servers'                    ],
    RPL_LUSEROP          => [252, '%d :operators online'                                                  ],
    RPL_LUSERUNKNOWN     => [253, '%d :unknown connections'                                               ],
    RPL_LUSERCHANNELS    => [254, '%d :channels formed'                                                   ],
    RPL_LUSERME          => [255, 'I have %d clients and %d servers'                                      ],
    RPL_ADMINME          => [256, ':Administrative info about %s'                                         ],
    RPL_ADMINLOC1        => [257, ':%s'                                                                   ],
    RPL_ADMINLOC2        => [258, ':%s'                                                                   ],
    RPL_ADMINEMAIL       => [259, ':%s'                                                                   ],
    RPL_LOAD2HI          => [263, '%s :Command dropped'                                                   ],
    RPL_LOCALUSERS       => [265, '%d %d :Current local users %d, max %d'                                 ],
    RPL_GLOBALUSERS      => [266, '%d %d :Current global users %d, max %d'                                ],
    RPL_AWAY             => [301, '%s :%s'                                                                ],
    RPL_USERHOST         => [302, ':%s'                                                                   ],
    RPL_ISON             => [303, ':%s'                                                                   ],
    RPL_UNAWAY           => [305, ':You are no longer marked as away'                                     ],
    RPL_NOWAWAY          => [306, ':You are now marked as away'                                           ],
    RPL_CREATIONTIME     => [329, '%s %d'                                                                 ],
    RPL_WHOISUSER        => [311, '%s %s %s * :%s'                                                        ],
    RPL_WHOISSERVER      => [312, '%s %s :%s'                                                             ],
    RPL_WHOISOPERATOR    => [313, '%s :is %s'                                                             ],
    RPL_ENDOFWHO         => [315, '%s :End of WHO list'                                                   ],
    RPL_WHOISIDLE        => [317, '%s %d %d :seconds idle, signon time'                                   ],
    RPL_ENDOFWHOIS       => [318, '%s :End of WHOIS list'                                                 ],
    RPL_WHOISCHANNELS    => [319, '%s :%s'                                                                ],
    RPL_LISTSTART        => [321, 'Channel :Users  Name'                                                  ],
    RPL_LIST             => [322, '%s %d :%s'                                                             ],
    RPL_LISTEND          => [323, ':End of channel list'                                                  ],
    RPL_CHANNELMODEIS    => [324, '%s %s'                                                                 ],
    RPL_CREATIONTIME     => [329, '%s %d'                                                                 ],
    RPL_WHOISACCOUNT     => [330, '%s %s :is logged in as'                                                ],
    RPL_NOTOPIC          => [331, '%s :No topic is set'                                                   ],
    RPL_TOPIC            => [332, '%s :%s'                                                                ],
    RPL_TOPICWHOTIME     => [333, '%s %s %d'                                                              ],
    RPL_WHOISBOT         => [335, '%s :is a bot'                                                          ],
    RPL_EXCEPTLIST       => [348, '%s %s'                                                                 ],
    RPL_ENDOFEXCEPTLIST  => [349, '%s :End of channel exception list'                                     ],
    RPL_VERSION          => [351, '%s-%s. %s :started at version %s; currently running %s'                ],
    RPL_WHOREPLY         => [352, '%s'                                                                    ],
    RPL_NAMREPLY         => [353, '%s %s :%s'                                                             ],
    RPL_WHOSPCRPL        => [354, '%s'                                                                    ],
    RPL_LINKS            => [364, '%s %s :%d %s'                                                          ],
    RPL_ENDOFLINKS       => [365, '%s :End of LINKS list'                                                 ],
    RPL_ENDOFNAMES       => [366, '%s :End of NAMES list'                                                 ],
    RPL_BANLIST          => [367, '%s %s %s %d'                                                           ],
    RPL_ENDOFBANLIST     => [368, '%s :End of channel ban list'                                           ],
    RPL_INFO             => [372, ':%s'                                                                   ],
    RPL_MOTD             => [372, ':- %s'                                                                 ],
    RPL_ENDOFINFO        => [374, 'End of INFO list'                                                      ],
    RPL_MOTDSTART        => [375, ':%s Message of the day'                                                ],
    RPL_ENDOFMOTD        => [376, ':End of message of the day'                                            ],
    RPL_WHOISMODES       => [379, '%s :is using modes %s'                                                 ],
    RPL_WHOISHOST        => [378, '%s :is connecting from *@%s %s'                                        ],
    RPL_YOUREOPER        => [381, ':You are now an IRC operator'                                          ],
    RPL_REHASHING        => [382, '%s :Rehashing server configuration file'                               ],
    RPL_TIME             => [391, \&rpl_time                                                              ],
    RPL_HOSTHIDDEN       => [396, '%s :is now your hidden host'                                           ],
    RPL_HOSTHIDDEN_SVS   => [396, '%s :is now your hidden host (set by %s)'                               ],
    RPL_HOSTHIDDEN_RST   => [396, '%s :hostname reset'                                                    ],
                          # [                                                                             ],
                          # [============================== ERROR REPLIES ================================],
                          # [                                                                             ],
    ERR_NOSUCHNICK       => [401, '%s :No such nick/channel'                                              ],
    ERR_NOSUCHSERVER     => [402, '%s :No such server'                                                    ],
    ERR_NOSUCHCHANNEL    => [403, '%s :No such channel'                                                   ],
    ERR_CANNOTSENDTOCHAN => [404, '%s :%s'                                                                ],
    ERR_TOOMANYCHANNELS  => [405, '%s :You have joined too many channels'                                 ],
    ERR_NOTEXTTOSEND     => [412, ':No text to send'                                                      ],
    ERR_UNKNOWNCOMMAND   => [421, '%s :Unknown command'                                                   ],
    ERR_NOMOTD           => [422, ':MOTD file is missing'                                                 ],
    ERR_ERRONEUSNICKNAME => [432, '%s :Erroneous nickname'                                                ],
    ERR_NICKNAMEINUSE    => [433, '%s :Nickname in use'                                                   ],
    ERR_USERNOTINCHANNEL => [441, '%s %s :isn\'t on that channel'                                         ],
    ERR_NOTONCHANNEL     => [442, '%s :You\'re not on that channel'                                       ],
    ERR_USERONCHANNEL    => [443, '%s %s :is already on channel'                                          ],
    ERR_NEEDMOREPARAMS   => [461, '%s :Not enough parameters'                                             ],
    ERR_ALREADYREGISTRED => [462, ':You may not reregister'                                               ],
    ERR_BANNEDFROMCHAN   => [474, '%s :You\'re banned'                                                    ],
    ERR_BANLISTFULL      => [478, '%s %s :Channel %s list is full'                                        ],
    ERR_NOPRIVILEGES     => [481, ':Permission denied - You can\'t %s'                                    ],
    ERR_CHANOPRIVSNEEDED => [482, '%s :You do not have the required status to perform this action'        ],
    ERR_NOOPERHOST       => [491, ':No oper blocks for your host'                                         ],
    ERR_USERSDONTMATCH   => [502, ':Can\'t change mode for other users'                                   ],
                          # [                                                                             ],
                          # [================================ EXTENSIONS =================================],
                          # [                                                                             ],
    RPL_WHOISSECURE      => [671, '%s :is using a secure connection'                                      ],
    ERR_MLOCKRESTRICTED  => [742, '%s %s :MLOCK policy does not allow this mode to be changed'            ],
    RPL_LOGGEDIN         => [900, '%s %s :You are now logged in as %s'                                    ],
    RPL_LOGGEDOUT        => [901, '%s :You are now logged out'                                            ],
    ERR_NICKLOCKED       => [902, ':You must use a nick assigned to you'                                  ],
                          # [                                                                             ],
                            ###############################################################################
);

sub init {
    $me->on(supported => \&isp_core, name => 'core.supported');
    return 1;
}

# RPL_ISUPPORT. See issue #96.
sub rpl_isupport {
    my $user = shift;
    my $yes = '__ENABLE__';

    # fire the event
    my %things;
    $me->fire(supported => \%things, $yes, $user);

    # spit out the result
    my ($curr, @lines) = (0, '');
    while (my ($param, $val) = each %things) {

        # configuration value probably nonexistent.
        next unless defined $val;

        # only allow around 140 chars per line.
        if (length $lines[$curr] > 135) {
            $curr++;
            $lines[$curr] = '';
        }

        $lines[$curr] .= $val eq $yes ? "$param " : "$param=$val ";
    }

    return map { "$_:are supported by this server" } @lines;
}

# core supported callback
sub isp_core {
    my ($event, $supported, $yes, $user) = @_;
    my $listmodes = join '',
        sort map $_->{letter},
        grep { ($_->{type} // MODE_UNKNOWN) == MODE_LIST }
        values %{ $me->{cmodes} };

    # construct core tokens
    my %core_supported = (
        PREFIX      => &isp_prefix,
        CHANTYPES   => '#',
        CHANMODES   => &isp_chanmodes,
        MODES       => conf('channels', 'client_max_mode_params'),
        CHANLIMIT   => '#:'.$user->conn->class_max('channel'),
        NICKLEN     => conf('limit', 'nick'),
        MAXLIST     => $listmodes.q(:).conf('channels', 'max_bans'),
        NETWORK     => conf('server', 'network') // conf('network', 'name'),
        EXCEPTS     => $me->cmode_letter('except'),
        DEAF        => $me->umode_letter('deaf'),
        CASEMAPPING => $::casemapping || lc conf('server', 'casemapping'),
        TOPICLEN    => conf('limit', 'topic'),
        KICKLEN     => conf('limit', 'kickmsg'),
        CHANNELLEN  => conf('limit', 'channelname'),
        RFC2812     => $yes,
        FNC         => $yes,
        AWAYLEN     => conf('limit', 'away'),
        WHOX        => $yes,
        MAXTARGETS  => 1                    # FIXME: (#53) needs work
      # ELIST       => 'flags'              # TODO: (#27) not implemented yet
    );

    # inject them
    @$supported{ keys %core_supported } = values %core_supported;
}

# CHANMODES in RPL_ISUPPORT.
sub isp_chanmodes {
    #   normal          (0)
    #   parameter       (1)
    #   parameter_set   (2)
    #   list            (3)
    #   status          (4)
    #   key             (5)
    my %m;
    my @a = ('') x 5;

    # find each mode letter.
    foreach my $name ($ircd::conf->keys_of_block(['modes', 'channel'])) {

        # fetch the type.
        # channel key (+k) is an exception.
        my ($type, $letter) = @{ conf(['modes', 'channel'], $name) };
        $type = MODE_PARAM if $type == MODE_KEY;

        # ignore modes without blocks.
        next unless keys %{ $pool->{channel_modes}{$name} || {} };

        push @{ $m{$type} ||= [] }, $letter;
    }

    # alphabetize each group.
    foreach my $type (keys %m) {
        my @alphabetized = sort { $a cmp $b } @{ $m{$type} };
        $a[$type] = join '', @alphabetized;
    }

    return "$a[3],$a[1],$a[2],$a[0]";
}

# PREFIX in RPL_ISUPPORT.
sub isp_prefix {
    my ($mode_str, $prefixes) = ('', '');

    # sort from largest to smallest level.
    foreach my $level (sort { $b <=> $a } keys %ircd::channel_mode_prefixes) {
        $mode_str .= $ircd::channel_mode_prefixes{$level}[0];
        $prefixes .= $ircd::channel_mode_prefixes{$level}[1];
    }

    return "($mode_str)$prefixes";
}

sub rpl_time {
    my ($user, $ts) = @_;
    my $time = POSIX::strftime('%A %B %d %Y %H:%M:%S %z (%Z)', localtime $ts);
    return "$$me{name} :$time";
}

$mod
