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

GB_PAGE_UNSPECIFIED   equ 0
GB_PAGE_APPLICATION   equ 1
GB_PAGE_RESOURCE      equ 2
GB_PAGE_DOCUMENT      equ 3
GB_PAGE_CACHE         equ 4
GB_PAGE_SCRAP         equ 5
GB_PAGE_TEMPORARY     equ 6

GB_PAGE_OK            equ 0
GB_PAGE_ERR_UNSUPPORTED equ 1
GB_PAGE_ERR_STALE     equ 2
GB_PAGE_ERR_OWNER     equ 3
GB_PAGE_ERR_FREE      equ 4
GB_PAGE_ERR_NOMEM     equ 5
GB_PAGE_ERR_BADARG    equ 6

GB_PLATFORM_MSX2      equ 1
GB_SYSINFO_V3         equ 3
GB_PACKING_2BPP       equ 2
GB_PACKING_4BPP       equ 4

GB_CAP_WINDOWS        equ #0001
GB_CAP_EVENTS         equ #0002
GB_CAP_FILESYSTEM     equ #0004
GB_CAP_SHELL          equ #0008
GB_CAP_NETWORK        equ #0010
GB_CAP_GBR            equ #0020
GB_CAP_PAGE_ALLOC     equ #0040
GB_CAP_OWNER_ID       equ #0080
GB_CAP_RUNTIME_VIDEO  equ #0100
GB_CAP_APPLICATIONS   equ #0200
GB_CAP_MULTI_WINDOW   equ #0400
GB_CAP_DEFERRED_MSG   equ #0800
GB_CAPS_MSX_M3        equ GB_CAP_WINDOWS|GB_CAP_EVENTS|GB_CAP_FILESYSTEM|GB_CAP_SHELL|GB_CAP_NETWORK|GB_CAP_GBR|GB_CAP_PAGE_ALLOC|GB_CAP_OWNER_ID|GB_CAP_RUNTIME_VIDEO|GB_CAP_APPLICATIONS|GB_CAP_MULTI_WINDOW|GB_CAP_DEFERRED_MSG

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

; Refresh the allocatable count. The first eight entries have a compatibility
; busy mirror used by older picture clients, so either metadata view reserves
; those pages. Entries 8..31 exist only in the general allocator.
page_count_free
                ld    a,(MSX_PAGE_TOTAL)
                ld    b,a
                ld    c,0
                ld    d,0
mpcf_scan       ld    hl,MSX_PAGE_STATE
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                jr    nz,mpcf_next
                ld    a,c
                cp    WM_MAXWIN
                jr    nc,mpcf_free
                ld    hl,APP_BUSY
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                jr    nz,mpcf_next
mpcf_free       inc   d
mpcf_next       inc   c
                djnz  mpcf_scan
                ld    a,d
                ld    (MSX_PAGE_FREE),a
                ld    (MSX_SYS_POOL_FREE),a
                ret

