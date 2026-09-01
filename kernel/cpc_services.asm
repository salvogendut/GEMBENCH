; CPC adapter for the target-neutral owner, shell, and deferred-message ABI.
;
; Universal applications call the same #80C0..#80CF entries and carry the same
; bytes on MSX2 and CPC.  MSX2 keeps the broker in resident page-3 code; CPC
; keeps this equivalent implementation beside the shared scheduler because its
; resident kernel must retain the guarded UniDOS stack gap.
;
; CPC application identity is the generation-tagged 16 KiB page allocation,
; not the focused window.  Consequently several windows mapped from one code
; page share one owner and one endpoint, matching the MSX application contract.

CPCS_ENDPOINT_MAX       equ 8
CPCS_ENDPOINT_SIZE      equ 8
CPCS_QUEUE_MAX          equ 8
CPCS_RECORD_SIZE        equ 8

CPCS_EP_OWNER_LO        equ 0
CPCS_EP_OWNER_HI        equ 1
CPCS_EP_HANDLER_LO      equ 2
CPCS_EP_HANDLER_HI      equ 3
CPCS_EP_SERVICE         equ 4
CPCS_EP_ACCESSORY       equ 5
CPCS_EP_PRIMARY         equ 6

CPCS_WM_SHELL_MASK      equ #E0
CPCS_WK_STANDARD        equ 31
CPCS_WK_LEGACY          equ 7
CPCS_WK_EXTENDED        equ #80
CPCS_WK_ABI_V1          equ #B6

CPCS_SHELL_ACCESSORY_CLASS equ #A0
CPCS_SHELL_OPEN         equ 1
CPCS_SHELL_QUIT         equ 4
CPCS_SHELL_STALE_CODE   equ 2
CPCS_SHELL_BUSY_CODE    equ 3
CPCS_SHELL_BAD_CODE     equ 4
CPCS_SHELL_NOHANDLER_CODE equ 5

CPCS_DEFER_STALE_CODE   equ 2
CPCS_DEFER_NOHANDLER_CODE equ 3
CPCS_DEFER_FULL_CODE    equ 4
CPCS_DEFER_BADARG       equ 5
CPCS_DEFER_CONTEXT_CODE equ 6
CPCS_PRIVATE_LOAD       equ #80D2
CPCS_GBAP4_GATE         equ #2200
CPCS_GBAP4_SIZE         equ 1201
CPCS_GBAP4_STAGE        equ #0600
CPCS_FS_ENT_SIZE        equ #14E8

; Installed window-kind registration.  The renderer continues to consume the
; same CPC_WIN_KIND array; only the tiny adapter moved into the shared runtime.
sched_cpc_kind_register
                ld    a,(CPC_KIND_SELECTOR)
                cp    CPCS_WK_ABI_V1
                ld    c,CPCS_WK_LEGACY
                jr    nz,cpcs_kind_store
                ld    a,(WM_FOCUS)
                call  sched_wm_entry
                ld    de,WM_FR_FRAME
                add   hl,de
                ld    e,(hl)
                inc   hl
                ld    d,(hl)
                ex    de,hl
                ld    de,12
                add   hl,de
                ld    a,(hl)
                and   CPCS_WK_STANDARD
                or    CPCS_WK_EXTENDED
                ld    c,a
cpcs_kind_store
                ld    a,(WM_FOCUS)
                ld    hl,CPC_WIN_KIND
                add   a,l
                ld    l,a
                ld    (hl),c
                ret

; A = native CPC page selector -> DE = generation-tagged allocation owner, CF;
; DE=0, NC if the page is not one current busy allocation.
cpcs_owner_for_page
                ld    (cpcs_page),a
                ld    a,(APP_NPAGES)
                ld    b,a
                ld    c,0
                ld    hl,APP_PAGES
cpcs_ofp_loop  ld    a,(cpcs_page)
                cp    (hl)
                jr    z,cpcs_ofp_found
                inc   hl
                inc   c
                djnz  cpcs_ofp_loop
cpcs_owner_none
                ld    de,0
                or    a
                ret
