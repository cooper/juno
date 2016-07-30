# Channel modes

## Supported
```
no_ext        = [0, 'n']  # no external channel messages         (n)
protect_topic = [0, 't']  # only operators can set the topic     (t)
invite_only   = [0, 'i']  # you must be invited to join          (i)
free_invite   = [0, 'g']  # you do not need op to invite         (g)
free_forward  = [0, 'F']  # you do not need op in forwad channel (F)
oper_only     = [0, 'O']  # you need to be an ircop to join      (O)
moderated     = [0, 'm']  # only voiced and up may speak         (m)
secret        = [0, 's']  # secret channel                       (s)
private       = [0, 'p']  # private channel, hide and no knocks  (p)
ban           = [3, 'b']  # channel ban                          (b)
mute          = [3, 'Z']  # channel mute ban                     (Z)
except        = [3, 'e']  # ban exception                        (e)
invite_except = [3, 'I']  # invite-only exception                (I)
access        = [3, 'A']  # Channel::Access module list mode     (A)
limit         = [2, 'l']  # Channel user limit mode              (l)
forward       = [2, 'f']  # Channel forward mode                 (f)
key           = [5, 'k']  # Channel key mode                     (k)
permanent     = [0, 'P']  # do not destroy channel when empty    (P)
reg_only      = [0, 'r']  # only registered users can join       (r)
ssl_only      = [0, 'S']  # only SSL users can join              (S)
strip_colors  = [0, 'c']  # strip mIRC color codes from messages (c)
owner         = ['q', '~',  2    ] # channel owner               (q)
admin         = ['a', '&',  1    ] # channel administrator       (a)
op            = ['o', '@',  0    ] # channel operator            (o)
halfop        = ['h', '%', -1, 0 ] # channel half-operator       (h)
voice         = ['v', '+', -2    ] # voiced channel member       (v)
```

## Not yet supported
```
join_throttle = [2, 'j'] # limit join frequency N:T             (j)
large_banlist = [0, 'L'] # allow lots of entries on lists       (L)
no_forward    = [0, 'Q'] # do not forward users to this channel (Q)
op_moderated  = [0, 'z'] # send blocked messages to channel ops (z)
no_nicks      = [0, 'N'] # no nick changes                      (N)
admin_only    = [0, 'W'] # only administrators can join         (W)
censor        = [3, 'g'] # censor list                          (g)
```
