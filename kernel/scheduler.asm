; kernel/scheduler.asm - fixed low-RAM scheduler image (issue #477).
;
; This file is assembled by scheduler_image.asm, not included in GBKERN. The
; preemptive desktop carries the resulting image in its app page and copies it
; to SCHED_BASE before entering the window-manager loop. CPC/PCW reserve
; #3000-#3DFF; MSX uses #C900-#CEFF in fixed page-3 RAM.
;
; An active task continues to use the platform's existing fixed stack.  On a
; switch, only BOOT_SP-SP live bytes are copied into the owning app bank.  This
; avoids eight fixed-RAM stacks and keeps the stack visible while kernel APIs
; temporarily map PAGE_DATA over #4000-#7FFF.

TASK_SNAPSHOT   equ   #7F00        ; top 256 bytes of a participating app bank
TASK_STACK_LEN  equ   TASK_SNAPSHOT ; byte: saved stack length
TASK_STACK_DATA equ   TASK_SNAPSHOT+1
TASK_STACK_CAP  equ   255          ; includes interrupt-saved Z80 context
TASK_STACK_SIZE equ   256          ; length byte plus TASK_STACK_CAP payload
                ifdef PLATFORM_PCW
VISIBLE_COMPOSITOR equ 0
                else
VISIBLE_COMPOSITOR equ 1           ; shared MSX2/CPC exact-region policy
                endif
                ifdef PLATFORM_MSX
SCHED_QUANTUM_TICKS equ 2          ; 25/30 Hz slices from the 50/60 Hz MSX IRQ
                else
SCHED_QUANTUM_TICKS equ 6          ; six 300 Hz CPC firmware ticks per 50 Hz slice
                endif

; #1450..#1480 is write-before-read kernel scratch. A real switch may use it
; as a tiny emergency stack only after SCHED_LOCK reaches zero. Interrupts
; arriving while kernel scratch is live return without switching.
SCHED_TMP_BOTTOM equ #1450
SCHED_TMP_TOP    equ   #1481

                org   SCHED_BASE
                jp    sched_init_impl
                jp    sched_yield
                jp    k_task_enable
                jp    sched_irq_uninstall
                if VISIBLE_COMPOSITOR
                jp    sched_compositor_prepare
                jp    sched_region_begin
                jp    sched_region_next
                jp    sched_region_test        ; test current clip for one source surface
                ifdef PLATFORM_CPC
                jp    sched_focus_damage
                jp    sched_damage_axis
                jp    sched_clip_full
                jp    sched_set_clip
                jp    sched_wm_entry
                jp    sched_wm_damage
                jp    sched_cpc_kind_register
                jp    sched_cpc_owner_current
                jp    sched_cpc_shell
                jp    sched_cpc_defer
                jp    sched_cpc_defer_dispatch
                jp    sched_cpc_window_current
                jp    sched_cpc_gbap4_gate_load
                endif
                endif

sched_init_impl
                xor   a
                ld    hl,SCHED_LOCK
                ld    de,SCHED_LOCK+1
                ld    bc,7
                ld    (hl),a
                ldir                          ; clear all eight scheduler bytes
                ld    a,#FF
                ld    (SCHED_CURRENT),a
                ld    a,1
                ld    (SCHED_LOCK),a          ; kernel owns execution at boot
                if PREEMPTIVE_CONTEXT
                ld    a,SCHED_QUANTUM_TICKS
                ld    (SCHED_QUANTUM),a
                if PREEMPTIVE_TIMER
                call  sched_irq_install       ; one install for the scheduler lifetime
                endif
                endif
                ret

                if PREEMPTIVE_CONTEXT
; sched_switch_context: switch from one fully saved app context to the next
; runnable WM slot. The interrupt wrapper must have pushed, in order:
;
;   AF, BC, DE, HL, IX, IY, AF', BC', DE', HL'
;
; and CALLed this routine. The CALL return address is intentionally part of the
; copied stack. Restoring another snapshot and RET therefore continues in that
; task's copy of the yield/interrupt wrapper, which restores its registers and
; either returns from a yield or completes the pending firmware tick. I and the
; interrupt mode are kernel-owned, not task-local.
;
; Preconditions: SCHED_LOCK=0, SCHED_CURRENT names a runnable slot, the current
; app bank is mapped, and participating app layouts reserve #7F00-#7FFF.
; Clobbers every register (the wrapper has already saved them).
sched_switch_context
                ld    hl,0
                add   hl,sp
                ex    de,hl                   ; DE = old SP
                ld    hl,(BOOT_SP)
                or    a
                sbc   hl,de                   ; HL = live fixed-stack bytes
                ld    a,h
                or    a
                jp    nz,sched_switch_fault
                ld    a,l                     ; zero is impossible (CALL is live)
                or    a
                jp    z,sched_switch_fault
                ld    hl,SCHED_STACK_MAX      ; always retain the observed high-water mark
                cp    (hl)
                jr    c,sched_stack_sampled
                ld    (hl),a
                ifdef PLATFORM_MSX
                ifdef GEMBENCH_BASELINE
                if GEMBENCH_BASELINE
                ld    (MSX_BASELINE_STACK_MAX),a
                endif
                endif
                endif
sched_stack_sampled

                ld    sp,SCHED_TMP_TOP        ; kernel scratch is dead while unlocked
                push  de                      ; old SP, below scheduler call frames
                ld    (TASK_STACK_LEN),a      ; current app bank is still mapped
                ld    c,a
                ld    b,0
                ex    de,hl                   ; HL = old SP
                ld    de,TASK_STACK_DATA
                ldir

                if VISIBLE_COMPOSITOR
                ; A worker always hands control back to slot zero, preserving a
                ; root/compositor turn between compute slices.  From root, choose
                ; owner-aggregated visibility tiers in order: focused, fully
                ; visible, partially visible. Fully occluded visual workers are
                ; parked without destroying their saved snapshot.
                ld    a,(SCHED_CURRENT)
                or    a
                jr    z,sched_m9_select_worker
                ld    c,0
                ld    hl,WM_TABLE+WM_FR_FLAGS
                ld    a,(hl)
                and   WM_TASK_RUNNABLE|1
                cp    WM_TASK_RUNNABLE|1
                jr    z,sched_restore_slot
                jr    sched_resume_old

sched_m9_select_worker
                ld    a,WM_VIS_FOCUSED
                ld    (MSX_REGION_OWNER_MAX),a ; scheduler-private desired tier
sched_m9_tier
                ld    a,(SCHED_FLAGS)          ; last worker selected, 1..7
                inc   a
                cp    WM_MAXWIN
                jr    c,sched_m9_cursor_ready
                ld    a,1
sched_m9_cursor_ready
                ld    c,a
                ld    a,WM_MAXWIN-1
                ld    (MSX_REGION_SLOT_SCAN),a
sched_m9_candidate
                ld    a,c
                call  sched_wm_entry
                ld    de,WM_FR_FLAGS
                add   hl,de
                ld    a,(hl)
                and   WM_TASK_RUNNABLE|1
                cp    WM_TASK_RUNNABLE|1
                jr    nz,sched_m9_next_candidate
                ld    hl,MSX_TASK_VISIBILITY
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(MSX_REGION_OWNER_MAX)
                cp    (hl)
                jr    z,sched_m9_found
sched_m9_next_candidate
                inc   c
                ld    a,c
                cp    WM_MAXWIN
                jr    c,sched_m9_count
                ld    c,1
sched_m9_count  ld    hl,MSX_REGION_SLOT_SCAN
                dec   (hl)
                jr    nz,sched_m9_candidate
                ld    hl,MSX_REGION_OWNER_MAX
                dec   (hl)
                jr    nz,sched_m9_tier
                jr    sched_resume_old
sched_m9_found  ld    a,c
                ld    (SCHED_FLAGS),a
                call  sched_wm_entry
                ld    de,WM_FR_FLAGS
                add   hl,de
                jr    sched_restore_slot

                ; No eligible peer: the original fixed stack was not
                ; overwritten, so resume it without copying back.
sched_resume_old
                pop   hl
                ld    sp,hl
                ret

                else
                ; Search the other seven slots round-robin. A runnable flag is
                ; set only after its initial snapshot has been constructed. Build
                ; the first entry pointer once and then advance it directly; the
                ; old wm_entry-per-candidate loop was needlessly quadratic.
                ld    a,(SCHED_CURRENT)
                inc   a
                and   WM_MAXWIN-1             ; WM_MAXWIN is deliberately a power of two
                ld    c,a
                call  sched_wm_entry
                ld    de,WM_FR_FLAGS
                add   hl,de
                ld    b,WM_MAXWIN-1
sched_next_slot
                ld    a,(hl)
                and   WM_TASK_RUNNABLE|1      ; both alive and runnable must be set
                cp    WM_TASK_RUNNABLE|1
                jr    z,sched_restore_slot
                inc   c
                ld    a,c
                cp    WM_MAXWIN
                jr    nc,sched_scan_wrap
                ld    de,WM_ESZ
                add   hl,de
sched_scan_count
                djnz  sched_next_slot

                ; No peer is runnable. The original fixed stack was never
                ; overwritten, so resume it without copying back.
sched_resume_old
                pop   hl
                ld    sp,hl
                ret
sched_scan_wrap
                ld    c,0
                ld    hl,WM_TABLE+WM_FR_FLAGS
                jr    sched_scan_count
                endif

sched_restore_slot
                ld    a,c
                push  af                      ; target slot above the saved old SP
                ld    de,-WM_FR_FLAGS
                add   hl,de                   ; flags pointer -> entry/page pointer
                ld    a,(hl)                  ; target app page from WM entry +0
                call  sched_bank_set
                ld    a,(TASK_STACK_LEN)
                or    a
                jr    z,sched_restore_fault
                ld    c,a
                ld    e,a
                ld    b,0
                ld    d,b
                ld    hl,(BOOT_SP)
                or    a
                sbc   hl,de                   ; target fixed-stack bottom
                push  hl                      ; keep target SP below mapper call frames
                ex    de,hl                   ; DE = fixed destination
                ld    hl,TASK_STACK_DATA
                ldir
                pop   hl                      ; target SP
                pop   af                      ; target slot
                ld    (SCHED_CURRENT),a
                pop   de                      ; discard old SP
                ld    sp,hl
                ret

sched_restore_fault
                ; The old bank was already replaced. Map the old task again,
                ; then resume its still-intact fixed stack.
                pop   af                      ; discard target slot above the saved old SP
                ld    a,(SCHED_CURRENT)
                call  sched_wm_entry
                ld    a,(hl)
                call  sched_bank_set
                ld    a,1
                ld    (SCHED_FAULT),a
                ifdef PLATFORM_MSX
                ifdef GEMBENCH_BASELINE
                if GEMBENCH_BASELINE
                ld    (MSX_BASELINE_STACK_FAULT),a
                endif
                endif
                endif
                jr    sched_resume_old

sched_switch_fault
                ld    a,1
                ld    (SCHED_FAULT),a
                ifdef PLATFORM_MSX
                ifdef GEMBENCH_BASELINE
                if GEMBENCH_BASELINE
                ld    (MSX_BASELINE_STACK_FAULT),a
                endif
                endif
                endif
                ret                             ; original SP is still active

; sched_yield: safe-point counterpart of the interrupt wrapper. Every task
; context has the same register image; only its continuation differs. A system
; or finite worker task uses this path, while a timer-preempted worker resumes
; through sched_irq_restore below.
sched_yield
                di
                push  af
                push  bc
                push  de
                push  hl
                push  ix
                push  iy
                ex    af,af'
                push  af
                ex    af,af'
                exx
                push  bc
                push  de
                push  hl
                exx
                ld    a,(SCHED_CURRENT)
                call  sched_wm_entry
                ld    de,WM_FR_FLAGS
                add   hl,de
                set   3,(hl)                   ; root becomes runnable with its first snapshot
                call  sched_switch_context
sched_yield_restore
                ld    a,1
                ld    (SCHED_LOCK),a
sched_context_restore
                exx
                pop   hl
                pop   de
                pop   bc
                exx
                ex    af,af'
                pop   af
                ex    af,af'
                pop   iy
                pop   ix
                pop   hl
                pop   de
                pop   bc
                ld    a,(SCHED_RESERVED)      ; AF is still saved, so restored HL stays untouched
                rra
                jr    nc,sched_restore_yield
                xor   a
                ld    (SCHED_RESERVED),a
                ifdef PLATFORM_PCW
                jp    sched_pcw_irq_finish
                else
                pop   af
                ifdef PLATFORM_MSX
                jp    sched_irq_chain          ; finish through the saved DOS IM1 handler
                else
                jp    CPC_FW_IRQ               ; finish the IRQ in the restored task context
                endif
                endif
sched_restore_yield
                pop   af
                ei
                ret

; k_task_enable: opt an already-registered managed window into task service.
; desc.task_worker becomes the compute-only callback; desc.proc stays on the
; root/compositor task for draw, input, and lifecycle. The app build must reserve
; #7F00-#7FFF.
k_task_enable
                di
                ld    a,(WM_FOCUS)
                call  sched_wm_entry
                push  hl
                ld    a,(BANK_CUR)
                cp    (hl)                    ; only the calling app may enable itself
                jr    nz,sched_task_enable_fail
                ld    a,2
                ld    (TASK_STACK_LEN),a
                ld    hl,sched_task_start
                ld    (TASK_STACK_DATA),hl
                pop   hl
                ld    de,WM_FR_FLAGS
                add   hl,de
                bit   1,(hl)                   ; only managed windows have a task_worker field
                jr    z,sched_task_enable_done
                bit   3,(hl)
                jr    nz,sched_task_enable_done
                set   3,(hl)                  ; publish only after snapshot is complete
                ld    hl,SCHED_RUNNABLE
                inc   (hl)
sched_task_enable_done
                ei
                ret
sched_task_enable_fail
                pop   hl
                ei
                ret

; A task-enabled managed descriptor's task_worker runs outside the compositor.
; Existing apps are not opted in: the normal WM continues to drive their proc
; exactly as it does in release builds. A worker is deliberately pure compute;
; kernel and paged-module work belongs in proc callbacks on the root task.
sched_task_start
sched_task_loop
                ld    a,(SCHED_CURRENT)
                call  sched_wm_entry
                push  hl
                ld    de,WM_FR_FLAGS
                add   hl,de
                ld    a,(hl)
                and   WM_TASK_RUNNABLE|1
                cp    WM_TASK_RUNNABLE|1
                pop   hl
                jr    nz,sched_task_sleep
                ld    de,WM_FR_FRAME
                add   hl,de
                ld    e,(hl)                   ; entry+5 = managed descriptor pointer
                inc   hl
                ld    d,(hl)
                ex    de,hl
                ld    de,10                    ; desc.task_worker
                add   hl,de
                ld    a,(hl)
                inc   hl
                ld    h,(hl)
                ld    l,a
                ld    a,h
                or    l
                jr    z,sched_task_sleep
                xor   a
                ld    (SCHED_LOCK),a
                ei                              ; first-run snapshots inherit sched_yield's DI
                call  sched_md_call
                ld    a,1
                ld    (SCHED_LOCK),a
sched_task_sleep
                call  sched_yield
                jr    sched_task_loop

                if VISIBLE_COMPOSITOR
; ---- Architecture Milestone 9: exact visible damage -------------------------
;
; The Screen-7 resident child COM has no useful headroom.  Keep the compositor's
; geometry engine in this app-carried, always-mapped page-3 image instead.  A
; visible region is enumerated as horizontal bands split at every higher window
; top/bottom edge.  Within a band, maximal uncovered x runs are emitted.  This
; representation is exact for the WM's opaque rectangles and cannot overflow a
; finite rectangle pool.
WM_CLIP_X       equ #1338
WM_CLIP_Y       equ #1339
WM_CLIP_W       equ #133A
WM_CLIP_H       equ #133B
WM_VIS_HIDDEN   equ 0
WM_VIS_PARTIAL  equ 1
WM_VIS_FULL     equ 2
WM_VIS_FOCUSED  equ 3
WM_SLOT         equ #12F9
WM_OPEN_BACK    equ #12FB

                ifdef PLATFORM_CPC
; These compact geometry helpers are shared by the MSX2 and CPC resident
; compositor. Keeping the CPC copy in its app-carried scheduler preserves the
; guarded stack gap without changing semantics or the fixed API surface.
sched_focus_damage
                xor   a
                ld    (MSX_COMPOSITOR_EXTRA_PENDING),a
                ld    a,(WM_SLOT)
                or    a
                jr    nz,sfd_primary
                ld    a,(WM_OPEN_BACK)
sfd_primary
                call  sched_wm_entry
                inc   hl
                ld    de,WM_CLIP_X
                ld    bc,4
                ldir
                ld    a,(WM_SLOT)
                or    a
                ret   z
                ld    a,(WM_OPEN_BACK)
                or    a
                ret   z
                call  sched_wm_entry
                inc   hl
                ld    de,MSX_COMPOSITOR_EXTRA
                ld    bc,4
                ldir
                ld    a,1
                ld    (MSX_COMPOSITOR_EXTRA_PENDING),a
                ret

sched_damage_axis
                cp    b
                jr    nc,sda_oldmin
                ld    d,a
                ld    a,b
                jr    sda_span
sda_oldmin     ld    d,b
sda_span       add   a,c
                sub   d
                ld    e,a
                ret

sched_clip_full
                ld    bc,0
                ld    (WM_CLIP_X),bc
                ld    de,(SCR_LINES*256)|SCR_COLS
                ld    (WM_CLIP_W),de
                ret

sched_set_clip
                call  sched_wm_entry
                ld    b,(hl)
                inc   hl
                ld    a,(hl)
                ld    (WM_CLIP_X),a
                inc   hl
                ld    a,(hl)
                ld    (WM_CLIP_Y),a
                inc   hl
                ld    a,(hl)
                add   a,8
                ld    (WM_CLIP_W),a
                inc   hl
                ld    a,(hl)
                ld    (WM_CLIP_H),a
                ret

sched_wm_damage
                ld    (WM_CLIP_X),bc
                ld    (WM_CLIP_W),de
                xor   a
                ld    (MSX_COMPOSITOR_EXTRA_PENDING),a
                ret
                endif

; Capture one immutable source-damage rectangle for the complete z pass, then
; refresh visibility. Every surface iterator restarts from this damage instead
; of inheriting the last fragment emitted for the preceding surface.
sched_compositor_prepare
                ld    hl,WM_CLIP_X
                ld    de,MSX_COMPOSITOR_DAMAGE
                ld    bc,4
                ldir
                ld    hl,MSX_COMPOSITOR_EXTRA_PENDING
                ld    a,(hl)
                inc   hl
                ld    (hl),a
                dec   hl
                ld    (hl),0
                jp    sched_visibility_refresh

; A = window slot. Restore the compositor source damage and start the iterator.
sched_region_begin
                push  af
                xor   a                         ; begin with the primary damage source
                ld    (MSX_COMPOSITOR_SOURCE),a
                ld    hl,MSX_COMPOSITOR_DAMAGE
                ld    de,WM_CLIP_X
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
                ld    (MSX_REGION_SLOT),a
                ld    c,a
                ld    a,(WM_NWIN)
                or    a
                jr    z,srb_empty
                cp    WM_MAXWIN+1
                jr    nc,srb_empty
                ld    b,a
                ld    hl,WM_Z
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
                ld    (MSX_REGION_Z),a
                ld    a,c
                call  sched_wm_entry
                inc   hl
                ld    c,(hl)                  ; window x
                inc   hl
                ld    d,(hl)                  ; window y
                inc   hl
                ld    e,(hl)                  ; window width
                inc   hl
                ld    b,(hl)                  ; window height

                ld    a,(WM_CLIP_X)           ; left = max(clip.x, window.x)
                cp    c
                jr    nc,srb_left_ready
                ld    a,c
srb_left_ready  ld    (MSX_REGION_LEFT),a
                ld    a,(WM_CLIP_Y)           ; top = max(clip.y, window.y)
                cp    d
                jr    nc,srb_top_ready
                ld    a,d
srb_top_ready   ld    (MSX_REGION_TOP),a

                ld    a,c                     ; window right
                add   a,e
                ld    e,a
                ld    a,(WM_CLIP_X)           ; clip right
                ld    c,a
                ld    a,(WM_CLIP_W)
                add   a,c
                cp    e                       ; right = min(clip right, window right)
                jr    c,srb_right_ready
                ld    a,e
srb_right_ready ld    (MSX_REGION_RIGHT),a

                ld    a,d                     ; window bottom
                add   a,b
                ld    b,a
                ld    a,(WM_CLIP_Y)           ; clip bottom
                ld    c,a
                ld    a,(WM_CLIP_H)
                add   a,c
                cp    b                       ; bottom = min(clip bottom, window bottom)
                jr    c,srb_bottom_ready
                ld    a,b
srb_bottom_ready
                ld    (MSX_REGION_BOTTOM),a
                ld    hl,MSX_REGION_TOP
                cp    (hl)
                jr    c,srb_empty
                jr    z,srb_empty
                ld    a,(MSX_REGION_RIGHT)
                ld    hl,MSX_REGION_LEFT
                cp    (hl)
                jr    c,srb_empty
                jr    z,srb_empty

                ld    a,(MSX_REGION_TOP)
                ld    (MSX_REGION_Y),a
                ld    (MSX_REGION_BAND_END),a ; force preparation of the first band
                ld    a,(MSX_REGION_LEFT)
                ld    (MSX_REGION_X),a
                xor   a
                ld    (MSX_REGION_COVERED),a
                ld    (MSX_REGION_FRAGMENT_COUNT),a
                jr    sched_region_seek

; Continue an active iterator.  The original damage rectangle has already been
; folded into the fixed base bounds, so each call only installs the next clip.
sched_region_next
                call  sched_region_seek
                ret   nz
sched_region_advance_source
                ld    a,(MSX_COMPOSITOR_EXTRA_ACTIVE)
                or    a
                ret   z
                ld    a,(MSX_COMPOSITOR_SOURCE)
                or    a
                jr    z,sras_load_extra
                xor   a
                ret
sras_load_extra
                inc   a
                ld    (MSX_COMPOSITOR_SOURCE),a
                ld    hl,MSX_COMPOSITOR_EXTRA
                ld    de,WM_CLIP_X
                ld    bc,4
                ldir
                ld    a,(MSX_REGION_SLOT)
                jp    sched_region_begin_raw

; Direct component-damage visibility tests do not participate in a pending
; two-rectangle move pass.
sched_region_test
                push  af
                xor   a
                ld    (MSX_COMPOSITOR_SOURCE),a
                pop   af
                jp    sched_region_begin_raw

sched_region_seek
srs_band
                ld    a,(MSX_REGION_Y)
                ld    hl,MSX_REGION_BOTTOM
                cp    (hl)
                jp    nc,srb_empty
                ld    hl,MSX_REGION_BAND_END
                cp    (hl)
                call  nc,sched_region_prepare_band

                ld    a,(MSX_REGION_X)
                ld    c,a
srs_skip_covered
                ld    a,(MSX_REGION_RIGHT)
                cp    c
                jr    z,srs_advance_band
                jr    c,srs_advance_band
                ld    a,c
                call  sched_region_is_covered
                or    a
                jr    z,srs_run_start
                inc   c
                ld    a,c
                ld    (MSX_REGION_X),a
                jr    srs_skip_covered

srs_run_start
                ld    a,c
                ld    (WM_CLIP_X),a            ; also serves as run-left scratch
                inc   c
srs_extend_run
                ld    a,(MSX_REGION_RIGHT)
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
                ld    (MSX_REGION_X),a
                ld    hl,WM_CLIP_X
                sub   (hl)
                ld    (WM_CLIP_W),a
                ld    a,(MSX_REGION_Y)
                ld    (WM_CLIP_Y),a
                ld    c,a
                ld    a,(MSX_REGION_BAND_END)
                sub   c
                ld    (WM_CLIP_H),a
                ld    hl,MSX_REGION_FRAGMENT_COUNT
                inc   (hl)
                ld    a,1
                or    a
                ret

srs_advance_band
                ld    a,(MSX_REGION_BAND_END)
                ld    (MSX_REGION_Y),a
                ld    a,(MSX_REGION_LEFT)
                ld    (MSX_REGION_X),a
                jr    srs_band

; Choose the next vertical edge among all higher windows whose rectangles touch
; the base horizontally.  An actual two-dimensional intersection also marks the
; surface partial; this flag is consumed by the visibility classifier.
sched_region_prepare_band
                ld    a,(MSX_REGION_BOTTOM)
                ld    (MSX_REGION_BAND_END),a
                ld    a,(MSX_COMPOSITOR_SOURCE)
                or    a
                jr    z,srp_begin_windows
                ; The second source is the old window rectangle. Treat the
                ; primary/new rectangle as an opaque pseudo-cover so overlap is
                ; emitted only once. Prime SCAN_Z one entry early: the shared
                ; edge tail increments it before beginning real higher windows.
                ld    a,(MSX_REGION_Z)
                ld    (MSX_REGION_SCAN_Z),a
                ld    hl,MSX_COMPOSITOR_DAMAGE
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
                ld    a,(MSX_REGION_LEFT)
                cp    e
                jr    nc,srp_next_cover
                ld    a,c
                ld    hl,MSX_REGION_RIGHT
                cp    (hl)
                jr    nc,srp_next_cover
                ld    a,(MSX_REGION_TOP)
                cp    b
                jr    nc,srp_edges
                ld    a,d
                ld    hl,MSX_REGION_BOTTOM
                cp    (hl)
                jr    nc,srp_edges
                jr    srp_mark_and_edges
srp_begin_windows
                ld    a,(MSX_REGION_Z)
                inc   a
                ld    (MSX_REGION_SCAN_Z),a
srp_cover_loop
                ld    a,(MSX_REGION_SCAN_Z)
                ld    hl,WM_NWIN
                cp    (hl)
                ret   nc
                ld    hl,WM_Z
                add   a,l
                ld    l,a
                ld    a,(hl)
                call  sched_wm_entry
                inc   hl
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

                ld    a,(MSX_REGION_LEFT)      ; horizontal intersection?
                cp    e
                jr    nc,srp_next_cover
                ld    a,c
                ld    hl,MSX_REGION_RIGHT
                cp    (hl)
                jr    nc,srp_next_cover
                ld    a,(MSX_REGION_TOP)       ; vertical intersection with base?
                cp    b
                jr    nc,srp_edges
                ld    a,d
                ld    hl,MSX_REGION_BOTTOM
                cp    (hl)
                jr    nc,srp_edges
srp_mark_and_edges
                ld    a,1
                ld    (MSX_REGION_COVERED),a

srp_edges       ld    a,(MSX_REGION_Y)         ; cover top is a future band edge?
                cp    d
                jr    nc,srp_bottom_edge
                ld    a,d
                ld    hl,MSX_REGION_BAND_END
                cp    (hl)
                jr    nc,srp_bottom_edge
                ld    (hl),a
srp_bottom_edge ld    a,(MSX_REGION_Y)         ; cover bottom is a future edge?
                cp    b
                jr    nc,srp_next_cover
                ld    a,b
                ld    hl,MSX_REGION_BAND_END
                cp    (hl)
                jr    nc,srp_next_cover
                ld    (hl),a
srp_next_cover  ld    hl,MSX_REGION_SCAN_Z
                inc   (hl)
                jr    srp_cover_loop

; A = x column. Return A=1/NZ if any higher opaque window contains (x,band_y),
; otherwise A=0/Z.  WM_Z contains live slots only.
sched_region_is_covered
                push  bc                       ; caller keeps its x cursor in C
                ld    (MSX_REGION_TEST_X),a
                ld    a,(MSX_COMPOSITOR_SOURCE)
                or    a
                jr    z,sric_begin_windows
                ld    hl,MSX_COMPOSITOR_DAMAGE
                ld    a,(MSX_REGION_TEST_X)
                cp    (hl)                     ; x < primary left
                jr    c,sric_begin_windows
                ld    c,(hl)
                inc   hl
                ld    d,(hl)                   ; primary top
                inc   hl
                ld    a,c
                add   a,(hl)                   ; primary right
                ld    c,a
                ld    a,(MSX_REGION_TEST_X)
                cp    c
                jr    nc,sric_begin_windows
                inc   hl
                ld    a,(hl)                   ; primary height
                add   a,d                      ; primary bottom
                ld    c,a
                ld    a,(MSX_REGION_Y)
                cp    d
                jr    c,sric_begin_windows
                cp    c
                jr    nc,sric_begin_windows
                pop   bc
                ld    a,1
                or    a
                ret
sric_begin_windows
                ld    a,(MSX_REGION_Z)
                inc   a
                ld    (MSX_REGION_SCAN_Z),a
sric_loop
                ld    a,(MSX_REGION_SCAN_Z)
                ld    hl,WM_NWIN
                cp    (hl)
                jr    nc,sric_clear
                ld    hl,WM_Z
                add   a,l
                ld    l,a
                ld    a,(hl)
                call  sched_wm_entry
                inc   hl
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
                ld    a,(MSX_REGION_TEST_X)
                cp    c
                jr    c,sric_next
                cp    e
                jr    nc,sric_next
                ld    a,(MSX_REGION_Y)
                cp    d
                jr    c,sric_next
                cp    b
                jr    nc,sric_next
                pop   bc
                ld    a,1
                or    a
                ret
sric_next       ld    hl,MSX_REGION_SCAN_Z
                inc   (hl)
                jr    sric_loop
sric_clear      pop   bc
                xor   a
                ret

; Reclassify all surfaces after stacking/geometry damage.  The ordinary table
; records surface visibility.  The scheduler table starts as a copy and then
; folds all windows of a multi-window application into its designated worker
; slot, so PAINT-like ownership has one scheduling rank.
sched_visibility_refresh
                ld    hl,WM_CLIP_X
                ld    de,MSX_REGION_SAVED_CLIP
                ld    bc,4
                ldir
                xor   a
                ld    (WM_CLIP_X),a
                ld    (WM_CLIP_Y),a
                ld    a,SCR_COLS
                ld    (WM_CLIP_W),a
                ld    a,SCR_LINES
                ld    (WM_CLIP_H),a
                xor   a
                ld    hl,MSX_WM_VISIBILITY
                ld    de,MSX_WM_VISIBILITY+1
                ld    bc,15
                ld    (hl),a
                ldir
                ld    (MSX_REGION_REFRESH_Z),a
svr_surface_loop
                ld    a,(MSX_REGION_REFRESH_Z)
                ld    hl,WM_NWIN
                cp    (hl)
                jr    nc,svr_aggregate
                ld    hl,WM_Z
                add   a,l
                ld    l,a
                ld    a,(hl)                   ; slot
                ld    c,a
                ld    a,(WM_FOCUS)
                cp    c
                ld    b,WM_VIS_FOCUSED
                jr    z,svr_store_surface
                xor   a                        ; each classification starts from
                ld    (WM_CLIP_X),a            ; the complete screen, not the first
                ld    (WM_CLIP_Y),a            ; fragment emitted for the prior slot
                ld    a,SCR_COLS
                ld    (WM_CLIP_W),a
                ld    a,SCR_LINES
                ld    (WM_CLIP_H),a
                ld    a,c
                call  sched_region_test
                ld    b,WM_VIS_HIDDEN
                or    a
                jr    z,svr_reload_surface_slot
                ld    b,WM_VIS_FULL
                ld    a,(MSX_REGION_COVERED)
                or    a
                jr    z,svr_reload_surface_slot
                ld    b,WM_VIS_PARTIAL
svr_reload_surface_slot
                ld    a,(MSX_REGION_SLOT)      ; iterator scratch freely uses C
                ld    c,a
svr_store_surface
                ld    hl,MSX_WM_VISIBILITY
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),b
                ld    hl,MSX_TASK_VISIBILITY
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),b
                ld    hl,MSX_REGION_REFRESH_Z
                inc   (hl)
                jr    svr_surface_loop