sysinfo_init
                ld    a,MSX_SYSINFO_SIZE
                ld    (MSX_SYS_SIZE),a
                ld    a,GB_SYSINFO_V3
                ld    (MSX_SYS_VERSION),a
                ld    a,1                     ; frozen GEMBENCH-1 ABI
                ld    (MSX_SYS_ABI_MAJOR),a
                xor   a
                ld    (MSX_SYS_ABI_MINOR),a
                ld    a,GB_PLATFORM_MSX2
                ld    (MSX_SYS_PLATFORM),a
                ifdef MSX_SCREEN7
                ld    a,7
                ld    (MSX_SYS_VIDEO_MODE),a
                ld    a,GB_PACKING_4BPP
                ld    (MSX_SYS_PACKING),a
                ld    a,16
                ld    (MSX_SYS_COLOURS),a
                else
                ld    a,6
                ld    (MSX_SYS_VIDEO_MODE),a
                ld    a,GB_PACKING_2BPP
                ld    (MSX_SYS_PACKING),a
                ld    a,4
                ld    (MSX_SYS_COLOURS),a
                endif
                ld    hl,512
                ld    (MSX_SYS_WIDTH),hl
                ld    hl,212
                ld    (MSX_SYS_HEIGHT),hl
                ld    a,(MSX_TOTSEG)
                ld    (MSX_SYS_MEM_PAGES),a
                ld    a,(MSX_PAGE_TOTAL)
                ld    (MSX_SYS_POOL_TOTAL),a
                ld    a,(MSX_PAGE_FREE)
                ld    (MSX_SYS_POOL_FREE),a
                ld    a,WM_MAXWIN
                ld    (MSX_SYS_MAX_WINDOWS),a
                ld    hl,GB_CAPS_MSX_M3
                ld    (MSX_SYS_CAPS),hl
                ld    hl,0
                ld    (MSX_SYS_RESERVED),hl
                ld    a,GB_APP_MAX
                ld    (MSX_SYS_MAX_APPS),a
                ld    a,1
                ld    (MSX_SYS_APP_VERSION),a
                ld    a,WM_MAXWIN
                ld    (MSX_SYS_MAX_APP_WINDOWS),a
                xor   a
                ld    (MSX_SYS_RESERVED2),a
                ld    a,GB_DEFER_MAX
                ld    (MSX_SYS_MSG_QUEUE),a
                ld    a,4
                ld    (MSX_SYS_MSG_INLINE),a
                ld    a,1
                ld    (MSX_SYS_MSG_VERSION),a
                xor   a
                ld    (MSX_SYS_RESERVED3),a
                ret

; app_record_reset: C = application slot. Clear every reusable field while
; preserving the independent active/generation pair.
app_record_reset
                xor   a
                ld    hl,MSX_APP_CODE_NATIVE
                add   a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,MSX_APP_CODE_PAGE
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,MSX_APP_CODE_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,MSX_APP_WINDOW_COUNT
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,MSX_APP_FLAGS
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,MSX_APP_SERVICE
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,MSX_APP_ACCESSORY
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,MSX_APP_PRIMARY_WIN
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),#FF
                ld    hl,MSX_APP_WORKER_WIN
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),#FF
                ld    hl,MSX_DEFER_HANDLER_LO
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,MSX_DEFER_HANDLER_HI
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ret

; owner_alloc -> DE = generation-tagged application handle, CF set; DE=0, NC
; if the fixed application table is full. GB_OWNER remains a source-compatible
; name for this same identity.
owner_alloc
                ld    hl,MSX_OWNER_ACTIVE
                ld    b,GB_OWNER_MAX
                ld    c,0
moa_scan       ld    a,(hl)
                or    a
                jr    z,moa_take
                inc   hl
                inc   c
                djnz  moa_scan
                ld    de,0
                or    a
                ret
moa_take       ld    (hl),1
                ld    hl,MSX_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                inc   a
                jr    nz,moa_gen_ok
                inc   a                       ; generation zero is never published
moa_gen_ok     ld    (hl),a
                ld    d,a
                ld    a,c
                inc   a
                ld    e,a
                push  de
                call  app_record_reset
                pop   de
                scf
                ret

; owner_validate: DE = handle -> CF valid, NC stale/invalid. Clobbers A,C,HL.
owner_validate
                ld    a,e
                or    a
                jr    z,mov_bad
                dec   a
                cp    GB_OWNER_MAX
                jr    nc,mov_bad
                ld    c,a
                ld    hl,MSX_OWNER_ACTIVE
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                jr    z,mov_bad
                ld    hl,MSX_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    d
                jr    nz,mov_bad
                scf
                ret
mov_bad         or    a                       ; clear carry
                ret

