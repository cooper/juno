#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
package user::numerics;

use warnings;
use strict;

use utils qw/conf log2/;

{

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
    RPL_YOUREOPER        => ['381', ':You now have flags: %s'                                             ],
    ERR_NOSUCHNICK       => ['401', '%s :No such nick/channel'                                            ],
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

log2("registering core numerics");
user::mine::register_numeric('core', $_, $numerics{$_}[0], $numerics{$_}[1]) foreach keys %numerics;
log2("end of core numerics");
undef %numerics;

}

sub rpl_isupport {
    my $user = shift;

    my %things = (
        PREFIX      => &prefix,
        CHANTYPES   => '#',                         # TODO
        CHANMODES   => &chanmodes,
        MODES       => 0,                           # TODO
        CHANLIMIT   => '#:0',                       # TODO
        NICKLEN     => conf('limit', 'nick'),
        MAXLIST     => 'beIZ:0',                    # TODO
        NETWORK     => conf('network', 'name'),
        EXCEPTS     => 'e',                         # TODO
        INVEX       => 'I',                         # TODO
        CASEMAPPING => 'rfc1459',
        TOPICLEN    => conf('limit', 'topic'),
        KICKLEN     => conf('limit', 'kickmsg'),
        CHANNELLEN  => conf('limit', 'channelname'),
        RFC2812     => 'YES',
        FNC         => 'YES',
        AWAYLEN     => conf('limit', 'away'),
        MAXTARGETS  => 1                            # TODO
      # ELIST                                       # TODO
    );

    my @lines = '';
    my $curr = 0;

    while (my ($param, $val) = each %things) {
        if (length $lines[$curr] > 135) {
            $curr++;
            $lines[$curr] = ''
        }
        $lines[$curr] .= ($val eq 'YES' ? $param : $param.q(=).$val).q( )
    }

    $user->numeric('RPL_ISUPPORT', $_) foreach @lines
}

# CHANMODES in RPL_ISUPPORT
sub chanmodes {
    #   normal (0)
    #   parameter (1)
    #   parameter_set (2)
    #   list (3)
    #   status (4)
    my (%m, @a);
    @a[3, 1, 2, 0] = (q.., q.., q.., q..);
    foreach my $name (keys %{$utils::conf{modes}{channel}}) {
        my ($type, $letter) = @{$utils::conf{modes}{channel}{$name}};
        $m{$type} = [] unless $m{$type};
        push @{$m{$type}}, $letter
    }

    # alphabetize
    foreach my $type (keys %m) {
        my @alphabetized = sort { $a cmp $b } @{$m{$type}};
        $a[$type] = join '', @alphabetized
    }

    return "$a[3],$a[1],$a[2],$a[0]"
}

# PREFIX in RPL_ISUPPORT
sub prefix {
    my ($modestr, $prefixes) = (q.., q..);
    foreach my $level (sort { $b <=> $a } keys %channel::modes::prefixes) {
        $modestr  .= $channel::modes::prefixes{$level}[0];
        $prefixes .= $channel::modes::prefixes{$level}[1];
    }
    return "($modestr)$prefixes"
}

1