svr_aggregate
                ifdef PLATFORM_MSX
                xor   a
                ld    (MSX_REGION_OWNER_INDEX),a
svr_owner_loop
                ld    a,(MSX_REGION_OWNER_INDEX)
                cp    8
                jr    nc,svr_restore_clip
                ld    hl,MSX_APP_WORKER_WIN
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a                         ; slot zero is the root, never an app worker
                jr    z,svr_next_owner
                cp    WM_MAXWIN
                jr    nc,svr_next_owner
                ld    (MSX_REGION_WORKER_SLOT),a
                ld    a,(MSX_REGION_OWNER_INDEX)
                inc   a
                ld    (MSX_REGION_OWNER_ID),a
                xor   a
                ld    (MSX_REGION_OWNER_MAX),a
                ld    (MSX_REGION_SLOT_SCAN),a
svr_owner_windows
                ld    a,(MSX_REGION_SLOT_SCAN)
                cp    WM_MAXWIN
                jr    nc,svr_owner_store
                ld    c,a
                ld    hl,MSX_WIN_OWNER
                add   a,l
                ld    l,a
                ld    a,(MSX_REGION_OWNER_ID)
                cp    (hl)
                jr    nz,svr_owner_window_next
                ld    hl,MSX_WM_VISIBILITY
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(MSX_REGION_OWNER_MAX)
                cp    (hl)
                jr    nc,svr_owner_window_next
                ld    a,(hl)
                ld    (MSX_REGION_OWNER_MAX),a