; app_bind_code_page: A = native mapper segment and DE = page handle returned
; by page_alloc_owned. Publish them in the pending application record. Returns
; A = native segment so loader call sites can continue unchanged.
app_bind_code_page
                ld    (MSX_ALLOC_NATIVE),a
                ld    (MSX_ALLOC_HANDLE),de
                ld    de,(MSX_PENDING_OWNER)
                call  owner_validate
                jr    nc,mabcp_done
                ld    a,e
                dec   a
                ld    c,a
                ld    hl,MSX_APP_CODE_NATIVE
                add   a,l
                ld    l,a
                ld    a,(MSX_ALLOC_NATIVE)
                ld    (hl),a
                ld    hl,MSX_APP_CODE_PAGE
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(MSX_ALLOC_HANDLE)
                ld    (hl),a
                ld    hl,MSX_APP_CODE_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(MSX_ALLOC_HANDLE+1)
                ld    (hl),a
mabcp_done     ld    a,(MSX_ALLOC_NATIVE)
                ret

; window_generation_next: A = reusable WM slot -> DE = new opaque window
; handle. A generation is advanced before the slot is published alive.
window_generation_next
                ld    c,a
                ld    hl,MSX_WIN_GEN
                add   a,l
                ld    l,a
                ld    a,(hl)
                inc   a
                jr    nz,mwgn_ok
                inc   a
mwgn_ok         ld    (hl),a
                ld    d,a
                ld    a,c
                inc   a
                ld    e,a
                ret

; window_handle_slot: A = live slot -> DE = generation-tagged handle.
window_handle_slot
                ld    c,a
                ld    hl,MSX_WIN_GEN
                add   a,l
                ld    l,a
                ld    d,(hl)
                ld    a,c
                inc   a
                ld    e,a
                ret

; app_window_attach: A = WM slot, DE = application. Bind the parallel window
; owner link, increment the application window count, and publish its first
; primary window. Returns CF on success.
app_window_attach
                ld    (MSX_WINDOW_SLOT),a
                ld    (MSX_ALLOC_OWNER),de
                call  owner_validate
                ret   nc
                ld    a,e
                dec   a
                ld    (MSX_APP_SLOT),a
                ld    c,a
                ld    a,(MSX_WINDOW_SLOT)
                ld    b,a
                ld    hl,MSX_WIN_OWNER
                add   a,l
                ld    l,a
                ld    (hl),e
                ld    hl,MSX_WIN_OWNER_GEN
                ld    a,b
                add   a,l
                ld    l,a
                ld    (hl),d
                ld    hl,MSX_APP_WINDOW_COUNT
                ld    a,c
                add   a,l
                ld    l,a
                inc   (hl)
                ld    hl,MSX_APP_PRIMARY_WIN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    #FF
                jr    nz,mawa_primary_ok
                ld    a,b
                ld    (hl),a
mawa_primary_ok ld   hl,MSX_APP_FLAGS
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                and   #FF-GB_APP_F_WINDOWLESS
                or    GB_APP_F_PUBLISHED
                ld    (hl),a
                scf
                ret

; app_window_detach: C = WM slot, DE = owning application. Clear the parallel
; link and update primary/worker metadata. Returns A = remaining window count.
app_window_detach
                ld    a,c
                ld    (MSX_WINDOW_SLOT),a
                ld    (MSX_ALLOC_OWNER),de
                call  owner_validate
                jp    nc,mawd_none
                ld    a,e
                dec   a
                ld    (MSX_APP_SLOT),a
                ld    b,a
                ld    hl,MSX_APP_WINDOW_COUNT
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                jr    z,mawd_counted
                dec   (hl)
                dec   a
mawd_counted    ld   (MSX_APP_REMAIN),a
                ld    a,(MSX_WINDOW_SLOT)
                ld    c,a
                ld    hl,MSX_WIN_OWNER
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,MSX_WIN_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,MSX_APP_WORKER_WIN
                ld    a,b
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    c
                jr    nz,mawd_primary
                ld    (hl),#FF
mawd_primary    ld   hl,MSX_APP_PRIMARY_WIN
                ld    a,b
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    c
                jr    nz,mawd_flags
                ld    (hl),#FF
                ld    a,(MSX_ALLOC_OWNER)
                ld    e,a
                ld    a,(MSX_ALLOC_OWNER+1)
                ld    d,a
                ld    b,WM_MAXWIN
                ld    c,0
