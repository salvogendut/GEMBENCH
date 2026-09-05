; GEOBENCH-2.1 GB_PARAMS. HL -> caller-primary 16-byte record, BC = 16.
; A = status (0 OK, 1 bad argument, 2 context, 3 stale, 4 owner, 5 busy,
; 6 unsupported); E = boolean result. No application pointer survives return.
; Serialize before copying: workers can publish/query, but never render.
universal_parameters
                push ix
                ld a,i
                push af
                di
                ld a,(SCHED_LOCK)
                push af
                ld a,1
                ld (SCHED_LOCK),a
                call up_dispatch
                ld d,a
                di
                pop af
                ld (SCHED_LOCK),a
                pop af
                ld a,d
                pop ix
                jp po,up_return
                ei
up_return       ret

up_dispatch
                ld a,b
                or a
                jp nz,up_bad
                ld a,c
                cp 16
                jp nz,up_bad
                call up_span
                jp nc,up_bad
                ld de,up_request
                ldir
                ld ix,up_request
                ld a,(ix+1)
                cp 1
                jp nz,up_unsupported
                ld a,(ix+0)
                dec a
                cp 7
                jp nc,up_unsupported
                ; Unlike focus fallback, the mapped primary must identify the
                ; caller. The existing ownership service validates generation.
                call GB_OWNER
                ld a,e
                or a
                jp z,up_context
                dec a
                ld hl,MSX_APP_CODE_NATIVE
                add a,l
                ld l,a
                ld a,(BANK_CUR)
                cp (hl)
                jp nz,up_context
                ld a,(ix+0)
                cp 3
                jp nc,up_timer
                ld a,(SCHED_CURRENT)
                or a
                jp nz,up_context
                ld a,(ix+0)
                cp 2
                jr z,up_text
                ; Pixel-coordinate endpoints must be inside the live display.
                ld hl,(up_request+2)
                ld de,512
                or a
                sbc hl,de
                jp nc,up_bad
                ld hl,(up_request+6)
                or a
                sbc hl,de
                jp nc,up_bad
                ld hl,(up_request+4)
                ld de,212
                or a
                sbc hl,de
                jp nc,up_bad
                ld hl,(up_request+8)
                or a
                sbc hl,de
                jp nc,up_bad
                ld a,(ix+10)
                cp 4
                jp nc,up_bad
                ld hl,up_request+2
                ld de,GLINE_X0             ; legacy backend is private to MSX
                ld bc,9
                ldir
                call GB_LINE
                jp up_ok

up_text
                ld a,(ix+2)
                cp 128
                jp nc,up_bad
                ld a,(ix+3)
                cp 212
                jp nc,up_bad
                ld a,(ix+4)
                or (ix+5)
                cp 4
                jp nc,up_bad
                ld a,(ix+8)                ; explicit byte length, max 48
                cp 49
                jp nc,up_bad
                or a
                jp z,up_ok
                ld c,a
                ld b,0
                ld hl,(up_request+6)
                call up_span
                jp nc,up_bad
                ld de,up_text_copy
                ldir                       ; copy data BEFORE GB_TEXT maps font
                xor a
                ld (de),a
                ld b,(ix+2)
                ld c,(ix+3)
                ld d,(ix+4)
                ld e,(ix+5)
                ld hl,up_text_copy
                call GB_TEXT
                jp up_ok

up_timer
                cp 6
                jr nz,up_owned_timer
                ld a,(MSX_TIMER_OWNER)
                jp up_boolean
up_owned_timer
                ld hl,(up_request+2)
                ld a,5
                call GB_APP                ; exact live window + implicit owner
                or a
                jr z,up_timer_valid
                inc a                      ; native stale=2/owner=3 -> 3/4
                ld e,0
                ret
up_timer_valid
                ld a,(ix+0)
                cp 3
                jr z,up_publish
                cp 5
                jr z,up_dropped
                cp 7
                jr z,up_cancel
                ld a,(ix+2)
                or #80
                ld hl,MSX_TIMER_OWNER
                cp (hl)
                jr nz,up_ok
                ld a,(MSX_TIMER_GEN)
                cp (ix+3)
                jr nz,up_ok
                jr up_true
up_publish
                ld a,(ix+6)
                or a
                jr z,up_bad
                add a,(ix+4)
                jr c,up_bad
                cp 129
                jr nc,up_bad
                ld a,(ix+7)
                or a
                jr z,up_bad
                add a,(ix+5)
                jr c,up_bad
                cp 213
                jr nc,up_bad
                ld a,(MSX_TIMER_OWNER)
                or a
                jr nz,up_busy
                ld hl,up_request+4
                ld de,MSX_TIMER_RECT
                ld bc,4
                ldir
                ld a,(ix+3)
                ld (MSX_TIMER_GEN),a
                ld a,(ix+2)
                ld (MSX_TIMER_OWNER),a      ; publish complete values last
                jr up_true
up_cancel
                ld a,(MSX_TIMER_GEN)
                cp (ix+3)
                jr nz,up_cancel_drop
                ld a,(MSX_TIMER_OWNER)
                cp (ix+2)                  ; active compositor is not cancelled
                jr nz,up_cancel_drop
                xor a
                ld (MSX_TIMER_OWNER),a
up_cancel_drop
                call up_dropped
                jr up_ok
up_dropped
                ld a,(MSX_TIMER_DROPPED)
                cp (ix+2)
                jr nz,up_ok
                ld a,(MSX_TIMER_DROPPED_GEN)
                cp (ix+3)
                jr nz,up_ok
                xor a
                ld (MSX_TIMER_DROPPED),a
up_true         ld a,1
up_boolean      ld e,0
                or a
                jr z,up_success
                inc e
up_success      xor a
                ret
up_ok           ld e,0
                xor a
                ret
up_bad          ld a,1
                jr up_error
up_context      ld a,2
                jr up_error
up_busy         ld a,5
                jr up_error
up_unsupported  ld a,6
up_error        ld e,0
                ret

; HL/BC preserved; CF iff [HL,HL+BC) lies entirely in #4000..#7EFF.
up_span
                ld a,h
                cp #40
                jr nc,up_span_start
                or a
                ret
up_span_start
                push hl
                add hl,bc
                jr c,up_span_bad
                ld a,h
                cp #7F
                jr c,up_span_good
                jr nz,up_span_bad
                ld a,l
                or a
                jr nz,up_span_bad
up_span_good    pop hl
                scf
                ret
up_span_bad     pop hl
                or a
                ret

up_request      ds 16,0
up_text_copy    ds 49,0