svr_owner_window_next
                ld    hl,MSX_REGION_SLOT_SCAN
                inc   (hl)
                jr    svr_owner_windows
svr_owner_store ld    a,(MSX_REGION_WORKER_SLOT)
                ld    hl,MSX_TASK_VISIBILITY
                add   a,l
                ld    l,a
                ld    a,(MSX_REGION_OWNER_MAX)
                ld    (hl),a
svr_next_owner  ld    hl,MSX_REGION_OWNER_INDEX
                inc   (hl)
                jr    svr_owner_loop
                endif

svr_restore_clip
                ld    hl,MSX_REGION_SAVED_CLIP
                ld    de,WM_CLIP_X
                ld    bc,4
                ldir
                ret
                endif                          ; shared MSX2/CPC M9 region engine

                ifdef PLATFORM_PCW
; GEOBENCH owns the PCW outright. Its FDC interrupt route remains disabled and
; storage is polled, leaving the ASIC's 300 Hz maskable timer as the only INT
; source. The standard PCW MCU bootstrap has F0 21 F5 at #0038; k_exit restores
; those bytes before jumping to #0000 for a warm boot.
PCW_IRQ_VECTOR  equ #0038
PCW_TIMER_ACK   equ #F4

sched_irq_install
                ld    hl,PCW_IRQ_VECTOR
                ld    (hl),#C3
                inc   hl
                ld    de,sched_irq_vector
                ld    (hl),e
                inc   hl
                ld    (hl),d
                im    1
                in    a,(PCW_TIMER_ACK)       ; discard timer ticks accumulated while DI
                ret