mawd_find       ld   hl,MSX_WIN_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    e
                jr    nz,mawd_next
                ld    hl,MSX_WIN_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    d
                jr    nz,mawd_next
                ld    a,(MSX_APP_SLOT)
                ld    hl,MSX_APP_PRIMARY_WIN
                add   a,l
                ld    l,a
                ld    (hl),c
                jr    mawd_flags
mawd_next       inc   c
                djnz  mawd_find
mawd_flags      ld   a,(MSX_APP_REMAIN)
                or    a
                jr    nz,mawd_done
                ld    a,(MSX_APP_SLOT)
                ld    hl,MSX_APP_FLAGS
                add   a,l
                ld    l,a
                set   3,(hl)
mawd_done       ld   a,(MSX_APP_REMAIN)
                ret
mawd_none       xor  a
                ret

; window_validate_owned: HL = opaque window handle, DE = current application.
; Returns A=GB_APP_OK and C=slot, or an explicit stale/owner result.
window_validate_owned
                ld    (MSX_WINDOW_HANDLE),hl
                ld    (MSX_ALLOC_OWNER),de
                call  owner_validate
                jr    nc,mwvo_owner
                ld    hl,(MSX_WINDOW_HANDLE)
                ld    a,l
                or    a
                jr    z,mwvo_stale
                dec   a
                cp    WM_MAXWIN
                jr    nc,mwvo_stale
                ld    c,a
                ld    hl,MSX_WIN_GEN
                add   a,l
                ld    l,a
                ld    a,(MSX_WINDOW_HANDLE+1)
                cp    (hl)
                jr    nz,mwvo_stale
                ld    a,c
                call  wm_entry
                ld    de,WM_FR_FLAGS
                add   hl,de
                bit   0,(hl)
                jr    z,mwvo_stale
                ld    de,(MSX_ALLOC_OWNER)
                ld    hl,MSX_WIN_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    e
                jr    nz,mwvo_owner
                ld    hl,MSX_WIN_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    d
                jr    nz,mwvo_owner
                xor   a
                ret
mwvo_stale      ld   a,GB_APP_ERR_STALE
                ret
mwvo_owner      ld   a,GB_APP_ERR_OWNER
                ret

; owner_current -> DE = pending loader application, mapped application, focused
; window application, or zero. The mapped page is authoritative during
; callbacks for windows below the focus in z-order.
owner_current
                ld    de,(MSX_PENDING_OWNER)
                ld    a,d
                or    e
                jr    nz,moc_validate
                ld    a,(bank_cur)
                call  owner_for_native
                ld    a,d
                or    e
                jr    nz,moc_validate
                ld    a,(WM_FOCUS)
                cp    WM_MAXWIN
                jr    nc,moc_none
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
moc_validate    call  owner_validate
                ret   c
moc_none        ld    de,0
                ret

; owner_bind_pending_window: attach the pending application (or the application
; already associated with the caller page) to wm_slot, then consume the pending
; handle. Later windows from the same mapped code page take the second path.
owner_bind_pending_window
                ld    de,(MSX_PENDING_OWNER)
                ld    a,d
                or    e
                jr    nz,mob_have
                ld    a,(bank_cur)
                call  owner_for_native
                ld    a,d
                or    e
                ret   z
mob_have        ld    a,(wm_slot)
                call  app_window_attach
                ret   nc
                ld    hl,0
                ld    (MSX_PENDING_OWNER),hl
                ret

; owner_for_native: A = native mapper segment -> DE = page owner, or zero.
owner_for_native
                ld    (MSX_ALLOC_PURPOSE),a   ; byte scratch: native target
                ld    a,(MSX_PAGE_TOTAL)
                ld    b,a
                ld    c,0
                ld    hl,MSX_PAGE_NATIVE
mof_scan        ld    a,(hl)
                push  hl
                ld    hl,MSX_ALLOC_PURPOSE
                cp    (hl)
                pop   hl
                jr    z,mof_hit
                inc   hl
                inc   c
                djnz  mof_scan
                ld    de,0
                ret
