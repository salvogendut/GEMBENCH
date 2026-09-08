; Shared existing visible-region/priority policy (#71).
; Provider obligations: visibility_contract.inc.
; A = window slot. Restore the compositor source damage and start the iterator.
sched_region_begin
                push  af
                xor   a                         ; begin with the primary damage source
                ld    (CORE_COMPOSITOR_SOURCE),a
                ld    hl,CORE_COMPOSITOR_DAMAGE
                ld    de,CORE_CLIP_X
                ld    bc,4
                ldir
                pop   af
                call  sched_region_begin_raw
                ret   nz
                jp    sched_region_advance_source
; Intersect the current damage clip with that window, locate
; it in z-order, then install the first effective visible fragment.  A=0/Z means
; no visible damage; A=1/NZ means a fragment is active.
sched_region_begin_raw
                ld    (CORE_REGION_SLOT),a
                ld    c,a
                ld    a,(CORE_LIVE_WINDOWS)
                or    a
                jr    z,srb_empty
                cp    CORE_WINDOW_MAX+1
                jr    nc,srb_empty
                ld    b,a
                ld    hl,CORE_Z_ORDER
                ld    d,0
srb_find_z
                ld    a,(hl)
                cp    c
                jr    z,srb_found_z
                inc   hl
                inc   d
                djnz  srb_find_z
srb_empty       xor   a
                ret
srb_found_z
                ld    a,d
                ld    (CORE_REGION_Z),a
                ld    a,c
                VIS_WINDOW_RECT
                ld    c,(hl)                  ; window x
                inc   hl
                ld    d,(hl)                  ; window y
                inc   hl
                ld    e,(hl)                  ; window width
                inc   hl
                ld    b,(hl)                  ; window height

                ld    a,(CORE_CLIP_X)           ; left = max(clip.x, window.x)
                cp    c
                jr    nc,srb_left_ready
                ld    a,c
srb_left_ready  ld    (CORE_REGION_LEFT),a
                ld    a,(CORE_CLIP_Y)           ; top = max(clip.y, window.y)
                cp    d
                jr    nc,srb_top_ready
                ld    a,d
srb_top_ready   ld    (CORE_REGION_TOP),a

                ld    a,c                     ; window right
                add   a,e
                ld    e,a
                ld    a,(CORE_CLIP_X)           ; clip right
                ld    c,a
                ld    a,(CORE_CLIP_W)
                add   a,c
                cp    e                       ; right = min(clip right, window right)
                jr    c,srb_right_ready
                ld    a,e
srb_right_ready ld    (CORE_REGION_RIGHT),a

                ld    a,d                     ; window bottom
                add   a,b
                ld    b,a
                ld    a,(CORE_CLIP_Y)           ; clip bottom
                ld    c,a
                ld    a,(CORE_CLIP_H)
                add   a,c
                cp    b                       ; bottom = min(clip bottom, window bottom)
                jr    c,srb_bottom_ready
                ld    a,b
srb_bottom_ready
                ld    (CORE_REGION_BOTTOM),a
                ld    hl,CORE_REGION_TOP
                cp    (hl)
                jr    c,srb_empty
                jr    z,srb_empty
                ld    a,(CORE_REGION_RIGHT)
                ld    hl,CORE_REGION_LEFT
                cp    (hl)
                jr    c,srb_empty
                jr    z,srb_empty

                ld    a,(CORE_REGION_TOP)
                ld    (CORE_REGION_Y),a
                ld    (CORE_REGION_BAND_END),a ; force preparation of the first band
                ld    a,(CORE_REGION_LEFT)
                ld    (CORE_REGION_X),a
                xor   a
                ld    (CORE_REGION_COVERED),a
                ld    (CORE_REGION_FRAGMENT_COUNT),a
                jr    sched_region_seek

; Continue an active iterator.  The original damage rectangle has already been
; folded into the fixed base bounds, so each call only installs the next clip.
sched_region_next
                call  sched_region_seek
                ret   nz
sched_region_advance_source
                ld    a,(CORE_COMPOSITOR_EXTRA_ACTIVE)
                or    a
                ret   z
                ld    a,(CORE_COMPOSITOR_SOURCE)
                or    a
                jr    z,sras_load_extra
                xor   a
                ret
sras_load_extra
                inc   a
                ld    (CORE_COMPOSITOR_SOURCE),a
                ld    hl,CORE_COMPOSITOR_EXTRA
                ld    de,CORE_CLIP_X
                ld    bc,4
                ldir
                ld    a,(CORE_REGION_SLOT)
                jp    sched_region_begin_raw

; Direct component-damage visibility tests do not participate in a pending
; two-rectangle move pass.
sched_region_test
                push  af
                xor   a
                ld    (CORE_COMPOSITOR_SOURCE),a
                pop   af
                jp    sched_region_begin_raw

sched_region_seek
srs_band
                ld    a,(CORE_REGION_Y)
                ld    hl,CORE_REGION_BOTTOM
                cp    (hl)
                jp    nc,srb_empty
                ld    hl,CORE_REGION_BAND_END
                cp    (hl)
                call  nc,sched_region_prepare_band

                ld    a,(CORE_REGION_X)
                ld    c,a
srs_skip_covered
                ld    a,(CORE_REGION_RIGHT)
                cp    c
                jr    z,srs_advance_band
                jr    c,srs_advance_band
                ld    a,c
                call  sched_region_is_covered
                or    a
                jr    z,srs_run_start
                inc   c
                ld    a,c
                ld    (CORE_REGION_X),a
                jr    srs_skip_covered

srs_run_start
                ld    a,c
                ld    (CORE_CLIP_X),a            ; also serves as run-left scratch
                inc   c
srs_extend_run
                ld    a,(CORE_REGION_RIGHT)
                cp    c
                jr    z,srs_emit
                jr    c,srs_emit
                ld    a,c
                call  sched_region_is_covered
                or    a
                jr    nz,srs_emit
                inc   c
                jr    srs_extend_run

srs_emit
                ld    a,c
                ld    (CORE_REGION_X),a
                ld    hl,CORE_CLIP_X
                sub   (hl)
                ld    (CORE_CLIP_W),a
                ld    a,(CORE_REGION_Y)
                ld    (CORE_CLIP_Y),a
                ld    c,a
                ld    a,(CORE_REGION_BAND_END)
                sub   c
                ld    (CORE_CLIP_H),a
                ld    hl,CORE_REGION_FRAGMENT_COUNT
                inc   (hl)
                ld    a,1
                or    a
                ret

srs_advance_band
                ld    a,(CORE_REGION_BAND_END)
                ld    (CORE_REGION_Y),a
                ld    a,(CORE_REGION_LEFT)
                ld    (CORE_REGION_X),a
                jr    srs_band

; Choose the next vertical edge among all higher windows whose rectangles touch
; the base horizontally.  An actual two-dimensional intersection also marks the
; surface partial; this flag is consumed by the visibility classifier.
sched_region_prepare_band
                ld    a,(CORE_REGION_BOTTOM)
                ld    (CORE_REGION_BAND_END),a
                ld    a,(CORE_COMPOSITOR_SOURCE)
                or    a
                jr    z,srp_begin_windows
                ; The second source is the old window rectangle. Treat the
                ; primary/new rectangle as an opaque pseudo-cover so overlap is
                ; emitted only once. Prime SCAN_Z one entry early: the shared
                ; edge tail increments it before beginning real higher windows.
                ld    a,(CORE_REGION_Z)
                ld    (CORE_REGION_SCAN_Z),a
                ld    hl,CORE_COMPOSITOR_DAMAGE
                ld    c,(hl)                   ; primary left
                inc   hl
                ld    d,(hl)                   ; primary top
                inc   hl
                ld    a,c
                add   a,(hl)
                ld    e,a                      ; primary right
                inc   hl
                ld    a,d
                add   a,(hl)
                ld    b,a                      ; primary bottom
                ld    a,(CORE_REGION_LEFT)
                cp    e
                jr    nc,srp_next_cover
                ld    a,c
                ld    hl,CORE_REGION_RIGHT
                cp    (hl)
                jr    nc,srp_next_cover
                ld    a,(CORE_REGION_TOP)
                cp    b
                jr    nc,srp_edges
                ld    a,d
                ld    hl,CORE_REGION_BOTTOM
                cp    (hl)
                jr    nc,srp_edges
                jr    srp_mark_and_edges
srp_begin_windows
                ld    a,(CORE_REGION_Z)
                inc   a
                ld    (CORE_REGION_SCAN_Z),a
srp_cover_loop
                ld    a,(CORE_REGION_SCAN_Z)
                ld    hl,CORE_LIVE_WINDOWS
                cp    (hl)
                ret   nc
                ld    hl,CORE_Z_ORDER
                add   a,l
                ld    l,a
                ld    a,(hl)
                VIS_WINDOW_RECT
                ld    c,(hl)                   ; cover left
                inc   hl
                ld    d,(hl)                   ; cover top
                inc   hl
                ld    a,c
                add   a,(hl)
                ld    e,a                      ; cover right
                inc   hl
                ld    a,d
                add   a,(hl)
                ld    b,a                      ; cover bottom

                ld    a,(CORE_REGION_LEFT)      ; horizontal intersection?
                cp    e
                jr    nc,srp_next_cover
                ld    a,c
                ld    hl,CORE_REGION_RIGHT
                cp    (hl)
                jr    nc,srp_next_cover
                ld    a,(CORE_REGION_TOP)       ; vertical intersection with base?
                cp    b
                jr    nc,srp_edges
                ld    a,d
                ld    hl,CORE_REGION_BOTTOM
                cp    (hl)
                jr    nc,srp_edges
srp_mark_and_edges
                ld    a,1
                ld    (CORE_REGION_COVERED),a

srp_edges       ld    a,(CORE_REGION_Y)         ; cover top is a future band edge?
                cp    d
                jr    nc,srp_bottom_edge
                ld    a,d
                ld    hl,CORE_REGION_BAND_END
                cp    (hl)
                jr    nc,srp_bottom_edge
                ld    (hl),a
srp_bottom_edge ld    a,(CORE_REGION_Y)         ; cover bottom is a future edge?
                cp    b
                jr    nc,srp_next_cover
                ld    a,b
                ld    hl,CORE_REGION_BAND_END
                cp    (hl)
                jr    nc,srp_next_cover
                ld    (hl),a
srp_next_cover  ld    hl,CORE_REGION_SCAN_Z
                inc   (hl)
                jr    srp_cover_loop

; A = x column. Return A=1/NZ if any higher opaque window contains (x,band_y),
; otherwise A=0/Z.  CORE_Z_ORDER contains live slots only.
sched_region_is_covered
                push  bc                       ; caller keeps its x cursor in C
                ld    (CORE_REGION_TEST_X),a
                ld    a,(CORE_COMPOSITOR_SOURCE)
                or    a
                jr    z,sric_begin_windows
                ld    hl,CORE_COMPOSITOR_DAMAGE
                ld    a,(CORE_REGION_TEST_X)
                cp    (hl)                     ; x < primary left
                jr    c,sric_begin_windows
                ld    c,(hl)
                inc   hl
                ld    d,(hl)                   ; primary top
                inc   hl
                ld    a,c
                add   a,(hl)                   ; primary right
                ld    c,a
                ld    a,(CORE_REGION_TEST_X)
                cp    c
                jr    nc,sric_begin_windows
                inc   hl
                ld    a,(hl)                   ; primary height
                add   a,d                      ; primary bottom
                ld    c,a
                ld    a,(CORE_REGION_Y)
                cp    d
                jr    c,sric_begin_windows
                cp    c
                jr    nc,sric_begin_windows
                pop   bc
                ld    a,1
                or    a
                ret
sric_begin_windows
                ld    a,(CORE_REGION_Z)
                inc   a
                ld    (CORE_REGION_SCAN_Z),a
sric_loop
                ld    a,(CORE_REGION_SCAN_Z)
                ld    hl,CORE_LIVE_WINDOWS
                cp    (hl)
                jr    nc,sric_clear
                ld    hl,CORE_Z_ORDER
                add   a,l
                ld    l,a
                ld    a,(hl)
                VIS_WINDOW_RECT
                ld    c,(hl)                   ; left
                inc   hl
                ld    d,(hl)                   ; top
                inc   hl
                ld    a,c
                add   a,(hl)
                ld    e,a                      ; right
                inc   hl
                ld    a,d
                add   a,(hl)
                ld    b,a                      ; bottom
                ld    a,(CORE_REGION_TEST_X)
                cp    c
                jr    c,sric_next
                cp    e
                jr    nc,sric_next
                ld    a,(CORE_REGION_Y)
                cp    d
                jr    c,sric_next
                cp    b
                jr    nc,sric_next
                pop   bc
                ld    a,1
                or    a
                ret
sric_next       ld    hl,CORE_REGION_SCAN_Z
                inc   (hl)
                jr    sric_loop
sric_clear      pop   bc
                xor   a
                ret