sched_irq_uninstall
                ld    hl,PCW_IRQ_VECTOR
                ld    (hl),#F0
                inc   hl
                ld    (hl),#21
                inc   hl
                ld    (hl),#F5
                ret

; AF is still the first word on the selected task's restored stack. Acknowledge
; the PCW timer before restoring it, then return directly from IM 1.
sched_pcw_irq_finish
                in    a,(PCW_TIMER_ACK)
                pop   af
                ei
                reti
                else
                ifdef PLATFORM_MSX
; MSX-DOS leaves a writable IM 1 trampoline at #0038 while the TPA is active.
; Hooking it keeps page-0 GEOBENCH state visible, unlike H.TIMI (which runs
; after the BIOS maps its ROM into page 0). The original DOS JP target is
; copied into sched_irq_chain and receives the exact raw interrupt stack after
; either a fast path or a task switch.
MSX_IRQ_VECTOR  equ #0038

sched_irq_install
                ld    hl,(MSX_IRQ_VECTOR+1)
                ld    (sched_irq_chain+1),hl
                ld    hl,sched_irq_vector
                ld    (MSX_IRQ_VECTOR+1),hl
                ret

sched_irq_uninstall
                ld    hl,(sched_irq_chain+1)
                ld    (MSX_IRQ_VECTOR+1),hl
                ret

