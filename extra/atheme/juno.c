/*
 * Copyright (c) 2003-2004 E. Will et al.
 * Copyright (c) 2005-2008 Atheme Development Group
 * Copyright (c) 2008-2010 ShadowIRCd Development Group
 * Copyright (c) 2013 PonyChat Development Group
 * Copyright (c) 2015 Mitchell Cooper
 *
 * Rights to this code are documented in LICENSE.
 *
 * This file contains protocol support for juno.
 *
 */

#include "atheme.h"
#include "uplink.h"
#include "pmodule.h"

/*        CMODE_NOCOLOR         0x00001000       hyperion    +c     prohibit color codes    */
/*        CMODE_REGONLY         0x00002000       hyperion    +r     register users only     */
/*        CMODE_OPMOD           0x00004000       hyperion    +z     ops get rejected msgs   */
#define   CMODE_FINVITE         0x00008000   /*  hyperion    +g     free invite             */

#define   CMODE_EXLIMIT         0x00010000   /*  charybdis   +L     unlimited +beI etc.     */
/*        CMODE_PERM            0x00020000       charybdis   +P     permanent               */
#define   CMODE_FTARGET         0x00040000   /*  charybdis   +F     free forward target     */
/*        CMODE_DISFWD          0x00080000       charybdis   +Q     disable forwarding      */

/*        CMODE_NOCTCP          0x00100000       charybdis   +C     block CTCPs to channel  */
/*        CMODE_IMMUNE          0x00200000       shadowircd  +M     */
/*        CMODE_ADMINONLY       0x00400000       shadowircd  +A     netadmins only allowed  */
#define   CMODE_OPERONLY        0x00800000   /*  shadowircd  +O     opers only allowed      */

/*        CMODE_SSLONLY         0x01000000       shadowircd  +S     SSL users only allowed  */
/*        CMODE_NOACTIONS       0x02000000       shadowircd  +D     block CTCP actions      */
/*        CMODE_NONOTICE        0x04000000       shadowircd  +T     block NOTICE            */
/*        CMODE_NOCAPS          0x08000000       shadowircd  +G     block all caps          */

/*        CMODE_NOKICKS         0x10000000       shadowircd  +E     disable KICK command    */
/*        CMODE_NONICKS         0x20000000       shadowircd  +N     block nick changes      */
/*        CMODE_NOREPEAT        0x40000000       shadowircd  +K     block repeat messages   */
/*        CMODE_KICKNOREJOIN    0x80000000       shadowircd  +J     block rejoin after kick */

/*        CMODE_HIDEBANS       0x100000000       elemental   +u     hide bans from non-ops  */
/*        CMODE_STRIP          0x200000000       unreal      +S     strip color codes       */
/*        CMODE_CENSOR         0x400000000       unreal      +G     censor bad words        */
/*        CMODE_NOKNOCK        0x800000000       unreal      +K     disable KNOCK command   */

DECLARE_MODULE_V1("protocol/juno", true, _modinit, NULL, PACKAGE_STRING, "Mitchell Cooper <https://github.com/cooper>");

ircd_t juno = {
    .ircdname           = "juno",
    .tldprefix          = "$$",
    .uses_uid           = true,
    .uses_rcommand      = false,
    .uses_owner         = true,
    .uses_protect       = true,
    .uses_halfops       = true,
    .uses_p10           = false,
    .uses_vhost         = false,
    .oper_only_modes    = CMODE_OPERONLY,
        /* | CMODE_EXLIMIT | CMODE_PERM | CMODE_IMMUNE | CMODE_ADMINONLY */
    .owner_mode         = CSTATUS_OWNER,
    .protect_mode       = CSTATUS_PROTECT,
    .halfops_mode       = CSTATUS_HALFOP,
    .owner_mchar        = "+y",
    .protect_mchar      = "+a",
    .halfops_mchar      = "+h",
    .type               = PROTOCOL_SHADOWIRCD,  /* close enough */
    .perm_mode          = 0,                    /* CMODE_PERM */
    .oimmune_mode       = 0,                    /* CMODE_IMMUNE */
    .ban_like_modes     = "AbeIZ",
    .except_mchar       = 'e',
    .invex_mchar        = 'I',
    .flags              = IRCD_CIDR_BANS | IRCD_HOLDNICK,
};


