# Copyright (c) 2009-13, Mitchell Cooper
package API::Module::Core::UserNumerics;
 
use warnings;
use strict;
 
use utils qw(log2 conf v);


my %numerics = (
                            ###############################################################################
                            #                              core numerics list                             #
                            #                              ------------------                             #
                            #      these are internal numerics that will be registered to user::mine.     #
                            ###############################################################################
    RPL_WELCOME          => ['001', 'Welcome to the %s IRC Network %s!%s@%s'                              ],
    RPL_YOURHOST         => ['002', ':Your host is %s, running version %s'                                ],
    RPL_CREATED          => ['003', ':This server was created %s'                                         ],
    RPL_MYINFO           => ['004', '%s %s %s %s'                                                         ],
    RPL_ISUPPORT         => ['005', \&rpl_isupport                                                        ],
    RPL_MAP              => ['015', ':%s'                                                                 ],
    RPL_MAPEND           => ['017', ':End of MAP'                                                         ],
    # 3 digits           => [#############################################################################],
    RPL_UMODEIS          => [221, '%s'                                                                    ],
    RPL_STATSCONN        => [250, ':Highest connection count: %d (%d clients) (%d connections received)'  ],
    RPL_LUSERCLIENT      => [251, ':There are %d users and %d invisible on %d servers'                    ],
    RPL_LUSEROP          => [252, '%d :operators online'                                                  ],
    RPL_LUSERUNKNOWN     => [253, '%d :unknown connections'                                               ],
    RPL_LUSERCHANNELS    => [254, '%d :channels formed'                                                   ],
    RPL_LUSERME          => [255, 'I have %d clients and %d servers'                                      ],
    RPL_LOCALUSERS       => [265, '%d %d :Current local users %d, max %d'                                 ],
    RPL_GLOBALUSERS      => [266, '%d %d :Current global users %d, max %d'                                ],
    RPL_AWAY             => [301, '%s :%s'                                                                ],
    RPL_ISON             => [303, ':%s'                                                                   ],
    RPL_UNAWAY           => [305, ':You are no longer marked as away'                                     ],
    RPL_NOWAWAY          => [306, ':You are now marked as away'                                           ],
    RPL_CREATIONTIME     => [329, '%s %d'                                                                 ],
    RPL_WHOISUSER        => [311, '%s %s %s * :%s'                                                        ],
    RPL_WHOISSERVER      => [312, '%s %s :%s'                                                             ],
    RPL_WHOISOPERATOR    => [313, '%s :is an IRC operator'                                                ],
    RPL_ENDOFWHO         => [315, '%s :End of WHO list'                                                   ],
    RPL_ENDOFWHOIS       => [318, '%s :End of WHOIS list'                                                 ],
    RPL_WHOISCHANNELS    => [319, '%s :%s'                                                                ],
    RPL_LISTSTART        => [321, 'Channel :Users  Name'                                                  ],
    RPL_LIST             => [322, '%s %d :%s'                                                             ],
    RPL_LISTEND          => [323, ':End of channel list'                                                  ],
    RPL_CHANNELMODEIS    => [324, '%s %s'                                                                 ],
    RPL_CREATIONTIME     => [329, '%s %d'                                                                 ],
    RPL_NOTOPIC          => [331, '%s :No topic is set'                                                   ],
    RPL_TOPIC            => [332, '%s :%s'                                                                ],
    RPL_TOPICWHOTIME     => [333, '%s %s %d'                                                              ],
    RPL_INVITELIST       => [346, '%s %s'                                                                 ],
    RPL_ENDOFINVITELIST  => [347, '%s :End of channel invite list'                                        ],
    RPL_EXCEPTLIST       => [348, '%s %s'                                                                 ],
    RPL_ENDOFEXCEPTLIST  => [349, '%s :End of channel exception list'                                     ],
    RPL_VERSION          => [351, '%s-%s. %s :start(%s);cur(%s);core(%s)'                                 ],
    RPL_WHOREPLY         => [352, '%s %s %s %s %s %s :0 %s'                                               ],
    RPL_NAMEREPLY        => [353, '%s %s :%s'                                                             ],
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
    ERR_NOSUCHNICK       => [401, '%s :No such nick/channel'                                              ],
    ERR_NOSUCHSERVER     => [402, '%s :No such server'                                                    ],
    ERR_NOSUCHCHANNEL    => [403, '%s :No such channel'                                                   ],
    ERR_CANNOTSENDTOCHAN => [404, '%s :%s'                                                                ],
    ERR_NOTEXTTOSEND     => [412, ':No text to send'                                                      ],
    ERR_UNKNOWNCOMMAND   => [421, '%s :Unknown command'                                                   ],
    ERR_NOMOTD           => [422, ':MOTD file is missing'                                                 ],
    ERR_ERRONEUSNICKNAME => [432, '%s :Erroneous nickname'                                                ],
    ERR_NICKNAMEINUSE    => [433, '%s :Nickname in use'                                                   ],
    ERR_USERNOTINCHANNEL => [441, '%s %s :isn\'t on that channel'                                         ],
    ERR_NOTONCHANNEL     => [442, '%s :You\'re not on that channel'                                       ],
    ERR_NEEDMOREPARAMS   => [461, '%s :Not enough parameters'                                             ],
    ERR_ALREADYREGISTRED => [462, ':You may not reregister'                                               ],
    ERR_BANNEDFROMCHAN   => [474, '%s :You\'re banned'                                                    ],
    ERR_NOPRIVILEGES     => [481, ':Permission denied - You can\'t %s'                                    ],
    ERR_CHANOPRIVSNEEDED => [482, '%s :You do not have the required status to perform this action'        ],
    ERR_NOOPERHOST       => [491, ':No oper blocks for your host'                                         ],
    ERR_USERSDONTMATCH   => [502, ':Can\'t change mode for other users'                                   ]
                            ###############################################################################
);