sched_irq_chain
                jp    0                       ; patched with the original DOS IRQ target
                else
; CPC IM 1 enters through writable RAM at #0038. The scheduler runs before the
; firmware tick. Fast paths tail-call B941 immediately. A context switch marks
; the shared restore path, which tail-calls B941 after the target registers and
; stack are active. Firmware therefore always sees its native interrupt stack
; contract and returns directly to the selected task. External interrupts skip
; scheduler work because B941 owns a different stack contract for them.
CPC_IRQ_VECTOR  equ #0038
CPC_FW_IRQ      equ #B941

sched_irq_install
                ld    hl,sched_irq_vector
                jr    sched_irq_set_vector

; Restore the standard firmware vector before returning to BASIC/DOS.
sched_irq_uninstall
                ld    hl,CPC_FW_IRQ
sched_irq_set_vector
                di
                ld    a,#C3
                ld    (CPC_IRQ_VECTOR),a
                ld    (CPC_IRQ_VECTOR+1),hl
                ret
                endif
                endif

sched_irq_vector
                ifndef PLATFORM_PCW
                ifndef PLATFORM_MSX
                ex    af,af'
                jr    nc,sched_irq_normal
                ex    af,af'                  ; restore app AF and leave firmware's stack untouched
                jp    CPC_FW_IRQ