cpcs_ofp_found ld    b,0
                ld    hl,APP_BUSY
                add   hl,bc
                ld    a,(hl)
                or    a
                jr    z,cpcs_owner_none
                ld    hl,CPC_PAGE_GEN
                add   hl,bc
                ld    a,(hl)
                or    a
                jr    z,cpcs_owner_none
                ld    d,a
                ld    a,c
                inc   a
                ld    e,a
                scf
                ret

; Public GB_OWNER implementation: the mapped code page is authoritative during
; callbacks and repaint, so an unfocused application never inherits focus's ID.
sched_cpc_owner_current
                ld    a,(BANK_CUR)
                jp    cpcs_owner_for_page

; GB_APP's window handle remains distinct from GB_OWNER. The current CPC gate
; has one primary window per universal app; use the mapped page to avoid handing
; an unfocused repaint callback the focused window's identity.
sched_cpc_window_current
                ld    a,(BANK_CUR)
                ld    (cpcs_page),a
                ld    a,(WM_NWIN)
                or    a
                jr    z,cpcs_window_none
                dec   a
                ld    b,a
cpcs_winc_loop ld    hl,WM_Z
                ld    a,b
                add   a,l
                ld    l,a
                ld    a,(hl)
                ld    c,a
                push  bc
                call  sched_wm_entry
                pop   bc
                ld    a,(cpcs_page)
                cp    (hl)
                jr    z,cpcs_winc_found
                ld    a,b
                or    a
                jr    z,cpcs_window_none
                dec   b
                jr    cpcs_winc_loop
cpcs_winc_found
                ld    a,c
                ld    hl,CPC_WIN_GEN
                add   a,l
                ld    l,a
                ld    d,(hl)
                ld    a,c
                inc   a
                ld    e,a
                ret
cpcs_window_none
                ld    de,0
                ret

; Reload and validate the paged GBAP v4 admission gate before every launch.
; #80D2/A=#FE is a CPC-kernel-private bounded system-module loader; ordinary
; public FSCTX operations continue to report unsupported.
sched_cpc_gbap4_gate_load
                ld    hl,cpcs_gbap4_name
                ld    de,CPCS_GBAP4_GATE
                ld    bc,CPCS_GBAP4_STAGE
                ld    a,#FE
                call  CPCS_PRIVATE_LOAD
                jr    nc,cpcs_gbap4_bad
                ld    hl,(CPCS_FS_ENT_SIZE+2)
                ld    a,h
                or    l
                jr    nz,cpcs_gbap4_bad
                ld    hl,(CPCS_FS_ENT_SIZE)
                ld    de,CPCS_GBAP4_SIZE
                or    a
                sbc   hl,de
                jr    nz,cpcs_gbap4_bad
                ld    hl,(CPCS_GBAP4_GATE+3)
                ld    de,#4247                 ; "GB"
                or    a
                sbc   hl,de
                jr    nz,cpcs_gbap4_bad
                scf
                ret
cpcs_gbap4_bad or    a
                ret
cpcs_gbap4_name db "GBAPV4  MOD"

; DE = owner -> CF valid, C = zero-based page allocation index.
cpcs_owner_validate
                ld    a,d
                or    a
                jr    z,cpcs_owner_invalid
                ld    a,e
                or    a
                jr    z,cpcs_owner_invalid
                dec   a
                ld    c,a
                ld    b,0
                ld    a,(APP_NPAGES)
                cp    c
                jr    z,cpcs_owner_invalid
                jr    c,cpcs_owner_invalid
                ld    hl,APP_BUSY
                add   hl,bc
                ld    a,(hl)
                or    a
                jr    z,cpcs_owner_invalid
                ld    hl,CPC_PAGE_GEN
                add   hl,bc
                ld    a,(hl)
                cp    d
                jr    nz,cpcs_owner_invalid
                scf
                ret
cpcs_owner_invalid
                or    a
                ret

; A = window slot -> DE = application owner, CF when live.
cpcs_owner_for_window
                cp    WM_MAXWIN
                jp    nc,cpcs_owner_none
                call  sched_wm_entry
                push  hl
                ld    de,WM_FR_FLAGS
                add   hl,de
                bit   0,(hl)
                pop   hl
                jp    z,cpcs_owner_none
                ld    a,(hl)
                jp    cpcs_owner_for_page

