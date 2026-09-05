; kernel/msx_page_pool.asm - MSX2 owner identities and 16 KiB page handles.
;
; Architecture milestone 1 (#31) separates mapper capacity from WM_MAXWIN.
; DOS mapper segments are retained once at boot, while the public allocator
; exposes generation-tagged handles instead of native segment numbers.  The
; existing resident picture/GBR paths keep using wm_alloc_page/wm_free_page as
; privileged compatibility helpers; their allocations still receive the owner
; of the focused application and are reclaimed when that owner closes.
;
; Architecture milestone 2 (#32) promotes those owners into independent
; application records. Windows retain their frozen compositor layout and point
; to an application through the parallel MSX_WIN_OWNER table. A single code page
; may consequently own several generation-tagged window slots.
;
; Architecture milestone 3 (#35) adds an eight-entry application FIFO. Senders
; copy four inline bytes into page-3 RAM and return; one message is delivered by
; the root loop on a later turn. Application generation is the endpoint identity.
;
; Architecture milestone 4 (#37) adds four explicit filesystem contexts behind
; a tiny resident dispatcher and the paged GBFSCTX.MOD implementation. Contexts
; retain drive/path/name/offset and directory FIB state independently.
;
; CPC restart step 2A (#64): owner identity, page policy and reclamation are
; included from core/ through msx_owner_page.inc's state/callback bindings.
; Step 2B (#69) adds application/window identities, links and lifetime through
; msx_app_lifetime.inc. Native mapper discovery, sysinfo, deferred/FS services
; remain here; focus/rendering implementations remain their existing providers.
; Ordered includes preserve the emitted MSX2 kernel bytes.

; This source is assembled in two passes. The normal app_pool include emits the
; owner/page/application runtime, while GB_DEFER_LATE emits only the deferred
; runtime after the MSX screen driver's page-aligned lookup tables. Keeping that
; late block out of alignment padding is required by the #0100..#3FFF child-COM
; loader window, especially for Screen 7.
                ifndef GB_DEFER_LATE

GB_OWNER_MAX          equ 8
GB_APP_MAX            equ GB_OWNER_MAX

GB_APP_F_PUBLISHED    equ 1
GB_APP_F_ROOT         equ 2
GB_APP_F_TERMINATING  equ 4
GB_APP_F_WINDOWLESS   equ 8

GB_APP_OK             equ 0
GB_APP_ERR_UNSUPPORTED equ 1
GB_APP_ERR_STALE      equ 2
GB_APP_ERR_OWNER      equ 3
GB_APP_ERR_FULL       equ 4
GB_APP_ERR_ROOT       equ 5
GB_APP_ERR_BADARG     equ 6

GB_DEFER_MAX          equ 8
GB_DEFER_RECORD_SIZE  equ 8
GB_DEFER_OK           equ 0
GB_DEFER_ERR_UNSUPPORTED equ 1
GB_DEFER_ERR_STALE    equ 2
GB_DEFER_ERR_NO_HANDLER equ 3
GB_DEFER_ERR_FULL     equ 4
GB_DEFER_ERR_BADARG   equ 5
GB_DEFER_ERR_CONTEXT  equ 6

GB_FSCTX_OK              equ 0
GB_FSCTX_ERR_UNSUPPORTED equ 1
GB_FSCTX_ERR_STALE       equ 2
GB_FSCTX_ERR_OWNER       equ 3
GB_FSCTX_ERR_FULL        equ 4
GB_FSCTX_ERR_BADARG      equ 5
GB_FSCTX_ERR_IO          equ 6
GB_FSCTX_ERR_CONTEXT     equ 7

GB_PAGE_UNSPECIFIED   equ 0
GB_PAGE_APPLICATION   equ 1
GB_PAGE_RESOURCE      equ 2
GB_PAGE_DOCUMENT      equ 3
GB_PAGE_CACHE         equ 4
GB_PAGE_SCRAP         equ 5
GB_PAGE_TEMPORARY     equ 6
GB_PAGE_SECONDARY_CODE equ 7

GB_PAGE_OK            equ 0
GB_PAGE_ERR_UNSUPPORTED equ 1
GB_PAGE_ERR_STALE     equ 2
GB_PAGE_ERR_OWNER     equ 3
GB_PAGE_ERR_FREE      equ 4
GB_PAGE_ERR_NOMEM     equ 5
GB_PAGE_ERR_BADARG    equ 6

GB_PLATFORM_MSX2      equ 1
                include "msx_capabilities.inc"

                include "msx_owner_page.inc"
                include "core/app_lifetime_contract.inc"
                include "core/window_focus_contract.inc" ; WM scratch EQU cells are now defined

; app_pool_init: retain the TPA page-1 segment plus every available mapper
; segment, up to MSX_PAGE_MAX.  PAGE_DATA was already allocated separately by
; msx_mem_init.  The TPA entry is never returned through FRE_SEG.
app_pool_init
                ld    hl,MSX_PAGE_STATE
                ld    de,MSX_PAGE_STATE+1
                ld    bc,MSX_ARCH_TABLE_END-MSX_PAGE_STATE-1
                ld    (hl),0
                ldir
                ld    hl,MSX_PAGE_NATIVE
                ld    a,(MSX_TPASEG)
                ld    (hl),a
                inc   hl
                ld    c,1
mpp_more
                ld    a,c
                cp    MSX_PAGE_MAX
                jr    nc,mpp_done
                push  hl
                push  bc
                xor   a                       ; ALL_SEG: user segment, any mapper
                ld    b,a
                ld    hl,(MSX_ALLSEG)
                call  jp_hl
                pop   bc
                pop   hl
                jr    c,mpp_done
                ld    (hl),a
                inc   hl
                inc   c
                jr    mpp_more
mpp_done
                ld    a,c
                ld    (MSX_PAGE_TOTAL),a
                ld    (MSX_PAGE_FREE),a
                call  msx_pool_mirror
                call  page_count_free
                jp    sysinfo_init

; Keep the old first-eight-page cells populated for diagnostics and old code
; that only inspects them.  Allocation state itself lives in page-3 metadata.
msx_pool_mirror
                ld    hl,APP_PAGES
                ld    de,APP_PAGES+1
                ld    bc,WM_MAXWIN-1
                ld    (hl),0
                ldir
                ld    hl,APP_BUSY
                ld    de,APP_BUSY+1
                ld    bc,WM_MAXWIN-1
                ld    (hl),0
                ldir
                ld    a,(MSX_PAGE_TOTAL)
                cp    WM_MAXWIN+1
                jr    c,mpm_count_ok
                ld    a,WM_MAXWIN
mpm_count_ok    or    a
                ld    (APP_NPAGES),a           ; compatibility view is exactly APP_PAGES capacity
                ret   z
                ld    c,a
                ld    hl,MSX_PAGE_NATIVE
                ld    de,APP_PAGES
                ld    b,0
                ldir
                ret

                include "core/page_count.asm"

sysinfo_init
                ifdef MSX_SCREEN7
                ld    a,7
                else
                ld    a,6
                endif
                jp    MSX_MODULE_SYSINFO

                include "core/owner_identity.asm"

                include "core/app_code.asm"

                include "core/window_identity.asm"

                include "core/owner_context.asm"

                include "core/page_pool.asm"

                include "core/owner_reclaim.asm"

; GB_SYSINFO #80C3: return an immutable versioned record in page-3 RAM. Only the free
; count is dynamic, so refresh it at the query boundary.
k_sysinfo
                call  page_count_free
                jp    MSX_MODULE_SYSINFO_QUERY

; GB_OWNER #80C6: return the generation-tagged current application identity.
k_owner_current
                jp    owner_current

; GB_PAGE #80C9 dispatcher:
;   A=0, B=purpose       -> DE=page handle (zero on failure)
;   A=1, HL=page handle -> A=status, free if owned by current application
;   A=2, HL=page handle -> A=status, validate without freeing
k_page
                or    a
                jr    z,kpg_alloc
                dec   a
                jr    z,kpg_free
                dec   a
                jr    z,kpg_check
                ld    a,GB_PAGE_ERR_BADARG
                ret
kpg_alloc       ld    a,b
                cp    GB_PAGE_SECONDARY_CODE+1
                jr    nc,kpg_alloc_bad
                push  bc                       ; owner lookup scans the page pool
                call  owner_current
                pop   bc                        ; restore requested purpose
                ld    a,d
                or    e
                jr    z,kpg_alloc_bad
                call  page_alloc_owned
                ret   c
kpg_alloc_bad   ld    de,0
                ret
kpg_free        push  hl
                call  owner_current
                pop   hl
                ld    a,d
                or    e
                jr    z,kpg_no_owner
                jp    page_free_owned
kpg_check       push  hl
                call  owner_current
                pop   hl
                ld    a,d
                or    e
                jr    z,kpg_no_owner
                jp    page_check_owned
kpg_no_owner    ld    a,GB_PAGE_ERR_OWNER
                ret

                endif
                ifdef GB_DEFER_LATE
; GB_DEFER #80CF (Architecture Milestone 3): bounded asynchronous application
; messages. Operations are append-only and MSX2-only:
;   A=0, HL=handler       register/unregister the current application endpoint
;   A=1, HL=send record   enqueue receiver,type,p0,p1,p2 (sender is implicit)
;   A=2                   DE=current eight-byte delivery record, or zero
;   A=3                   A=free queue records
;   A=4, B=service class  DE=topmost matching application owner, or zero
;   A=5, C=accessory ID   DE=matching accessory application owner, or zero
;   A=6                   cancel all messages queued by the current application
k_defer
                or    a
                jp    z,kdefer_register
                dec   a
                jp    z,kdefer_send
                dec   a
                jp    z,kdefer_current
                dec   a
                jp    z,kdefer_free
                dec   a
                jp    z,kdefer_find_service
                dec   a
                jp    z,kdefer_find_accessory
                dec   a
                jp    z,kdefer_cancel_all
kdefer_bad     ld    a,GB_DEFER_ERR_BADARG
                ret

kdefer_register
                if PREEMPTIVE_CONTEXT
                ld    a,(SCHED_CURRENT)
                or    a
                jp    nz,kdefer_context          ; workers cannot publish callbacks
                endif
                ld    (MSX_DEFER_SEND+4),hl
                call  owner_current
                call  owner_validate
                jp    nc,kdefer_context
                ld    (MSX_DEFER_SEND),de
                ld    hl,(MSX_DEFER_SEND+4)
                ld    a,h
                or    l
                jr    z,kdr_unregister
                ld    a,h                       ; callbacks must live in the mapped app page
                cp    #40
                jr    c,kdefer_bad
                cp    #80
                jr    nc,kdefer_bad
kdr_store      ld    a,e
                dec   a
                ld    c,a
                ld    hl,MSX_DEFER_HANDLER_LO
                add   a,l
                ld    l,a
                ld    a,(MSX_DEFER_SEND+4)
                ld    (hl),a
                ld    hl,MSX_DEFER_HANDLER_HI
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(MSX_DEFER_SEND+5)
                ld    (hl),a
                xor   a
                ret
kdr_unregister ld    de,(MSX_DEFER_SEND)
                call  defer_purge_owner          ; cancel both directions before unpublishing
                xor   a
                ld    (MSX_DEFER_SEND+4),a
                ld    (MSX_DEFER_SEND+5),a
                ld    de,(MSX_DEFER_SEND)
                jr    kdr_store

; Validate the caller-page six-byte record before copying it. Queue entries are
; strictly FIFO; validation precedes the capacity check, so stale/no-handler is
; deterministic even when the queue is full.
kdefer_send
                if PREEMPTIVE_CONTEXT
                ld    a,(SCHED_CURRENT)
                or    a
                jp    nz,kdefer_context          ; root-task application callbacks only
                endif
                ld    (MSX_DEFER_SEND+4),hl
                ld    a,h
                cp    #40
                jp    c,kdefer_bad
                cp    #80
                jr    c,kds_page1_pointer
                cp    MSX_APP_FIXED_BOTTOM/256
                jp    c,kdefer_bad               ; reject kernel glue/scheduler fixed RAM
                push  hl
                ld    de,5                       ; the complete six-byte record must remain TPA
                add   hl,de
                ex    de,hl
                ld    hl,(BOOT_SP)               ; stable copy of the DOS/Nextor TPA ceiling
                or    a
                sbc   hl,de
                pop   hl
                jp    c,kdefer_bad
                jp    z,kdefer_bad               ; ceiling itself belongs to DOS
                jr    kds_pointer_ok
kds_page1_pointer
                cp    #7F
                jr    nz,kds_pointer_ok
                ld    a,l
                cp    #FB                       ; record through HL+5 must remain below #8000
                jp    nc,kdefer_bad
kds_pointer_ok push  hl
                call  owner_current
                call  owner_validate
                pop   hl                        ; owner validation clobbers HL
                jp    nc,kdefer_context
                ld    (MSX_DEFER_SEND),de       ; implicit sender
                ld    e,(hl)
                inc   hl
                ld    d,(hl)
                inc   hl
                ld    a,(hl)                    ; type zero is reserved/invalid
                or    a
                jp    z,kdefer_bad
                ld    (MSX_DEFER_SEND+2),de
                call  owner_validate
                jp    nc,kdefer_stale
                ld    a,e
                dec   a
                ld    c,a
                ld    hl,MSX_APP_FLAGS
                add   a,l
                ld    l,a
                bit   2,(hl)
                jp    nz,kdefer_stale
                ld    hl,MSX_DEFER_HANDLER_LO
                ld    a,c
                add   a,l
                ld    l,a
                ld    b,(hl)
                ld    hl,MSX_DEFER_HANDLER_HI
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    b
                jp    z,kdefer_no_handler
                ld    a,(MSX_DEFER_COUNT)
                cp    GB_DEFER_MAX
                jp    nc,kdefer_full
                push  af                        ; destination = queue + count*8
                add   a,a
                add   a,a
                add   a,a
                ld    e,a
                ld    d,0
                ld    hl,MSX_DEFER_QUEUE
                add   hl,de
                ex    de,hl
                ld    hl,MSX_DEFER_SEND         ; sender + receiver
                ld    bc,4
                ldir
                ld    hl,(MSX_DEFER_SEND+4)     ; type + four-byte inline tail
                inc   hl
                inc   hl
                ld    bc,4
                ldir
                pop   af
                inc   a
                ld    (MSX_DEFER_COUNT),a       ; publish only after all bytes are copied
                xor   a
                ret

kdefer_current
                ld    a,(MSX_DEFER_BUSY)
                or    a
                jr    z,kdefer_no_current
                ld    de,MSX_DEFER_CURRENT
                ret
kdefer_no_current
                ld    de,0
                ret

kdefer_free    ld    a,(MSX_DEFER_COUNT)
                ld    b,a
                ld    a,GB_DEFER_MAX
                sub   b
                ret

kdefer_find_service
                ld    c,0
                call  ksh_find
                jr    kdefer_owner_for_handle
kdefer_find_accessory
                call  ksh_find_accessory
kdefer_owner_for_handle
                or    a
                jr    z,kdefer_no_current
                dec   a
                ld    c,a
                ld    hl,MSX_WIN_OWNER
                add   a,l
                ld    l,a
                ld    e,(hl)
                ld    hl,MSX_WIN_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    d,(hl)
                call  owner_validate
                ret   c
                jr    kdefer_no_current

kdefer_cancel_all
                if PREEMPTIVE_CONTEXT
                ld    a,(SCHED_CURRENT)
                or    a
                jp    nz,kdefer_context          ; queue ownership belongs to root apps
                endif
                call  owner_current
                call  owner_validate
                jr    nc,kdefer_context
                jp    defer_cancel_sender

kdefer_stale   ld    a,GB_DEFER_ERR_STALE
                ret
kdefer_no_handler
                ld    a,GB_DEFER_ERR_NO_HANDLER
                ret
kdefer_full    ld    a,GB_DEFER_ERR_FULL
                ret
kdefer_context ld    a,GB_DEFER_ERR_CONTEXT
                ret

; A=index -> HL=queue record. The queue stays within one #C3xx page.
defer_record_ptr
                add   a,a
                add   a,a
                add   a,a
                add   a,#80
                ld    l,a
                ld    h,#C3
                ret

; Remove compact record C and retain FIFO order. Count is decremented before
; the bounded overlap-safe left shift (at most 56 bytes).
defer_remove_index
                ld    a,(MSX_DEFER_COUNT)
                dec   a
                ld    (MSX_DEFER_COUNT),a
                sub   c                         ; records after the removed one
                ret   z
                ld    b,a
                ld    a,c
                call  defer_record_ptr
                push  hl                        ; destination
                ld    de,GB_DEFER_RECORD_SIZE
                add   hl,de                     ; source
                pop   de
                ld    a,b
                add   a,a
                add   a,a
                add   a,a
                ld    c,a
                ld    b,0
                ldir
                ret

; Compact messages matching an owner. Mode zero removes both sender and receiver
; (teardown/unregister); mode one removes only sender (explicit cancellation).
; Returns the number removed in A.
defer_purge_owner
                xor   a
                jr    defer_purge_start
defer_cancel_sender
                ld    a,1
defer_purge_start
                ld    (MSX_DEFER_SEND+4),a      ; match mode
                ld    (MSX_DEFER_PURGE_OWNER),de
                xor   a
                ld    (MSX_DEFER_INDEX),a
                ld    (MSX_DEFER_SEND+5),a      ; removed count
defer_purge_loop
                ld    a,(MSX_DEFER_INDEX)
                ld    c,a
                ld    a,(MSX_DEFER_COUNT)
                cp    c
                jr    z,defer_purge_done
                jr    c,defer_purge_done
                ld    a,c
                call  defer_record_ptr
                ld    de,(MSX_DEFER_PURGE_OWNER)
                ld    a,(hl)                    ; sender low/generation
                cp    e
                jr    nz,defer_purge_receiver
                inc   hl
                ld    a,(hl)
                cp    d
                jr    z,defer_purge_remove
                dec   hl
defer_purge_receiver
                ld    a,(MSX_DEFER_SEND+4)
                or    a
                jr    nz,defer_purge_keep
                inc   hl
                inc   hl                        ; receiver low/generation
                ld    a,(hl)
                cp    e
                jr    nz,defer_purge_keep
                inc   hl
                ld    a,(hl)
                cp    d
                jr    nz,defer_purge_keep
defer_purge_remove
                ld    a,(MSX_DEFER_INDEX)
                ld    c,a
                call  defer_remove_index
                ld    hl,MSX_DEFER_SEND+5
                inc   (hl)
                jr    defer_purge_loop          ; compacted next record has same index
defer_purge_keep
                ld    hl,MSX_DEFER_INDEX
                inc   (hl)
                jr    defer_purge_loop
defer_purge_done
                ld    a,(MSX_DEFER_SEND+5)
                ret

; Called exactly once per WM root-loop turn. The queue head is copied and
; removed before validation/callback, so handlers may enqueue replies without
; nesting delivery or corrupting the stable current record.
defer_dispatch_one
                ld    a,(MSX_DEFER_BUSY)
                or    a
                ret   nz
                ld    a,(MSX_DEFER_COUNT)
                or    a
                ret   z
                ld    hl,MSX_DEFER_QUEUE
                ld    de,MSX_DEFER_CURRENT
                ld    bc,GB_DEFER_RECORD_SIZE
                ldir
                ld    c,0
                call  defer_remove_index
                ld    de,(MSX_DEFER_CURRENT+2)
                call  owner_validate
                ret   nc                        ; stale receiver: deterministic drop
                ld    a,e
                dec   a
                ld    c,a
                ld    hl,MSX_APP_FLAGS
                add   a,l
                ld    l,a
                bit   2,(hl)
                ret   nz                        ; terminating endpoints never run
                ld    hl,MSX_DEFER_HANDLER_LO
                ld    a,c
                add   a,l
                ld    l,a
                ld    e,(hl)
                ld    hl,MSX_DEFER_HANDLER_HI
                ld    a,c
                add   a,l
                ld    l,a
                ld    d,(hl)
                ld    a,d
                or    e
                ret   z
                ex    de,hl                     ; HL=handler
                ld    a,c
                ld    de,MSX_APP_CODE_NATIVE
                add   a,e
                ld    e,a
                ld    a,(de)
                or    a
                ret   z
                ld    c,a                       ; target native mapper segment
                ld    a,(MSX_DEFER_CURRENT+2)  ; precompute receiver's primary window
                dec   a
                ld    de,MSX_APP_PRIMARY_WIN
                add   a,e
                ld    e,a
                ld    a,(de)
                ld    (MSX_DEFER_ACTIVATE),a
                ld    a,1
                ld    (MSX_DEFER_BUSY),a
                ld    a,(bank_cur)
                push  af
                ld    a,c
                call  bank_set                  ; preserves HL=handler
                ld    a,GB_MSG_DEFER
                ld    (GB_MSG),a
                ld    a,(MSX_DEFER_CURRENT+4)
                ld    (GB_MSG+1),a
                ld    a,(MSX_DEFER_CURRENT+5)
                ld    (GB_MSG+2),a
                xor   a                         ; handler response: nonzero requests activation
                ld    (GB_MSG+3),a
                call  md_call
                pop   af
                call  bank_set
                xor   a
                ld    (MSX_DEFER_BUSY),a
                ld    a,(GB_MSG+3)
                or    a
                ret   z
                ld    a,(MSX_DEFER_ACTIVATE)
                cp    #FF
                ret   z
                ld    c,a
                call  wm_entry
                ld    de,WM_FR_FLAGS
                add   hl,de
                bit   0,(hl)
                ret   z
                ld    a,c
                call  wm_set_clip                ; repaint only the raised endpoint window
                ld    a,c
                call  wm_raise
                jp    wm_repaint_top

; Architecture Milestone 4 public gate. The application binding marshals only
; fixed-size values and at most 512 bytes into page-3 RAM. The paged module owns
; all branchy filesystem policy; the resident path only captures the implicit
; generation-tagged caller and rejects worker-task entry.
k_fsctx
                ld    (MSX_FSCTX_OP),a
                cp    #FE                     ; private module leaf: path in native-FIB workspace
                jr    z,kfsctx_chdir
                if PREEMPTIVE_CONTEXT
                ld    a,(SCHED_CURRENT)
                or    a
                jr    nz,kfsctx_context
                endif
                call  owner_current
                ld    (MSX_FSCTX_OWNER),de
                ld    a,d
                or    e
                jr    z,kfsctx_context
                ld    hl,gbfsctx_modname
                call  run_data_module
                jr    c,kfsctx_result
                ld    a,GB_FSCTX_ERR_UNSUPPORTED
                jr    kfsctx_store
kfsctx_context ld    a,GB_FSCTX_ERR_CONTEXT
kfsctx_store   ld    (MSX_FSCTX_STATUS),a
kfsctx_result  ld    a,(MSX_FSCTX_STATUS)
                ld    de,(MSX_FSCTX_HANDLE)
                ret
; A paged module cannot execute even one instruction after BDOS has restored
; the process TPA bank. Keep _CHDIR resident, then re-map PAGE_DATA before RET.
; Return the native zero/nonzero DOS result directly to GBFSCTX.MOD.
kfsctx_chdir   ei
                push  ix
                ld    c,#5A
                ld    de,MSX_FSCTX_FIB
                call  BDOS
                pop   ix
                push  af
                call  fsmx_restore_page
                pop   af
                ret
gbfsctx_modname db   "GBFSCTX MOD"

; Owner teardown cannot depend on storage or on the paged module still being
; loadable. Four fixed records are cheap to scan resident; no native DOS handle
; remains open between bounded calls, so invalidating matching records is the
; complete close/cancel action. The one-shot launch transfer owns no resource
; and is overwritten/consumed by the next prepare/adopt pair.
fsctx_owner_cleanup
                ld    ix,MSX_FSCTX_TABLE
                ld    b,MSX_FSCTX_MAX
kfoc_loop      ld    a,(ix+0)
                or    a
                jr    z,kfoc_next
                ld    a,(MSX_ALLOC_OWNER)
                cp    (ix+2)
                jr    nz,kfoc_next
                ld    a,(MSX_ALLOC_OWNER+1)
                cp    (ix+3)
                jr    nz,kfoc_next
                ld    (ix+0),0
kfoc_next      ld    de,MSX_FSCTX_RECORD_SIZE
                add   ix,de
                djnz  kfoc_loop
                ret

                endif
                ifndef GB_DEFER_LATE
                include "core/app_lifetime.asm"
                endif