struct cmode_ juno_mode_list[] = {
    { 'i', CMODE_INVITE         },      /* invite only                              */
    { 'm', CMODE_MOD            },      /* moderated                                */
    { 'n', CMODE_NOEXT          },      /* block external messages                  */
 /* { 'p', CMODE_PRIV           }, */   /* private                                  */
    { 's', CMODE_SEC            },      /* secret                                   */
    { 't', CMODE_TOPIC          },      /* only ops can set the topic               */
 /* { 'c', CMODE_NOCOLOR        },      /* block color codes                        */
 /* { 'r', CMODE_REGONLY        },      /* only registered users allowed            */
 /* { 'z', CMODE_OPMOD          },      /* ops can see rejected messages            */
    { 'g', CMODE_FINVITE        },      /* free invite, non-ops can invite          */
 /* { 'L', CMODE_EXLIMIT        },      /* unlimited ban-type mode entries          */
 /* { 'P', CMODE_PERM           },      /* permanent                                */
    { 'F', CMODE_FTARGET        },      /* free target, non-ops can forward here    */
 /* { 'Q', CMODE_DISFWD         },      /* disable channel forwarding               */
 /* { 'M', CMODE_IMMUNE         },      /* */
 /* { 'C', CMODE_NOCTCP         },      /* block CTCPs to channel                   */
 /* { 'A', CMODE_ADMINONLY      },      /* only network administrators allowed      */
    { 'O', CMODE_OPERONLY       },      /* only IRC operators allowed               */
 /* { 'S', CMODE_SSLONLY        },      /* only SSL clients allowed                 */
 /* { 'D', CMODE_NOACTIONS      },      /* block CTCP actions                       */
 /* { 'T', CMODE_NONOTICE       },      /* block notices to channel                 */
 /* { 'G', CMODE_NOCAPS         },      /* block messages in all caps               */
 /* { 'E', CMODE_NOKICKS        },      /* disable KICK command                     */
 /* { 'd', CMODE_NONICKS        },      /* block nick changes while in channel      */
 /* { 'K', CMODE_NOREPEAT       },      /* block repetitive messages                */
 /* { 'J', CMODE_KICKNOREJOIN   },      /* block immediate rejoin after KICK        */
 /* { 'u', CMODE_HIDEBANS       },      /* hide ban-type mode lists from non-ops    */
    { '\0', 0 }
};


static bool check_forward(const char *, channel_t *, mychan_t *, user_t *, myuser_t *);

struct extmode juno_ignore_mode_list[] = {
    { 'f', check_forward        },
    { '\0', 0 }
};


struct cmode_ juno_status_mode_list[] = {
    { 'y', CSTATUS_OWNER        },
    { 'a', CSTATUS_PROTECT      },
    { 'o', CSTATUS_OP           },
    { 'h', CSTATUS_HALFOP       },
    { 'v', CSTATUS_VOICE        },
    { '\0', 0 }
};


/* these can be any arbitrary symbols
 * as long as they are consistent with
 * those in juno's default.conf. */
struct cmode_ juno_prefix_mode_list[] = {
    { '~', CSTATUS_OWNER        },
    { '&', CSTATUS_PROTECT      },
    { '@', CSTATUS_OP           },
    { '%', CSTATUS_HALFOP       },
    { '+', CSTATUS_VOICE        },
    { '\0', 0 }
};


struct cmode_ juno_user_mode_list[] = {
 /* { 'p', UF_IMMUNE            }, */       /*  immune from kickban         */
 /* { 'a', UF_ADMIN             }, */       /*  network administrator       */
    { 'i', UF_INVIS             },          /*  invisible user  (juno +i)   */
    { 'o', UF_IRCOP             },          /*  IRC operator    (juno +o)   */
 /* { 'D', UF_DEAF              }, */       /*  deaf user                   */
    { 'S', UF_SERVICE           },          /*  network service (juno +S)   */
    { '\0', 0 }
};

/* check if setting +f is valid */
static bool check_forward(const char *value, channel_t *c, mychan_t *mc, user_t *u, myuser_t *mu)
{
    channel_t *target_c;
    mychan_t *target_mc;
    chanuser_t *target_cu;
    
    /* check channel validity */
    if (!VALID_GLOBAL_CHANNEL_PFX(value) || strlen(value) > 50)
        return false;
    
    if (u == NULL && mu == NULL)
        return true;
    
    /* can't find channel */
    target_c = channel_find(value);
    target_mc = MYCHAN_FROM(target_c);
    if (target_c == NULL && target_mc == NULL)
        return false;
    
    /* target channel exists and has free forward (+F) */
    if (target_c != NULL && target_c->modes & CMODE_FTARGET)
        return true;
    if (target_mc != NULL && target_mc->mlock_on & CMODE_FTARGET)
        return true;
    
    /* the source is a user */
    if (u != NULL)
    {
        /* target channel exists and user has op in it */
        target_cu = chanuser_find(target_c, u);
        if (target_cu != NULL && target_cu->modes & CSTATUS_OP)
            return true;
        
        /* user has set privs in target channel */
        if (chanacs_user_flags(target_mc, u) & CA_SET)
            return true;
        
    }
    else if (mu != NULL)
        if (chanacs_entity_has_flag(target_mc, entity(mu), CA_SET))
            return true;
    
    return false;
}

void _modinit(module_t * m)
{
    MODULE_TRY_REQUEST_DEPENDENCY(m, "protocol/charybdis");

    mode_list        = juno_mode_list;
    user_mode_list   = juno_user_mode_list;
    ignore_mode_list = juno_ignore_mode_list;
    status_mode_list = juno_status_mode_list;
    prefix_mode_list = juno_prefix_mode_list;

    ircd = &juno;

    m->mflags = MODTYPE_CORE;
    pmodule_loaded = true;
}