; DE = owner -> C = endpoint slot and HL = record, CF when present.
cpcs_endpoint_find
                ld    (cpcs_lookup),de
                ld    hl,cpcs_endpoints
                ld    b,CPCS_ENDPOINT_MAX
                ld    c,0
cpcs_epf_loop  ld    a,(cpcs_lookup)
                cp    (hl)
                jr    nz,cpcs_epf_next
                inc   hl
                ld    a,(cpcs_lookup+1)
                cp    (hl)
                dec   hl
                jr    z,cpcs_epf_found
cpcs_epf_next  ld    de,CPCS_ENDPOINT_SIZE
                add   hl,de
                inc   c
                djnz  cpcs_epf_loop
                or    a
                ret
cpcs_epf_found scf
                ret

; DE = current valid owner -> existing or reclaimed endpoint in HL/C, CF.
cpcs_endpoint_get
                ld    (cpcs_owner),de
                call  cpcs_endpoint_find
                ret   c
                ld    de,(cpcs_owner)
                ld    hl,cpcs_endpoints
                ld    b,CPCS_ENDPOINT_MAX
                ld    c,0
cpcs_epg_loop  ld    a,(hl)
                or    a
                jr    z,cpcs_epg_take
                push  bc
                push  hl
                ld    e,(hl)
                inc   hl
                ld    d,(hl)
                call  cpcs_owner_validate
                pop   hl
                pop   bc
                jr    nc,cpcs_epg_take
                ld    de,CPCS_ENDPOINT_SIZE
                add   hl,de
                inc   c
                djnz  cpcs_epg_loop
                or    a
                ret
cpcs_epg_take  push  hl
                ld    d,h
                ld    e,l
                inc   de
                ld    (hl),0
                ld    bc,CPCS_ENDPOINT_SIZE-1
                ldir
                pop   hl
                ld    de,(cpcs_owner)
                ld    (hl),e
                inc   hl
                ld    (hl),d
                dec   hl
                scf
                ret

; DE = owner -> A = topmost live owned window, CF.
cpcs_window_for_owner
                ld    (cpcs_lookup),de
                ld    a,(WM_NWIN)
                or    a
                jr    z,cpcs_wfo_none
                dec   a
                ld    b,a
cpcs_wfo_loop  ld    hl,WM_Z
                ld    a,b
                add   a,l
                ld    l,a
                ld    a,(hl)
                ld    (cpcs_window),a
                push  bc
                call  cpcs_owner_for_window
                pop   bc
                jr    nc,cpcs_wfo_next
                ld    hl,(cpcs_lookup)
                ld    a,e
                cp    l
                jr    nz,cpcs_wfo_next
                ld    a,d
                cp    h
                jr    z,cpcs_wfo_found
cpcs_wfo_next  ld    a,b
                or    a
                jr    z,cpcs_wfo_none
                dec   b
                jr    cpcs_wfo_loop
cpcs_wfo_found ld    a,(cpcs_window)
                scf
                ret
cpcs_wfo_none  or    a
                ret

; Raise A while retaining NWIN and all relative order. Desktop slot zero remains
; pinned at the bottom; callers only use this for application endpoints.
cpcs_raise
                or    a
                ret   z
                ld    c,a
                ld    a,(WM_NWIN)
                ld    b,a
                ld    hl,WM_Z
cpcs_raise_find
                ld    a,(hl)
                cp    c
                jr    z,cpcs_raise_shift
                inc   hl
                djnz  cpcs_raise_find
                ret
cpcs_raise_shift
                dec   b
                jr    z,cpcs_raise_store
cpcs_raise_one inc   hl
                ld    a,(hl)
                dec   hl
                ld    (hl),a
                inc   hl
                djnz  cpcs_raise_one
cpcs_raise_store
                ld    (hl),c
                ret

; A = activation slot. Capture exact old/new focus damage, update z-order, and
; force the resident root loop to install the new handler/menu on its next map.
cpcs_focus
                ld    (cpcs_window),a
                ld    a,(WM_FOCUS)
                ld    (WM_OPEN_BACK),a
                ld    a,(cpcs_window)
                ld    (WM_SLOT),a
                ld    (WM_FOCUS),a
                call  sched_focus_damage
                ld    a,(cpcs_window)
                call  cpcs_raise
                ld    a,#FF
                ld    (WM_FPREV),a
                ret

