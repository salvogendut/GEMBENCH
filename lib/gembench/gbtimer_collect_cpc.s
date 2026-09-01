;; CPC adapter for the shared background-timer collector contract.
;; The algorithm matches gbtimer_collect.s; only owner/generation tables and
;; the fixed scheduler entry differ from the MSX2 memory map.
        .module gbtimer_collect_cpc
        .globl  _gb_timer_collect

GB_TIMER_DROPPED = 0x3FF8
GB_TIMER_OWNER   = 0x3FF9
GB_TIMER_RECT    = 0x3FFA
GB_TIMER_GEN     = 0x3FFE
WM_FULLSCREEN    = 0x130A
WM_TABLE         = 0x1352
WM_ESZ           = 25
WM_FLAGS         = 13
CPC_WIN_GEN      = 0x3E9F
CPC_VISIBILITY   = 0x3EC0
GB_RESTPAR       = 0x8057
GB_WMDAMAGE      = 0x80B4
GB_DAMAGE_VISIBLE = 0x3015

        .area   _CODE

_gb_timer_collect::
        ld      a, (GB_TIMER_OWNER)
        or      a
        ret     z
        ret     m
        dec     a
        cp      #8
        jr      nc, timer_stale
        ld      c, a
        ld      hl, #CPC_WIN_GEN
        add     a, l
        ld      l, a
        ld      a, (GB_TIMER_GEN)
        cp      (hl)
        jr      nz, timer_stale

        ld      a, c                    ; validate the live WM slot
        ld      hl, #WM_TABLE+WM_FLAGS
        or      a
        jr      z, timer_flags
        ld      b, a
        ld      de, #WM_ESZ
timer_entry:
        add     hl, de
        djnz    timer_entry
timer_flags:
        bit     0, (hl)
        jr      z, timer_stale

        ld      hl, #CPC_VISIBILITY
        ld      a, c
        add     a, l
        ld      l, a
        ld      a, (hl)
        or      a
        jr      z, timer_occluded
        ld      a, (WM_FULLSCREEN)
        or      a
        jr      nz, timer_stale
        ld      bc, (GB_TIMER_RECT+0)
        ld      de, (GB_TIMER_RECT+2)
        call    GB_WMDAMAGE
        ld      a, (GB_TIMER_OWNER)
        dec     a
        call    GB_DAMAGE_VISIBLE
        or      a
        jr      z, timer_occluded
        ld      a, (GB_TIMER_OWNER)
        or      #0x80
        ld      (GB_TIMER_OWNER), a
        ld      bc, (GB_TIMER_RECT+0)
        ld      de, (GB_TIMER_RECT+2)
        call    GB_WMDAMAGE
        call    GB_RESTPAR
        xor     a
        ld      (GB_TIMER_OWNER), a
        ret
timer_occluded:
        ld      a, (GB_TIMER_OWNER)
        ld      (GB_TIMER_DROPPED), a
timer_stale:
        xor     a
        ld      (GB_TIMER_OWNER), a
        ret
