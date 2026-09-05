; Shared existing visible-region/priority policy (#71).
; Provider obligations: visibility_contract.inc.
                ; A worker always hands control back to slot zero, preserving a
                ; root/compositor turn between compute slices.  From root, choose
                ; owner-aggregated visibility tiers in order: focused, fully
                ; visible, partially visible. Fully occluded visual workers are
                ; parked without destroying their saved snapshot.
                ld    a,(CORE_WORKER_CURRENT)
                or    a
                jr    z,sched_m9_select_worker
                ld    c,0
                VIS_ROOT_FLAGS
                ld    a,(hl)
                and   CORE_WORKER_READY
                cp    CORE_WORKER_READY
                jr    z,VIS_RESTORE_CONTEXT
                jr    VIS_RESUME_CONTEXT

sched_m9_select_worker
                ld    a,CORE_VIS_FOCUSED
                ld    (CORE_REGION_OWNER_MAX),a ; scheduler-private desired tier
sched_m9_tier
                ld    a,(CORE_WORKER_LAST)      ; last worker, 1..CORE_WINDOW_MAX-1
                inc   a
                cp    CORE_WINDOW_MAX
                jr    c,sched_m9_cursor_ready
                ld    a,1
sched_m9_cursor_ready
                ld    c,a
                ld    a,CORE_WINDOW_MAX-1
                ld    (CORE_REGION_SLOT_SCAN),a
sched_m9_candidate
                ld    a,c
                VIS_WINDOW_FLAGS
                ld    a,(hl)
                and   CORE_WORKER_READY
                cp    CORE_WORKER_READY
                jr    nz,sched_m9_next_candidate
                ld    hl,CORE_WORKER_VISIBILITY
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(CORE_REGION_OWNER_MAX)
                cp    (hl)
                jr    z,sched_m9_found
sched_m9_next_candidate
                inc   c
                ld    a,c
                cp    CORE_WINDOW_MAX
                jr    c,sched_m9_count
                ld    c,1
sched_m9_count  ld    hl,CORE_REGION_SLOT_SCAN
                dec   (hl)
                jr    nz,sched_m9_candidate
                ld    hl,CORE_REGION_OWNER_MAX
                dec   (hl)
                jr    nz,sched_m9_tier
                jr    VIS_RESUME_CONTEXT
sched_m9_found  ld    a,c
                ld    (CORE_WORKER_LAST),a
                VIS_WINDOW_FLAGS
                jr    VIS_RESTORE_CONTEXT