; A = slot; publish the managed rectangle for callbacks invoked before the next
; ordinary compositor frame.
cpcs_publish_rect
                call  sched_wm_entry
                inc   hl
                ld    de,MW_RECT
                ld    bc,4
                ldir
                ret

; Find a provider by class B and optional exact accessory C. Returns the same
; short-lived slot+1 handle used by MSX2, or zero.
cpcs_shell_find
                ld    a,b
                and   CPCS_WM_SHELL_MASK
                ret   z
                ld    (cpcs_class),a
                ld    a,c
                ld    (cpcs_accessory),a
                ld    a,(WM_NWIN)
                or    a
                jr    z,cpcs_shf_missing
                dec   a
                ld    b,a
cpcs_shf_loop  ld    hl,WM_Z
                ld    a,b
                add   a,l
                ld    l,a
                ld    a,(hl)
                ld    (cpcs_window),a
                push  bc
                call  cpcs_owner_for_window
                pop   bc
                jr    nc,cpcs_shf_next
                call  cpcs_endpoint_find
                jr    nc,cpcs_shf_next
                ld    de,CPCS_EP_SERVICE
                add   hl,de
                ld    a,(cpcs_class)
                cp    (hl)
                jr    nz,cpcs_shf_next
                ld    a,(cpcs_accessory)
                or    a
                jr    z,cpcs_shf_found
                inc   hl
                cp    (hl)
                jr    z,cpcs_shf_found
cpcs_shf_next  ld    a,b
                or    a
                jr    z,cpcs_shf_missing
                dec   b
                jr    cpcs_shf_loop
cpcs_shf_found ld    a,(cpcs_window)
                inc   a
                ret
cpcs_shf_missing
                xor   a
                ret

; GB_SHELL #80C0: same five operations and callback message as MSX2.
sched_cpc_shell
                or    a
                jr    z,cpcs_shell_register
                dec   a
                jp    z,cpcs_shell_find
                dec   a
                jp    z,cpcs_shell_send
                dec   a
                jr    z,cpcs_shell_register_accessory
                dec   a
                jr    z,cpcs_shell_find_accessory
cpcs_shell_bad ld    a,CPCS_SHELL_BAD_CODE
                ret

cpcs_shell_register
                ld    a,b
                and   CPCS_WM_SHELL_MASK
                jr    z,cpcs_shell_bad
                ld    (cpcs_class),a
                call  sched_cpc_owner_current
                jr    nc,cpcs_shell_bad
                call  cpcs_endpoint_get
                jr    nc,cpcs_shell_bad
                ld    de,CPCS_EP_SERVICE
                add   hl,de
                ld    a,(cpcs_class)
                ld    (hl),a
                ld    de,(cpcs_owner)
                call  cpcs_window_for_owner
                jr    nc,cpcs_shell_no_handler
                ld    (cpcs_window),a
                ld    de,(cpcs_owner)
                call  cpcs_endpoint_find
                jr    nc,cpcs_shell_bad
                ld    de,CPCS_EP_PRIMARY
                add   hl,de
                ld    a,(cpcs_window)
                ld    (hl),a
                xor   a
                ret
cpcs_shell_no_handler
                ld    a,CPCS_SHELL_NOHANDLER_CODE
                ret

cpcs_shell_register_accessory
                ld    a,c
                or    a
                jr    z,cpcs_shell_bad
                ld    (cpcs_accessory),a
                ld    b,CPCS_SHELL_ACCESSORY_CLASS
                call  cpcs_shell_register
                or    a
                ret   nz
                call  sched_cpc_owner_current
                call  cpcs_endpoint_find
                jr    nc,cpcs_shell_bad
                ld    de,CPCS_EP_ACCESSORY
                add   hl,de
                ld    a,(cpcs_accessory)
                ld    (hl),a
                xor   a
                ret

cpcs_shell_find_accessory
                ld    a,c
                or    a
                ret   z
                ld    b,CPCS_SHELL_ACCESSORY_CLASS
                jp    cpcs_shell_find