sched_irq_normal
                ex    af,af'
                endif
                endif
sched_irq_body
                push  af
                push  hl                      ; quantum bookkeeping must preserve worker HL
                ld    a,(SCHED_CURRENT)
                or    a
                jr    z,sched_irq_fast
sched_irq_worker
                if !PREEMPTIVE_SWITCH
                jp    sched_irq_fast          ; diagnostic: prove the firmware trampoline alone
                endif
                ld    hl,SCHED_QUANTUM
                dec   (hl)
                jr    nz,sched_irq_fast
                ld    (hl),SCHED_QUANTUM_TICKS
                ld    a,(SCHED_LOCK)
                or    a
                jr    z,sched_irq_switch
sched_irq_fast
                pop   hl
                ifdef PLATFORM_PCW
                jp    sched_pcw_irq_finish
                else
                pop   af
                ifdef PLATFORM_MSX
                jp    sched_irq_chain
                else
                jp    CPC_FW_IRQ
                endif
                endif

sched_irq_switch
                pop   hl
                inc   a                       ; A is zero after the SCHED_LOCK test
                ld    (SCHED_RESERVED),a      ; common restore must complete this firmware tick
                push  bc
                push  de
                push  hl
                push  ix
                push  iy
                ex    af,af'
                push  af
                ex    af,af'
                exx
                push  bc
                push  de
                push  hl
                exx
                ld    hl,21                   ; interrupted PC high byte after ten PUSHes
                add   hl,sp
                ld    a,(hl)
                cp    #40                     ; only code in the mapped app bank is preemptible
                jr    c,sched_irq_defer
                cp    #80
                jr    nc,sched_irq_defer
                ld    a,(SCHED_CURRENT)
                call  sched_wm_entry
                ld    a,(BANK_CUR)
                cp    (hl)                    ; reject kernel modules mapped over the app bank
                jr    nz,sched_irq_defer
                call  sched_switch_context
