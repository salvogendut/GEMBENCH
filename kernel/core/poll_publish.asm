; Shared MSX production input/root routing; target leaves and state supplied by providers.
                ld    d,0
                ld    a,(in_fire)            ; click edge = fire & !last_fire
                ld    e,a
                ld    a,(poll_lastfire)
                cpl
                and   e
                jr    z,gp_noclick
                set   0,d
gp_noclick
                ld    a,e
                ld    (poll_lastfire),a
                ld    a,(in_quit)
                or    a
                jr    z,gp_noquit
                set   1,d
gp_noquit
                ld    a,(in_fire)            ; bit2 = fire currently held (for drag)
                or    a
                jr    z,gp_nohold
                set   2,d
gp_nohold
                call  POLL_MENU_DISPATCH     ; kernel-owned top-bar click -> app
                ld    a,d
                ld    (POLL_FLAGS),a
                ld    a,(poll_byte)
                ld    (POLL_MX),a
                ld    b,a
                ld    a,(poll_line)
                ld    (POLL_MY),a
                ld    c,a
                ret