cpcs_shell_send
                ld    a,(cpcs_shell_busy)
                or    a
                jp    nz,cpcs_shell_busy_result
                ld    a,c
                or    a
                jr    z,cpcs_shell_bad
                cp    CPCS_SHELL_QUIT+1
                jr    nc,cpcs_shell_bad
                ld    (cpcs_request),a
                ld    a,b
                or    a
                jp    z,cpcs_shell_stale
                dec   a
                cp    WM_MAXWIN
                jp    nc,cpcs_shell_stale
                ld    (cpcs_window),a
                push  hl
                call  cpcs_owner_for_window
                jp    nc,cpcs_shell_pop_stale
                call  cpcs_endpoint_find
                jp    nc,cpcs_shell_pop_stale
                ld    de,CPCS_EP_SERVICE
                add   hl,de
                ld    a,(hl)
                or    a
                jr    z,cpcs_shell_pop_stale
                ld    a,(cpcs_window)
                call  sched_wm_entry
                push  hl
                ld    de,WM_FR_EVENT
                add   hl,de
                ld    e,(hl)
                inc   hl
                ld    d,(hl)
                ld    a,d
                or    e
                jr    z,cpcs_shell_pop_no_handler
                ld    (cpcs_handler),de
                pop   de                       ; discard saved window entry
                pop   hl                       ; optional caller argument
                ld    a,(cpcs_request)
                cp    CPCS_SHELL_OPEN
                jr    nz,cpcs_shell_deliver
                ld    a,h
                or    l
                jp    z,cpcs_shell_bad
                ld    de,WM_DRAGNAME
                ld    bc,11
                ldir
cpcs_shell_deliver
                ld    a,1
                ld    (cpcs_shell_busy),a
                ld    a,(BANK_CUR)
                ld    (cpcs_back_page),a
                ld    a,(cpcs_window)
                call  cpcs_focus
                ld    a,(cpcs_window)
                call  cpcs_publish_rect
                ld    a,(cpcs_window)
                call  sched_wm_entry
                ld    a,(hl)
                call  sched_bank_set
                ld    a,(cpcs_request)
                ld    (GB_MSG+1),a
                xor   a
                ld    (GB_MSG+2),a
                ld    (GB_MSG+3),a
                ld    a,GB_MSG_SHELL
                ld    (GB_MSG),a
                ld    hl,(cpcs_handler)
                call  sched_md_call
                ld    a,(GB_MSG+2)
                ld    (cpcs_result),a
                ld    a,(cpcs_back_page)
                call  sched_bank_set
                xor   a
                ld    (cpcs_shell_busy),a
                call  GB_RESTPAR
                ld    a,(cpcs_result)
                ret
cpcs_shell_pop_stale
                pop   hl
                pop   hl
cpcs_shell_stale
                ld    a,CPCS_SHELL_STALE_CODE
                ret
cpcs_shell_pop_no_handler
                pop   hl
                pop   hl
                jp    cpcs_shell_no_handler
cpcs_shell_busy_result
                ld    a,CPCS_SHELL_BUSY_CODE
                ret

; GB_DEFER #80CF dispatcher.
sched_cpc_defer
                or    a
                jp    z,cpcs_defer_register
                dec   a
                jp    z,cpcs_defer_send
                dec   a
                jp    z,cpcs_defer_current
                dec   a
                jp    z,cpcs_defer_free
                dec   a
                jp    z,cpcs_defer_find_service
                dec   a
                jp    z,cpcs_defer_find_accessory
                dec   a
                jp    z,cpcs_defer_cancel_all
cpcs_defer_bad ld    a,CPCS_DEFER_BADARG
                ret

cpcs_defer_register
                ld    (cpcs_handler),hl
                ld    a,(SCHED_CURRENT)
                or    a
                jp    nz,cpcs_defer_context
                call  sched_cpc_owner_current
                jp    nc,cpcs_defer_context
                ld    (cpcs_owner),de
                call  cpcs_endpoint_get
                jp    nc,cpcs_defer_context
                ld    de,CPCS_EP_HANDLER_LO
                add   hl,de
                ld    de,(cpcs_handler)
                ld    (hl),e
                inc   hl
                ld    (hl),d
                ld    a,d
                or    e
                jr    nz,cpcs_defer_ok
                ld    de,(cpcs_owner)
                xor   a                         ; unregister purges both directions
                call  cpcs_defer_purge
