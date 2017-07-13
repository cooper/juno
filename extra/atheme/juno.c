/*
 * Copyright (c) 2003-2004 E. Will et al.
 * Copyright (c) 2005-2008 Atheme Development Group
 * Copyright (c) 2008-2010 ShadowIRCd Development Group
 * Copyright (c) 2013 PonyChat Development Group
 * Copyright (c) 2017 Mitchell Cooper
 *
 * Rights to this code are documented in LICENSE.
 *
 * This file contains protocol support for juno.
 *
 */

#include "atheme.h"
#include "uplink.h"
#include "pmodule.h"

#define   CMODE_NOCOLOR         0x00001000   /* hyperion     +c     strip color codes       */
#define   CMODE_REGONLY         0x00002000   /*  hyperion    +r     register users only     */
#define   CMODE_OPMOD           0x00004000   /*  hyperion    +z     ops get rejected msgs   */
#define   CMODE_FINVITE         0x00008000   /*  hyperion    +g     free invite             */
#define   CMODE_EXLIMIT         0x00010000   /*  charybdis   +L     unlimited +beI etc.     */
#define   CMODE_PERM            0x00020000   /*  charybdis   +P     permanent               */
#define   CMODE_FTARGET         0x00040000   /*  charybdis   +F     free forward target     */
#define   CMODE_DISFWD          0x00080000   /*  charybdis   +Q     disable forwarding      */
#define   CMODE_OPERONLY        0x00800000   /*  shadowircd  +O     opers only allowed      */
#define   CMODE_SSLONLY         0x01000000   /*  shadowircd  +S     SSL users only allowed  */
#define   CMODE_STRIP          0x200000000   /*  unreal      +S     strip color codes       */

/* Compatibility stuff */

#ifdef PROTOCOL_ELEMENTAL_IRCD
    #define PROTOCOL_JUNO PROTOCOL_ELEMENTAL_IRCD
#else
    #define PROTOCOL_JUNO PROTOCOL_SHADOWIRCD
#endif

#ifndef MYCHAN_FROM
    #define MYCHAN_FROM(x) mychan_from(x)
#endif

/* Protocol definition */

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
    .oper_only_modes    = CMODE_OPERONLY | CMODE_PERM | CMODE_EXLIMIT,
    .owner_mode         = CSTATUS_OWNER,
    .protect_mode       = CSTATUS_PROTECT,
    .halfops_mode       = CSTATUS_HALFOP,
    .owner_mchar        = "+u",
    .protect_mchar      = "+a",
    .halfops_mchar      = "+h",
    .type               = PROTOCOL_JUNO,
    .perm_mode          = CMODE_PERM,
    .oimmune_mode       = 0,
    .ban_like_modes     = "AIbeq",
    .except_mchar       = 'e',
    .invex_mchar        = 'I',
    .flags              = IRCD_CIDR_BANS | IRCD_HOLDNICK
};

struct cmode_ juno_mode_list[] = {
    { 'i', CMODE_INVITE         },      /* invite only                              */
    { 'm', CMODE_MOD            },      /* moderated                                */
    { 'n', CMODE_NOEXT          },      /* block external messages                  */
    { 'p', CMODE_PRIV           },      /* private                                  */
    { 's', CMODE_SEC            },      /* secret                                   */
    { 't', CMODE_TOPIC          },      /* only ops can set the topic               */
    { 'c', CMODE_NOCOLOR        },      /* block color codes                        */
    { 'r', CMODE_REGONLY        },      /* only registered users allowed            */
    { 'z', CMODE_OPMOD          },      /* ops can see rejected messages            */
    { 'g', CMODE_FINVITE        },      /* free invite, non-ops can invite          */
    { 'L', CMODE_EXLIMIT        },      /* unlimited ban-type mode entries          */
    { 'P', CMODE_PERM           },      /* permanent                                */
    { 'F', CMODE_FTARGET        },      /* free target, non-ops can forward here    */
    { 'Q', CMODE_DISFWD         },      /* disable channel forwarding               */
    { 'O', CMODE_OPERONLY       },      /* only IRC operators allowed               */
    { 'S', CMODE_SSLONLY        },      /* only SSL clients allowed                 */
    { '\0', 0 }
};

static bool check_forward(const char *, channel_t *, mychan_t *, user_t *, myuser_t *);
static bool check_jointhrottle(const char *value, channel_t *c, mychan_t *mc, user_t *u, myuser_t *mu);

struct extmode juno_ignore_mode_list[] = {
    { 'f', check_forward        },
    { 'j', check_jointhrottle   },
    { '\0', 0 }
};

struct cmode_ juno_status_mode_list[] = {
    { 'u', CSTATUS_OWNER        },
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
    { 'i', UF_INVIS             },          /*  invisible user  (juno +i)   */
    { 'o', UF_IRCOP             },          /*  IRC operator    (juno +o)   */
    { 'D', UF_DEAF              },          /*  deaf user                   */
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

/* check if setting +j is valid */
static bool check_jointhrottle(const char *value, channel_t *c, mychan_t *mc, user_t *u, myuser_t *mu)
{
	const char *p, *arg2;

	p = value, arg2 = NULL;
	while (*p != '\0')
	{
		if (*p == ':')
		{
			if (arg2 != NULL)
				return false;
			arg2 = p + 1;
		}
		else if (!isdigit((unsigned char)*p))
			return false;
		p++;
	}
	if (arg2 == NULL)
		return false;
	if (p - arg2 > 10 || arg2 - value - 1 > 10 || !atoi(value) || !atoi(arg2))
		return false;
	return true;
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
