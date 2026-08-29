; kernel/msx_page_pool.asm - MSX2 owner identities and 16 KiB page handles.
;
; Architecture milestone 1 (#31) separates mapper capacity from WM_MAXWIN.
; DOS mapper segments are retained once at boot, while the public allocator
; exposes generation-tagged handles instead of native segment numbers.  The
; existing resident picture/GBR paths keep using wm_alloc_page/wm_free_page as
; privileged compatibility helpers; their allocations still receive the owner
; of the focused application and are reclaimed when that owner closes.

GB_OWNER_MAX          equ 8

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
GB_SYSINFO_V1         equ 1
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
GB_CAPS_MSX_M1        equ GB_CAP_WINDOWS|GB_CAP_EVENTS|GB_CAP_FILESYSTEM|GB_CAP_SHELL|GB_CAP_NETWORK|GB_CAP_GBR|GB_CAP_PAGE_ALLOC|GB_CAP_OWNER_ID|GB_CAP_RUNTIME_VIDEO

; app_pool_init: retain the TPA page-1 segment plus every available mapper
; segment, up to MSX_PAGE_MAX.  PAGE_DATA was already allocated separately by
; msx_mem_init.  The TPA entry is never returned through FRE_SEG.
app_pool_init
                ld    hl,MSX_PAGE_STATE
                ld    de,MSX_PAGE_STATE+1
                ld    bc,MSX_SYSINFO+MSX_SYSINFO_SIZE-MSX_PAGE_STATE-1
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
                ld    a,GB_SYSINFO_V1
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
                ld    hl,GB_CAPS_MSX_M1
                ld    (MSX_SYS_CAPS),hl
                ld    hl,0
                ld    (MSX_SYS_RESERVED),hl
                ret

; owner_alloc -> DE = generation-tagged owner handle, CF set; DE=0, NC if full.
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

; owner_current -> DE = pending loader owner, mapped application owner, focused
; window owner, or zero. The mapped page is authoritative during callbacks for
; windows below the focus in z-order.
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

; owner_bind_pending_window: attach the pending owner (or the owner already
; associated with the caller page) to wm_slot, then consume the pending handle.
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
                ld    c,a
                ld    hl,MSX_WIN_OWNER
                add   a,l
                ld    l,a
                ld    (hl),e
                ld    hl,MSX_WIN_OWNER_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    (hl),d
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

; GB_SYSINFO #80C3: return an immutable v1 record in page-3 RAM. Only the free
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