mof_hit         ld    hl,MSX_PAGE_STATE
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                jr    z,mof_none
                ld    hl,MSX_PAGE_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    e,(hl)
                ld    hl,MSX_PAGE_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    d,(hl)
                ret
mof_none        ld    de,0
                ret

; page_alloc_owned: DE = valid owner, B = purpose -> A native segment and
; DE page handle, CF set. On failure A=0, DE=0, NC.
page_alloc_owned
                ld    (MSX_ALLOC_OWNER),de
                ld    a,b
                ld    (MSX_ALLOC_PURPOSE),a
                call  page_count_free
                ld    de,(MSX_ALLOC_OWNER)
                call  owner_validate
                jr    nc,mpa_fail
                ld    a,(MSX_PAGE_TOTAL)
                ld    b,a
                ld    c,0
                ld    hl,MSX_PAGE_STATE
mpa_scan        ld    a,(hl)
                or    a
                jr    nz,mpa_next
                ld    a,c
                cp    WM_MAXWIN
                jr    nc,mpa_take
                push  hl
                ld    hl,APP_BUSY
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                pop   hl
                jr    z,mpa_take
mpa_next
                inc   hl
                inc   c
                djnz  mpa_scan
mpa_fail        ld    de,0
                xor   a
                ret
mpa_take        ld    (hl),1
                ld    hl,MSX_PAGE_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                inc   a
                jr    nz,mpa_gen_ok
                inc   a
mpa_gen_ok      ld    (hl),a
                ld    d,a
                ld    a,c
                inc   a
                ld    e,a
                ld    (MSX_ALLOC_HANDLE),de
                ld    de,(MSX_ALLOC_OWNER)
                ld    hl,MSX_PAGE_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),e
                ld    hl,MSX_PAGE_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),d
                ld    hl,MSX_PAGE_PURPOSE
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(MSX_ALLOC_PURPOSE)
                ld    (hl),a
                ld    a,c
                cp    WM_MAXWIN
                jr    nc,mpa_count
                ld    hl,APP_BUSY
                add   a,l
                ld    l,a
                ld    (hl),1
mpa_count       push  bc
                call  page_count_free
                pop   bc
                ld    hl,MSX_PAGE_NATIVE
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                ld    de,(MSX_ALLOC_HANDLE)
                scf
                ret

; page_check_owned: HL = page handle, DE = owner -> A = GB_PAGE_* result.
page_check_owned
                ld    (MSX_ALLOC_HANDLE),hl
                ld    (MSX_ALLOC_OWNER),de
                call  owner_validate
                jr    nc,mpc_owner
                ld    hl,(MSX_ALLOC_HANDLE)
                ld    a,l
                or    a
                jr    z,mpc_stale
                dec   a
                ld    c,a
                ld    a,(MSX_PAGE_TOTAL)
                cp    c
                jr    z,mpc_stale
                jr    c,mpc_stale
                ld    hl,MSX_PAGE_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(MSX_ALLOC_HANDLE+1)
                cp    (hl)
                jr    nz,mpc_stale
                ld    hl,MSX_PAGE_STATE
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                jr    z,mpc_free
                ld    de,(MSX_ALLOC_OWNER)
                ld    hl,MSX_PAGE_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    e
                jr    nz,mpc_owner
                ld    hl,MSX_PAGE_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    d
                jr    nz,mpc_owner
                xor   a
                ret
mpc_stale       ld    a,GB_PAGE_ERR_STALE
                ret
mpc_owner       ld    a,GB_PAGE_ERR_OWNER
                ret
mpc_free        ld    a,GB_PAGE_ERR_FREE
                ret

; page_release_index: C = pool index. Privileged internal primitive.
page_release_index
                ld    hl,MSX_PAGE_STATE
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,MSX_PAGE_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,MSX_PAGE_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    hl,MSX_PAGE_PURPOSE
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    a,c
                cp    WM_MAXWIN
                jr    nc,mpri_count
                ld    hl,APP_BUSY
                add   a,l
                ld    l,a
                ld    (hl),0