our $mod = API::Module->new(
    name        => 'UserNumerics',
    version     => $API::Module::Core::VERSION,
    description => 'the core set of user numerics',
    requires    => ['UserNumerics'],
    initialize  => \&init
);
 
sub init {

    $mod->register_user_numeric(
        name    => $_,
        number  => $numerics{$_}[0],
        format  => $numerics{$_}[1]
    ) foreach keys %numerics;
    
    undef %numerics;
    
    return 1;
}

# RPL_ISUPPORT
sub rpl_isupport {
    my ($user, $server) = (shift, v('SERVER'));
    my $listmodes = join '', sort map { $_->{letter} }
      grep { $_->{type} // -1 == 3 } values %{ $server->{cmodes} };

    my %things = (
        PREFIX      => &isp_prefix,
        CHANTYPES   => '#',                         # TODO: only global channels supported
        CHANMODES   => &isp_chanmodes,
        MODES       => 5,                           # TODO: currently unlimited
        CHANLIMIT   => '#:100',                     # TODO: currently unlimited
        NICKLEN     => conf('limit', 'nick'),
        MAXLIST     => "$listmodes:1000",           # TODO: currently unlimited
        NETWORK     => conf('network', 'name'),
        EXCEPTS     => $server->cmode_letter('except'),
        INVEX       => $server->cmode_letter('invite_except'),
        CASEMAPPING => 'rfc1459',
        TOPICLEN    => conf('limit', 'topic'),
        KICKLEN     => conf('limit', 'kickmsg'),
        CHANNELLEN  => conf('limit', 'channelname'),
        RFC2812     => 'YES',
        FNC         => 'YES',
        AWAYLEN     => conf('limit', 'away'),
        MAXTARGETS  => 1                            # TODO: currently unconfigurable
      # ELIST       => 'YES'                        # TODO: not implemented yet
    );

    my ($curr, @lines) = (0, '');
    while (my ($param, $val) = each %things) {
    
        # configuration value probably nonexistent.
        next unless defined $val;
        
        # only allow around 140 chars per line.
        if (length $lines[$curr] > 135) {
            $curr++;
            $lines[$curr] = '';
        }
        
        $lines[$curr] .= $val eq 'YES' ? "$param " : "$param=$val ";
    }

    return map { "$_:are supported by this server" } @lines
}

# CHANMODES in RPL_ISUPPORT.
sub isp_chanmodes {
    #   normal          (0)
    #   parameter       (1)
    #   parameter_set   (2)
    #   list            (3)
    #   status          (4)
    my %m;
    my @a = ('', '', '', '');
    
    # find each mode letter.
    foreach my $name ($ircd::conf->keys_of_block(['modes', 'channel'])) {
        my ($type, $letter) = @{ conf(['modes', 'channel'], $name) };
        $m{$type} = [] unless $m{$type};
        push @{ $m{$type} }, $letter;
    }

    # alphabetize.
    foreach my $type (keys %m) {
        my @alphabetized = sort { $a cmp $b } @{ $m{$type} };
        $a[$type] = join '', @alphabetized
    }

    return "$a[3],$a[1],$a[2],$a[0]";
}

# PREFIX in RPL_ISUPPORT.
sub isp_prefix {
    my ($modestr, $prefixes) = ('', '');
    
    # sort from largest to smallest level.
    foreach my $level (sort { $b <=> $a } keys %channel::modes::prefixes) {
        $modestr  .= $channel::modes::prefixes{$level}[0];
        $prefixes .= $channel::modes::prefixes{$level}[1];
    }
    
    return "($modestr)$prefixes";
}

$mod
