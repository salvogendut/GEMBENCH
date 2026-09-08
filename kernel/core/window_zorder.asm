; Shared working focus/stack policy (#70); see window_focus_contract.inc.
; --- z-order manager (#148): the ONLY code that mutates CORE_Z_ORDER / CORE_LIVE_WINDOWS. ---------
; Three callers (register/close/raise) used to open-code the compaction; one held
; the slot in C across wm_free_page (which does ld c,a) and dropped the wrong
; window. Centralising it kills that bug class and dedups the loops.
;
; wm_z_append: A = slot -> CORE_Z_ORDER[CORE_LIVE_WINDOWS++] = slot (new z-top).
wm_z_append
                if CORE_Z_PRESERVE_SLOT
                ld    hl,CORE_LIVE_WINDOWS
                ld    e,(hl)                       ; preserve/return A = slot for claimed drops
                inc   (hl)                          ; NWIN++
                ld    d,0
                ld    hl,CORE_Z_ORDER
                add   hl,de                         ; HL = &CORE_Z_ORDER[NWIN]
                ld    (hl),a
                else
                ld    b,a                          ; B = slot
                ld    hl,CORE_LIVE_WINDOWS
                ld    a,(hl)                       ; A = NWIN
                inc   (hl)                          ; NWIN++
                ld    hl,CORE_Z_ORDER
                add   a,l
                ld    l,a                           ; HL = &CORE_Z_ORDER[NWIN]
                ld    (hl),b
                endif
                ret

; wm_z_remove: C = slot -> compact CORE_Z_ORDER dropping slot C, dec NWIN once. Keeps C.
; Clobbers A,B,DE,HL (NOT C - callers may still need the slot).
wm_z_remove
                ld    hl,CORE_Z_ORDER
                ld    de,CORE_Z_ORDER
                ld    a,(CORE_LIVE_WINDOWS)
                ld    b,a
wzr_l           ld    a,(hl)
                cp    c
                jr    z,wzr_skip
                ld    (de),a
                inc   de
wzr_skip        inc   hl
                djnz  wzr_l
                ld    hl,CORE_LIVE_WINDOWS
                dec   (hl)
                ret

; wm_focus_top: CORE_FOCUS_SLOT = CORE_Z_ORDER[NWIN-1] (the live z-top). NWIN>=1 (desktop is [0]).
; The z-top is always alive (the manager keeps CORE_Z_ORDER == the live slots).
wm_focus_top
                ld    a,(CORE_LIVE_WINDOWS)
                dec   a
                ld    hl,CORE_Z_ORDER
                add   a,l
                ld    l,a
                ld    a,(hl)
                ld    (CORE_FOCUS_SLOT),a
                ret
