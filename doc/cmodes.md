# Channel modes

## Supported
```
no_ext        = [ mode_normal, 'n' ]  # no external channel messages         (n)
protect_topic = [ mode_normal, 't' ]  # only operators can set the topic     (t)
invite_only   = [ mode_normal, 'i' ]  # you must be invited to join          (i)
free_invite   = [ mode_normal, 'g' ]  # you do not need op to invite         (g)
free_forward  = [ mode_normal, 'F' ]  # you do not need op in forwad channel (F)
oper_only     = [ mode_normal, 'O' ]  # you need to be an ircop to join      (O)
moderated     = [ mode_normal, 'm' ]  # only voiced and up may speak         (m)
secret        = [ mode_normal, 's' ]  # secret channel                       (s)
private       = [ mode_normal, 'p' ]  # private channel, hide and no knocks  (p)
ban           = [ mode_list,   'b' ]  # channel ban                          (b)
mute          = [ mode_list,   'Z' ]  # channel mute ban                     (Z)
except        = [ mode_list,   'e' ]  # ban exception                        (e)
invite_except = [ mode_list,   'I' ]  # invite-only exception                (I)
access        = [ mode_list,   'A' ]  # Channel::Access module list mode     (A)
limit         = [ mode_pset,   'l' ]  # Channel user limit mode              (l)
forward       = [ mode_pset,   'f' ]  # Channel forward mode                 (f)
key           = [ mode_key,    'k' ]  # Channel key mode                     (k)
permanent     = [ mode_normal, 'P' ]  # do not destroy channel when empty    (P)
reg_only      = [ mode_normal, 'r' ]  # only registered users can join       (r)
ssl_only      = [ mode_normal, 'S' ]  # only SSL users can join              (S)
strip_colors  = [ mode_normal, 'c' ]  # strip mIRC color codes from messages (c)
op_moderated  = [ mode_normal, 'z' ]  # send blocked messages to channel ops (z)
join_throttle = [ mode_pset,   'j' ]  # limit join frequency N:T             (j)
no_forward    = [ mode_normal, 'Q' ]  # do not forward users to this channel (Q)
large_banlist = [ mode_normal, 'L' ]  # allow lots of entries on lists       (L)
owner  = [ 'q', '~',  2    ]          # channel owner                        (q)
admin  = [ 'a', '&',  1    ]          # channel administrator                (a)
op     = [ 'o', '@',  0    ]          # channel operator                     (o)
halfop = [ 'h', '%', -1, 0 ]          # channel half-operator                (h)
voice  = [ 'v', '+', -2    ]          # voiced channel member                (v)
```

## Not yet supported
```
no_nicks    = [ mode_normal, 'N' ]
admin_only  = [ mode_normal, 'W' ]
censor      = [ mode_list,   'g' ]

```