mpri_count      jp    page_count_free

page_free_owned
                push  hl
                call  page_check_owned
                pop   hl
                or    a
                ret   nz
                ld    a,l
                dec   a
                ld    c,a
                call  page_release_index
                xor   a
                ret

; Adopt a page reserved through the old APP_BUSY compatibility mirror. Legacy
; Browser/Icon Editor picture clients still need the native segment for
; GB_PICEDIT, but their first kernel transfer makes the reservation owned and
; therefore eligible for automatic release. A = native segment. Best effort;
; an unknown, free, or already-owned page is left unchanged.
page_claim_legacy_native
                ld    (MSX_ALLOC_NATIVE),a
                ld    a,(MSX_PAGE_TOTAL)
                ld    b,a
                ld    c,0
                ld    hl,MSX_PAGE_NATIVE
mpcl_scan       ld    a,(hl)
                push  hl
                ld    hl,MSX_ALLOC_NATIVE
                cp    (hl)
                pop   hl
                jr    z,mpcl_found
                inc   hl
                inc   c
                djnz  mpcl_scan
                ret
mpcl_found      ld    a,c
                cp    WM_MAXWIN
                ret   nc                       ; only the mirror can reserve outside metadata
                ld    hl,MSX_PAGE_STATE
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                ret   nz                       ; already owned by the general allocator
                ld    a,c
                ld    hl,APP_BUSY
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                ret   z                        ; not actually reserved
                ld    a,c
                ld    (MSX_ALLOC_INDEX),a
                call  owner_current
                ld    a,d
                or    e
                ret   z
                ld    (MSX_ALLOC_OWNER),de
                ld    a,(MSX_ALLOC_INDEX)
                ld    c,a
                ld    hl,MSX_PAGE_STATE
                add   a,l
                ld    l,a
                ld    (hl),1
                ld    hl,MSX_PAGE_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                inc   a
                jr    nz,mpcl_gen_ok
                inc   a
mpcl_gen_ok     ld    (hl),a
                ld    de,(MSX_ALLOC_OWNER)
                ld    hl,MSX_PAGE_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),e
                ld    hl,MSX_PAGE_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),d
                ld    hl,MSX_PAGE_PURPOSE
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),GB_PAGE_RESOURCE
                jp    page_count_free

; owner_release: DE = owner. Reclaim all its pages and invalidate the owner.
owner_release
                ld    (MSX_ALLOC_OWNER),de
                call  owner_validate
                jr    nc,mor_stale
                ld    de,(MSX_ALLOC_OWNER)      ; queued sender/receiver endpoints die atomically
                call  defer_purge_owner
                ld    a,(MSX_PAGE_TOTAL)
                ld    b,a
                ld    c,0
mor_pages       push  bc
                ld    hl,MSX_PAGE_STATE
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                jr    z,mor_next
                ld    de,(MSX_ALLOC_OWNER)
                ld    hl,MSX_PAGE_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    e
                jr    nz,mor_next
                ld    hl,MSX_PAGE_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    d
                jr    nz,mor_next
                call  page_release_index
mor_next        pop   bc
                inc   c
                djnz  mor_pages
                ld    de,(MSX_ALLOC_OWNER)
                ld    a,e
                dec   a
                ld    hl,MSX_OWNER_ACTIVE
                add   a,l
                ld    l,a
                ld    (hl),0
                ld    a,e
                dec   a
                ld    c,a
                call  app_record_reset
                ld    b,WM_MAXWIN
                ld    c,0
mor_windows     ld    hl,MSX_WIN_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    e
                jr    nz,mor_win_next
                ld    hl,MSX_WIN_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    d
                jr    nz,mor_win_next
                ld    (hl),0
                ld    hl,MSX_WIN_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),0
mor_win_next    inc   c
                djnz  mor_windows
                ld    hl,(MSX_PENDING_OWNER)
                or    a
                sbc   hl,de
                jr    nz,mor_ok
                ld    hl,0
                ld    (MSX_PENDING_OWNER),hl