cpcs_defer_ok  xor   a
                ret

cpcs_defer_send
                ld    (cpcs_send_ptr),hl
                ld    a,(SCHED_CURRENT)
                or    a
                jp    nz,cpcs_defer_context
                call  sched_cpc_owner_current
                jp    nc,cpcs_defer_context
                ld    (cpcs_owner),de
                ld    hl,(cpcs_send_ptr)
                ld    e,(hl)
                inc   hl
                ld    d,(hl)
                inc   hl
                ld    a,(hl)
                or    a
                jp    z,cpcs_defer_bad
                ld    (cpcs_receiver),de
                call  cpcs_owner_validate
                jp    nc,cpcs_defer_stale
                call  cpcs_endpoint_find
                jp    nc,cpcs_defer_no_handler
                ld    de,CPCS_EP_HANDLER_LO
                add   hl,de
                ld    a,(hl)
                inc   hl
                or    (hl)
                jp    z,cpcs_defer_no_handler
                ld    a,(cpcs_queue_count)
                cp    CPCS_QUEUE_MAX
                jp    nc,cpcs_defer_full
                push  af
                call  cpcs_record_ptr
                ex    de,hl
                ld    hl,cpcs_owner
                ld    bc,2
                ldir
                ld    hl,(cpcs_send_ptr)
                ld    bc,6
                ldir
                pop   af
                inc   a
                ld    (cpcs_queue_count),a
                xor   a
                ret

cpcs_defer_current
                ld    a,(cpcs_defer_busy)
                or    a
                jr    z,cpcs_defer_no_current
                ld    de,cpcs_current
                ret
cpcs_defer_no_current
                ld    de,0
                ret
cpcs_defer_free
                ld    a,(cpcs_queue_count)
                ld    b,a
                ld    a,CPCS_QUEUE_MAX
                sub   b
                ret
cpcs_defer_find_service
                ld    c,0
                call  cpcs_shell_find
                jr    cpcs_defer_owner_for_handle
cpcs_defer_find_accessory
                call  cpcs_shell_find_accessory
cpcs_defer_owner_for_handle
                or    a
                jr    z,cpcs_defer_no_current
                dec   a
                jp    cpcs_owner_for_window

cpcs_defer_cancel_all
                ld    a,(SCHED_CURRENT)
                or    a
                jr    nz,cpcs_defer_context
                call  sched_cpc_owner_current
                jr    nc,cpcs_defer_context
                ld    a,1                         ; explicit cancel: sender only
                jp    cpcs_defer_purge
cpcs_defer_stale
                ld    a,CPCS_DEFER_STALE_CODE
                ret
cpcs_defer_no_handler
                ld    a,CPCS_DEFER_NOHANDLER_CODE
                ret
cpcs_defer_full ld    a,CPCS_DEFER_FULL_CODE
                ret
cpcs_defer_context
                ld    a,CPCS_DEFER_CONTEXT_CODE
                ret

; A = record index -> HL.
cpcs_record_ptr
                add   a,a
                add   a,a
                add   a,a
                ld    e,a
                ld    d,0
                ld    hl,cpcs_queue
                add   hl,de
                ret

; Remove queue record C while preserving FIFO order.
cpcs_defer_remove
                ld    a,(cpcs_queue_count)
                dec   a
                ld    (cpcs_queue_count),a
                sub   c
                ret   z
                ld    b,a
                ld    a,c
                call  cpcs_record_ptr
                push  hl
                ld    de,CPCS_RECORD_SIZE
                add   hl,de
                pop   de
                ld    a,b
                add   a,a
                add   a,a
                add   a,a
                ld    c,a
                ld    b,0
                ldir
                ret

; DE owner, A=0 both directions / 1 sender only -> A records removed.
cpcs_defer_purge
                ld    (cpcs_purge_mode),a
                ld    (cpcs_owner),de
                xor   a
                ld    (cpcs_index),a
                ld    (cpcs_removed),a
