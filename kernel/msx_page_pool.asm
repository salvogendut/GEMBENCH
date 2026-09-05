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
; msx_app_lifetime.inc. Step 2F (#73) shares deferred API/FIFO/delivery through
; msx_deferred.inc. Step 2G (#74) shares resident filesystem-owner cleanup and
; paged context policy. Native mapper discovery, sysinfo and FS service gates
; remain here; focus/rendering policy has its own shared units and bindings.
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
                include "msx_deferred.inc"
                include "core/deferred_api.asm"
                include "core/deferred_queue.asm"
                include "core/deferred_purge.asm"
                include "core/deferred_dispatch.asm"

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
                include "msx_fsctx_cleanup.inc"
                include "core/fsctx_cleanup.asm"

                endif
                ifndef GB_DEFER_LATE
                include "core/app_lifetime.asm"
                endif