mor_ok          xor   a
                ret
mor_stale       ld    a,GB_PAGE_ERR_STALE
                ret

; Legacy internal allocation: use the pending loader owner or focused owner,
; and return the raw mapper segment expected by the existing bank code.
wm_alloc_page
                call  owner_current
                ld    a,d
                or    e
                jr    z,mwa_fail
                ld    b,GB_PAGE_RESOURCE
                call  page_alloc_owned
                ret   c
mwa_fail        xor   a
                ret

; Privileged raw-segment free used by existing picture/GBR code. Public clients
; can only free generation-tagged handles through GB_PAGE.
wm_free_page
                ld    (MSX_ALLOC_PURPOSE),a
                ld    a,(MSX_PAGE_TOTAL)
                ld    b,a
                ld    c,0
                ld    hl,MSX_PAGE_NATIVE
mwf_scan        ld    a,(hl)
                push  hl
                ld    hl,MSX_ALLOC_PURPOSE
                cp    (hl)
                pop   hl
                jr    z,mwf_hit
                inc   hl
                inc   c
                djnz  mwf_scan
                ret
mwf_hit         jp    page_release_index

; GB_SYSINFO #80C3: return an immutable versioned record in page-3 RAM. Only the free
; count is dynamic, so refresh it at the query boundary.
k_sysinfo
                call  page_count_free
                ld    a,(MSX_PAGE_FREE)
                ld    (MSX_SYS_POOL_FREE),a
                ld    de,MSX_SYSINFO
                ret

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
                cp    GB_PAGE_TEMPORARY+1
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
                add   a,#7C
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

                endif
                ifndef GB_DEFER_LATE
; app_mark_root_current: the first Desktop registration owns the immortal root
; application. Explicit quit rejects this record.
app_mark_root_current
                call  owner_current
                call  owner_validate
                ret   nc
                ld    a,e
                dec   a
                ld    hl,MSX_APP_FLAGS
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    GB_APP_F_PUBLISHED|GB_APP_F_ROOT
                ld    (hl),a
                ret

; app_mark_worker_current: record which window supplies the application-owned
; worker callback. The fixed scheduler still snapshots by window slot, but the
; application table is authoritative for lifecycle cleanup and allows only one
; worker registration per application in this milestone.
app_mark_worker_current
                call  owner_current
                call  owner_validate
                ret   nc
                ld    a,e
                dec   a
                ld    c,a
                ld    hl,MSX_APP_WORKER_WIN
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    #FF
                ret   nz
                ld    a,(WM_FOCUS)
                ld    (hl),a
                ret

; app_service_for_window: A = WM slot -> A = owning application's registered
; shell service class, or zero for an ownerless/stale window.
app_service_for_window
                cp    WM_MAXWIN
                jr    nc,masfw_none
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
                jr    nc,masfw_none
                ld    a,e
                dec   a
                ld    hl,MSX_APP_SERVICE
                add   a,l
                ld    l,a
                ld    a,(hl)
                ret
masfw_none      xor  a
                ret

; app_find_window: DE = application -> A = one owned slot, CF; NC when none.
app_find_window
                ld    (MSX_ALLOC_OWNER),de
                ld    b,WM_MAXWIN
                ld    c,0
mafw_scan       ld   hl,MSX_WIN_OWNER
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(MSX_ALLOC_OWNER)
                cp    (hl)
                jr    nz,mafw_next
                ld    hl,MSX_WIN_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(MSX_ALLOC_OWNER+1)
                cp    (hl)
                jr    nz,mafw_next
                ld    a,c
                scf
                ret
mafw_next       inc  c
                djnz  mafw_scan
                xor   a
                ret

