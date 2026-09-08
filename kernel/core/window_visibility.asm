; Shared existing visible-region/priority policy (#71).
; Provider obligations: visibility_contract.inc.
; Reclassify all surfaces after stacking/geometry damage.  The ordinary table
; records surface visibility.  The scheduler table starts as a copy and then
; folds all windows of a multi-window application into its designated worker
; slot, so PAINT-like ownership has one scheduling rank.
sched_visibility_refresh
                ld    hl,CORE_CLIP_X
                ld    de,CORE_REGION_SAVED_CLIP
                ld    bc,4
                ldir
                xor   a
                ld    (CORE_CLIP_X),a
                ld    (CORE_CLIP_Y),a
                ld    a,CORE_SCREEN_COLS        ; provider's native WM extent
                ld    (CORE_CLIP_W),a
                ld    a,CORE_SCREEN_LINES
                ld    (CORE_CLIP_H),a
                xor   a
                ld    hl,CORE_SURFACE_VISIBILITY
                ld    de,CORE_SURFACE_VISIBILITY+1
                ld    bc,CORE_WINDOW_MAX*2-1
                ld    (hl),a
                ldir
                ld    (CORE_REGION_REFRESH_Z),a
svr_surface_loop
                ld    a,(CORE_REGION_REFRESH_Z)
                ld    hl,CORE_LIVE_WINDOWS
                cp    (hl)
                jr    nc,svr_aggregate
                ld    hl,CORE_Z_ORDER
                add   a,l
                ld    l,a
                ld    a,(hl)                   ; slot
                ld    c,a
                ld    a,(CORE_FOCUS_SLOT)
                cp    c
                ld    b,CORE_VIS_FOCUSED
                jr    z,svr_store_surface
                xor   a                        ; each classification starts from
                ld    (CORE_CLIP_X),a            ; the complete screen, not the first
                ld    (CORE_CLIP_Y),a            ; fragment emitted for the prior slot
                ld    a,CORE_SCREEN_COLS
                ld    (CORE_CLIP_W),a
                ld    a,CORE_SCREEN_LINES
                ld    (CORE_CLIP_H),a
                ld    a,c
                call  sched_region_test
                ld    b,CORE_VIS_HIDDEN
                or    a
                jr    z,svr_reload_surface_slot
                ld    b,CORE_VIS_FULL
                ld    a,(CORE_REGION_COVERED)
                or    a
                jr    z,svr_reload_surface_slot
                ld    b,CORE_VIS_PARTIAL
svr_reload_surface_slot
                ld    a,(CORE_REGION_SLOT)      ; iterator scratch freely uses C
                ld    c,a
svr_store_surface
                ld    hl,CORE_SURFACE_VISIBILITY
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),b
                ld    hl,CORE_WORKER_VISIBILITY
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),b
                ld    hl,CORE_REGION_REFRESH_Z
                inc   (hl)
                jr    svr_surface_loop

svr_aggregate
                xor   a
                ld    (CORE_REGION_OWNER_INDEX),a
svr_owner_loop
                ld    a,(CORE_REGION_OWNER_INDEX)
                cp    CORE_OWNER_CAPACITY
                jr    nc,svr_restore_clip
                ld    hl,CORE_APP_WORKER_WIN
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a                         ; slot zero is the root, never an app worker
                jr    z,svr_next_owner
                cp    CORE_WINDOW_MAX
                jr    nc,svr_next_owner
                ld    (CORE_REGION_WORKER_SLOT),a
                ld    a,(CORE_REGION_OWNER_INDEX)
                inc   a
                ld    (CORE_REGION_OWNER_ID),a
                xor   a
                ld    (CORE_REGION_OWNER_MAX),a
                ld    (CORE_REGION_SLOT_SCAN),a
svr_owner_windows
                ld    a,(CORE_REGION_SLOT_SCAN)
                cp    CORE_WINDOW_MAX
                jr    nc,svr_owner_store
                ld    c,a
                ld    hl,CORE_WIN_OWNER
                add   a,l
                ld    l,a
                ld    a,(CORE_REGION_OWNER_ID)
                cp    (hl)
                jr    nz,svr_owner_window_next
                ld    hl,CORE_SURFACE_VISIBILITY
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(CORE_REGION_OWNER_MAX)
                cp    (hl)
                jr    nc,svr_owner_window_next
                ld    a,(hl)
                ld    (CORE_REGION_OWNER_MAX),a
svr_owner_window_next
                ld    hl,CORE_REGION_SLOT_SCAN
                inc   (hl)
                jr    svr_owner_windows
svr_owner_store ld    a,(CORE_REGION_WORKER_SLOT)
                ld    hl,CORE_WORKER_VISIBILITY
                add   a,l
                ld    l,a
                ld    a,(CORE_REGION_OWNER_MAX)
                ld    (hl),a
svr_next_owner  ld    hl,CORE_REGION_OWNER_INDEX
                inc   (hl)
                jr    svr_owner_loop

svr_restore_clip
                ld    hl,CORE_REGION_SAVED_CLIP
                ld    de,CORE_CLIP_X
                ld    bc,4
                ldir
                ret