sched_irq_restore
                xor   a
                ld    (SCHED_LOCK),a
                jp    sched_context_restore
sched_irq_defer
                jp    sched_context_restore

; Fixed-address scheduler helpers. They duplicate only the small pieces that
; cannot be called through profile-dependent resident labels.
sched_wm_entry
                ld    hl,WM_TABLE
                or    a
                ret   z
                ld    b,a
                ld    de,WM_ESZ
sched_we_add
                add   hl,de
                djnz  sched_we_add
                ret

sched_md_call
                jp    (hl)

sched_bank_set
                ld    (BANK_CUR),a
                ifdef PLATFORM_MSX
                ld    hl,(MSX_PUTP1)
                jp    (hl)                    ; mapper RET returns to our caller
                else
                ifdef PLATFORM_PCW
                out   (PCW_BANK1),a
                else
                ld    bc,#7F00
                out   (c),a
                endif
                ret
                endif

                ifdef PLATFORM_CPC
                include "cpc_services.asm"
                endif

                endif                         ; PREEMPTIVE_CONTEXT

sched_image_end
                ifndef SCHED_LIMIT
                ifdef PLATFORM_CPC
SCHED_LIMIT     equ   3584
                else
                if VISIBLE_COMPOSITOR
SCHED_LIMIT     equ   1536
                else
SCHED_LIMIT     equ   512
                endif
                endif
                endif
                assert sched_image_end-SCHED_BASE<=SCHED_LIMIT,"scheduler exceeds fixed slot"