; GB_APP #80CC dispatcher (MSX2 Architecture Milestone 2):
;   A=0                    -> DE=current application handle
;   A=1                    -> A=status, publish a windowless application
;   A=2                    -> A=status, terminate current application
;   A=3                    -> DE=current focused window handle
;   A=4, HL=window handle  -> A=status, close an owned window
;   A=5, HL=window handle  -> A=status, validate an owned window
;   A=6                    -> A=free compositor window slots
;   A=7                    -> A=current application live-window count
;   A=8                    -> A=status, drag the focused owned window
k_app
                or    a
                jp    z,owner_current
                dec   a
                jr    z,kapp_publish
                dec   a
                jr    z,kapp_quit
                dec   a
                jp    z,kapp_window_current
                dec   a
                jp    z,kapp_window_close
                dec   a
                jp    z,kapp_window_check
                dec   a
                jp    z,kapp_window_free
                dec   a
                jp    z,kapp_window_count
                dec   a
                jp    z,kapp_window_drag
                ld    a,GB_APP_ERR_BADARG
                ret

kapp_publish    call  owner_current
                call  owner_validate
                jp    nc,kapp_owner
                ld    a,e
                dec   a
                ld    c,a
                ld    hl,MSX_APP_FLAGS
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    GB_APP_F_PUBLISHED
                ld    (hl),a
                ld    hl,MSX_APP_WINDOW_COUNT
                ld    a,c
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a
                jr    nz,kapp_publish_done
                ld    hl,MSX_APP_FLAGS
                ld    a,c
                add   a,l
                ld    l,a
                set   3,(hl)
kapp_publish_done
                ld    hl,0
                ld    (MSX_PENDING_OWNER),hl
                xor   a
                ret

kapp_quit       call  owner_current
                call  owner_validate
                jp    nc,kapp_owner
                ld    (MSX_CLOSE_OWNER),de
                ld    a,e
                dec   a
                ld    c,a
                ld    hl,MSX_APP_FLAGS
                add   a,l
                ld    l,a
                bit   1,(hl)
                jp    nz,kapp_root
                set   2,(hl)
kapp_quit_windows
                ld    de,(MSX_CLOSE_OWNER)
                call  app_find_window
                jr    nc,kapp_quit_release
                ld    c,a
                call  msx_window_close_slot
                ld    de,(MSX_CLOSE_OWNER)
                call  owner_validate
                jr    c,kapp_quit_windows
                xor   a
                ret
kapp_quit_release
                ld    de,(MSX_CLOSE_OWNER)
                call  owner_release
                xor   a
                ret

kapp_window_current
                call  owner_current
                ld    (MSX_ALLOC_OWNER),de
                call  owner_validate
                jr    nc,kapp_window_none
                ld    a,(WM_FOCUS)
                cp    WM_MAXWIN
                jr    nc,kapp_window_none
                call  window_handle_slot
                ld    (MSX_WINDOW_HANDLE),de
                ex    de,hl
                ld    de,(MSX_ALLOC_OWNER)
                call  window_validate_owned
                or    a
                jr    nz,kapp_window_none
                ld    de,(MSX_WINDOW_HANDLE)
                ret
kapp_window_none
                ld    de,0
                ret

kapp_window_close
                push  hl
                call  owner_current
                pop   hl
                call  window_validate_owned
                ret   nz
                call  msx_window_close_slot
                xor   a
                ret

kapp_window_check
                push  hl
                call  owner_current
                pop   hl
                jp    window_validate_owned

kapp_window_free
                ld    a,(WM_NWIN)
                ld    b,a
                ld    a,WM_MAXWIN
                sub   b
                ret

kapp_window_count
                call  owner_current
                call  owner_validate
                jp    nc,kapp_owner
                ld    a,e
                dec   a
                ld    hl,MSX_APP_WINDOW_COUNT
                add   a,l
                ld    l,a
                ld    a,(hl)
                ret

kapp_window_drag
                call  kapp_window_current
                ld    a,d
                or    e
                jr    z,kapp_owner
                ld    a,(WM_FOCUS)
                call  wm_entry
                call  mw_publish
                call  mw_move_silent          ; legacy app records geometry before its repaint
                xor   a
                ret

kapp_root       ld   a,GB_APP_ERR_ROOT
                ret
kapp_owner      ld   a,GB_APP_ERR_OWNER
                ret
                endif
