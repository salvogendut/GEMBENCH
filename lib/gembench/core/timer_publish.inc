;; void gb_timer_damage(u8 x, u8 y, u8 w, u8 h)
;; SDCC: x=A, y=L, packed w/h word at SP+2. Do not use the shared gblib sv_ret:
;; a worker can be preempted while the root task is using another trampoline.
_gb_timer_damage::
        push    ix
        ld      ix, #0
        add     ix, sp
        ld      c, a
        ld      a, (CORE_TIMER_FULLSCREEN)
        or      a
        jr      nz, timer_done
        ld      a, (CORE_TIMER_OWNER)
        or      a
        jr      nz, timer_done
        ld      a, c
        ld      (CORE_TIMER_RECT+0), a
        ld      a, l
        ld      (CORE_TIMER_RECT+1), a
        ld      a, 4(ix)
        or      a
        jr      z, timer_bad_rect
        ld      (CORE_TIMER_RECT+2), a
        ld      a, 5(ix)
        or      a
        jr      z, timer_bad_rect
        ld      (CORE_TIMER_RECT+3), a
        ld      a, (CORE_TIMER_CURRENT)
        cp      #CORE_TIMER_WINDOW_MAX
        jr      nc, timer_bad_rect
        ld      b, a
        ld      hl, #CORE_TIMER_WIN_GEN
        add     a, l
        ld      l, a
        ld      a, (hl)
        ld      (CORE_TIMER_GEN), a
        ld      a, b
        inc     a
        ld      (CORE_TIMER_OWNER), a     ; publish generation-tagged owner last
timer_bad_rect:
timer_done:
        pop     ix
        pop     hl                      ; callee-cleans packed w/h word
        inc     sp
        inc     sp
        jp      (hl)
