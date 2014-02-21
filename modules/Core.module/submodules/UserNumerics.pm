# Copyright (c) 2009-13, Mitchell Cooper
package API::Module::Core::UserNumerics;
 
use warnings;
use strict;
 
use utils 'log2';


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
    RPL_ISUPPORT         => ['005', '%s:are supported by this server'                                     ],
    RPL_MAP              => ['015', ':%s'                                                                 ],
    RPL_MAPEND           => ['017', ':End of MAP'                                                         ],
    RPL_UMODEIS          => ['221', '%s'                                                                  ],
    RPL_STATSCONN        => ['250', ':Highest connection count: %d (%d clients) (%d connections received)'],
    RPL_LUSERCLIENT      => ['251', ':There are %d users and %d invisible on %d servers'                  ],
    RPL_LUSEROP          => ['252', '%d :operators online'                                                ],
    RPL_LUSERUNKNOWN     => ['253', '%d :unknown connections'                                             ],
    RPL_LUSERCHANNELS    => ['254', '%d :channels formed'                                                 ],
    RPL_LUSERME          => ['255', 'I have %d clients and %d servers'                                    ],
    RPL_LOCALUSERS       => ['265', '%d %d :Current local users %d, max %d'                               ],
    RPL_GLOBALUSERS      => ['266', '%d %d :Current global users %d, max %d'                              ],
    RPL_AWAY             => ['301', '%s :%s'                                                              ],
    RPL_ISON             => ['303', ':%s'                                                                 ],
    RPL_UNAWAY           => ['305', ':You are no longer marked as away'                                   ],
    RPL_NOWAWAY          => ['306', ':You are now marked as away'                                         ],
    RPL_CREATIONTIME     => ['329', '%s %d'                                                               ],
    RPL_WHOISUSER        => ['311', '%s %s %s * :%s'                                                      ],
    RPL_WHOISSERVER      => ['312', '%s %s :%s'                                                           ],
    RPL_WHOISOPERATOR    => ['313', '%s :is an IRC operator'                                              ],
    RPL_ENDOFWHO         => ['315', '%s :End of WHO list'                                                 ],
    RPL_ENDOFWHOIS       => ['318', '%s :End of WHOIS list'                                               ],
    RPL_WHOISCHANNELS    => ['319', '%s :%s'                                                              ],
    RPL_LISTSTART        => ['321', 'Channel :Users  Name'                                                ],
    RPL_LIST             => ['322', '%s %d :%s'                                                           ],
    RPL_LISTEND          => ['323', ':End of channel list'                                                ],
    RPL_CHANNELMODEIS    => ['324', '%s %s'                                                               ],
    RPL_CREATIONTIME     => ['329', '%s %d'                                                               ],
    RPL_NOTOPIC          => ['331', '%s :No topic is set'                                                 ],
    RPL_TOPIC            => ['332', '%s :%s'                                                              ],
    RPL_TOPICWHOTIME     => ['333', '%s %s %d'                                                            ],
    RPL_WHOREPLY         => ['352', '%s %s %s %s %s %s :0 %s'                                             ],
    RPL_NAMEREPLY        => ['353', '%s %s :%s'                                                           ],
    RPL_ENDOFNAMES       => ['366', '%s :End of NAMES list'                                               ],
    RPL_BANLIST          => ['367', '%s %s %s %d'                                                         ],
    RPL_ENDOFBANLIST     => ['368', '%s :End of ban list'                                                 ],
    RPL_INFO             => ['372', ':%s'                                                                 ],
    RPL_MOTD             => ['372', ':- %s'                                                               ],
    RPL_ENDOFINFO        => ['374', 'End of INFO list'                                                    ],
    RPL_MOTDSTART        => ['375', ':%s Message of the day'                                              ],
    RPL_ENDOFMOTD        => ['376', ':End of message of the day'                                          ],
    RPL_WHOISMODES       => ['379', '%s :is using modes %s'                                               ],
    RPL_WHOISHOST        => ['378', '%s :is connecting from *@%s %s'                                      ],
    RPL_YOUREOPER        => ['381', ':You are now an IRC operator'                                        ],
    ERR_NOSUCHNICK       => ['401', '%s :No such nick/channel'                                            ],
    ERR_NOSUCHSERVER     => ['402', '%s :No such server'                                                  ],
    ERR_NOSUCHCHANNEL    => ['403', '%s :No such channel'                                                 ],
    ERR_CANNOTSENDTOCHAN => ['404', '%s :%s'                                                              ],
    ERR_NOTEXTTOSEND     => ['412', ':No text to send'                                                    ],
    ERR_UNKNOWNCOMMAND   => ['421', '%s :Unknown command'                                                 ],
    ERR_NOMOTD           => ['422', ':MOTD file is missing'                                               ],
    ERR_ERRONEUSNICKNAME => ['432', '%s :Erroneous nickname'                                              ],
    ERR_NICKNAMEINUSE    => ['433', '%s :Nickname in use'                                                 ],
    ERR_USERNOTINCHANNEL => ['441', '%s %s :isn\'t on that channel'                                       ],
    ERR_NOTONCHANNEL     => ['442', '%s :You\'re not on that channel'                                     ],
    ERR_NEEDMOREPARAMS   => ['461', '%s :Not enough parameters'                                           ],
    ERR_ALREADYREGISTRED => ['462', ':You may not reregister'                                             ],
    ERR_BANNEDFROMCHAN   => ['474', '%s :You\'re banned'                                                  ],
    ERR_NOPRIVILEGES     => ['481', ':Permission denied'                                                  ],
    ERR_CHANOPRIVSNEEDED => ['482', '%s :You do not have the required status to perform this action'      ],
    ERR_NOOPERHOST       => ['491', ':No oper blocks for your host'                                       ],
    ERR_USERSDONTMATCH   => ['502', ':Can\'t change mode for other users'                                 ]
                            ###############################################################################
);

our $mod = API::Module->new(
    name        => 'UserNumerics',
    version     => '0.1',
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

$mod