cpcs_purge_loop
                ld    a,(cpcs_index)
                ld    c,a
                ld    a,(cpcs_queue_count)
                cp    c
                jr    z,cpcs_purge_done
                jr    c,cpcs_purge_done
                ld    a,c
                call  cpcs_record_ptr
                ld    de,(cpcs_owner)
                ld    a,(hl)
                cp    e
                jr    nz,cpcs_purge_receiver
                inc   hl
                ld    a,(hl)
                cp    d
                jr    z,cpcs_purge_remove
                dec   hl
cpcs_purge_receiver
                ld    a,(cpcs_purge_mode)
                or    a
                jr    nz,cpcs_purge_keep
                inc   hl
                inc   hl
                ld    a,(hl)
                cp    e
                jr    nz,cpcs_purge_keep
                inc   hl
                ld    a,(hl)
                cp    d
                jr    nz,cpcs_purge_keep
cpcs_purge_remove
                ld    a,(cpcs_index)
                ld    c,a
                call  cpcs_defer_remove
                ld    hl,cpcs_removed
                inc   (hl)
                jr    cpcs_purge_loop
cpcs_purge_keep
                ld    hl,cpcs_index
                inc   (hl)
                jr    cpcs_purge_loop
cpcs_purge_done
                ld    a,(cpcs_removed)
                ret

; One bounded asynchronous delivery from the shared root loop.
sched_cpc_defer_dispatch
                ld    a,(cpcs_defer_busy)
                or    a
                ret   nz
                ld    a,(cpcs_queue_count)
                or    a
                ret   z
                ld    hl,cpcs_queue
                ld    de,cpcs_current
                ld    bc,CPCS_RECORD_SIZE
                ldir
                ld    c,0
                call  cpcs_defer_remove
                ld    de,(cpcs_current+2)
                call  cpcs_owner_validate
                ret   nc
                ld    de,(cpcs_current+2)
                call  cpcs_endpoint_find
                ret   nc
                push  hl
                ld    de,CPCS_EP_HANDLER_LO
                add   hl,de
                ld    e,(hl)
                inc   hl
                ld    d,(hl)
                ld    a,d
                or    e
                pop   hl
                ret   z
                ld    (cpcs_handler),de
                ld    de,(cpcs_current+2)
                call  cpcs_window_for_owner
                ret   nc
                ld    (cpcs_window),a
                ld    a,(BANK_CUR)
                ld    (cpcs_back_page),a
                ld    a,1
                ld    (cpcs_defer_busy),a
                ld    a,(cpcs_window)
                call  sched_wm_entry
                ld    a,(hl)
                call  sched_bank_set
                ld    a,GB_MSG_DEFER
                ld    (GB_MSG),a
                ld    a,(cpcs_current+4)
                ld    (GB_MSG+1),a
                ld    a,(cpcs_current+5)
                ld    (GB_MSG+2),a
                xor   a
                ld    (GB_MSG+3),a
                ld    hl,(cpcs_handler)
                call  sched_md_call
                ld    a,(GB_MSG+3)
                ld    (cpcs_result),a
                ld    a,(cpcs_back_page)
                call  sched_bank_set
                xor   a
                ld    (cpcs_defer_busy),a
                ld    a,(cpcs_result)
                or    a
                ret   z
                ld    a,(cpcs_window)
                call  cpcs_focus
                jp    GB_RESTPAR

; Fixed-runtime state. The kernel loads this initialized image before any
; service can run, so zero-filled tables are also the boot reset operation.
cpcs_page       db 0
cpcs_class      db 0
cpcs_accessory  db 0
cpcs_request    db 0
cpcs_result     db 0
cpcs_window     db 0
cpcs_back_page  db 0
cpcs_shell_busy db 0
cpcs_defer_busy db 0
cpcs_queue_count db 0
cpcs_index      db 0
cpcs_removed    db 0
cpcs_purge_mode db 0
cpcs_owner      dw 0
cpcs_lookup     dw 0
cpcs_receiver   dw 0
cpcs_handler    dw 0
cpcs_send_ptr   dw 0
cpcs_endpoints  defs CPCS_ENDPOINT_MAX*CPCS_ENDPOINT_SIZE,0
cpcs_current    defs CPCS_RECORD_SIZE,0
cpcs_queue      defs CPCS_QUEUE_MAX*CPCS_RECORD_SIZE,0
