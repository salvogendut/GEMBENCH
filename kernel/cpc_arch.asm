; CPC architecture adapter for the compile-once GEOBENCH-2 ABI.
;
; The CPC resident kernel has only a guarded 256-byte stack gap below UniDOS,
; so scheduling plus owner/shell/deferred services live in fixed low RAM at
; #3000. Code remains resident here; the larger GBAP v4 validator is loaded
; into the ordinary #2200 module workspace only while admitting an app.

CPC_SYSINFO_SIZE equ 48
CPC_GBAP4_GATE   equ #2200

; Low-word capabilities implemented by the restored shared kernel plus this
; shim: windows, events, filesystem, page allocation, owner identity, runtime
; video, applications, and multiple windows.
CPC_CAPS_LOW    equ   #0FCF
; High-word capabilities initially proved by the CPC gate: strict universal
; loading, runtime geometry, semantic drawing, and normalised pointer input.
CPC_CAPS_HIGH   equ   #004F       ; universal core + shared background timers

; Install the shared scheduler/service runtime before any boot-time geometry,
; window-kind, owner, shell, deferred, or timer entry can be reached.
cpc_scheduler_load
                ld    hl,cpc_scheduler_name
                ld    de,fs_req_name
                call  copy11
                ld    hl,SCHED_BASE
                ld    (fs_load_dst),hl
                ld    hl,3584
                ld    (fs_load_max),hl
                call  fs_load_sys
                ret   nc
                call  SCHED_INIT_ENTRY
                scf
                ret
cpc_scheduler_name db "GBSCHED MOD"

; CPC-private leaf behind the otherwise unsupported GB_FSCTX slot. It gives the
; fixed scheduler a bounded way to reload system modules while preserving the
; pending application's 8.3 name. Public operations 0..n still return 1.
k_cpc_fsctx
                cp    #FE
                jp    nz,k_ret1
                ld    (fs_load_dst),de
                ld    (fs_load_max),bc
                push  hl
                ld    hl,fs_req_name
                ld    de,CPC_GATE_NAME
                call  copy11
                pop   hl
                ld    de,fs_req_name
                call  copy11
                call  fs_load_sys
                push  af
                ld    hl,CPC_GATE_NAME
                ld    de,fs_req_name
                call  copy11
                pop   af
                ret

; cpc_arch_init: publish the immutable fields and seed generation arrays.
cpc_arch_init
                ld    hl,cpc_sysinfo_template
                ld    de,CPC_SYSINFO
                ld    bc,CPC_SYSINFO_SIZE
                ldir
                ld    a,(md_banks)           ; total physical 16K pages = 4 + banks*4
                add   a,a
                add   a,a
                add   a,4
                ld    (CPC_SYSINFO+12),a
                ld    a,(APP_NPAGES)
                ld    (CPC_SYSINFO+13),a
                ld    (CPC_SYSINFO+14),a
                ld    hl,CPC_PAGE_GEN
                ld    de,CPC_PAGE_GEN+1
                ld    bc,CPC_WIN_KIND+8-CPC_PAGE_GEN-1
                                              ; generations + interaction/kind state
                ld    (hl),0
                ldir
                ret

; Refresh the dynamically changing free-page byte in the v6 record.
cpc_page_count_free
                ld    a,(APP_NPAGES)
                ld    b,a
                ld    c,0
                ld    hl,APP_BUSY
cpc_pcf_loop
                ld    a,(hl)
                or    a
                jr    nz,cpc_pcf_next
                inc   c
cpc_pcf_next   inc   hl
                djnz  cpc_pcf_loop
                ld    a,c
                ld    (CPC_SYSINFO+14),a
                ret

; GB_SYSINFO: DE points at the complete v6 record for the process lifetime.
k_cpc_sysinfo
                call  cpc_page_count_free
                ld    de,CPC_SYSINFO
                ret

; Validate HL as a live public page handle. CF=valid, C=zero-based index.
cpc_page_validate
                ld    d,h                     ; caller's generation
                ld    a,d
                or    a
                jr    z,cpc_page_bad
                ld    a,l
                or    a
                jr    z,cpc_page_bad
                dec   a
                ld    c,a
                ld    b,a
                ld    a,(APP_NPAGES)
                cp    b
                jr    c,cpc_page_bad
                jr    z,cpc_page_bad
                ld    hl,APP_BUSY
                ld    b,0
                add   hl,bc
                ld    a,(hl)
                or    a
                jr    z,cpc_page_bad
                ld    hl,CPC_PAGE_GEN
                add   hl,bc
                ld    a,(hl)
                cp    d
                jr    nz,cpc_page_bad
                scf
                ret
cpc_page_bad   or    a
                ret

; GB_PAGE dispatcher. Success status is zero, matching the inherited API.
k_cpc_page
                or    a
                jr    z,cpc_page_alloc
                dec   a
                jr    z,cpc_page_free
                dec   a
                jr    z,cpc_page_check
                ld    a,6                    ; bad argument
                ret
cpc_page_alloc
                call  wm_alloc_page
                or    a
                jr    z,cpc_page_alloc_fail
                ld    d,a                    ; raw page selector
                ld    a,(APP_NPAGES)
                ld    b,a
                ld    c,0
                ld    hl,APP_PAGES
cpc_page_find  ld    a,(hl)
                cp    d
                jr    z,cpc_page_found
                inc   hl
                inc   c
                djnz  cpc_page_find
cpc_page_alloc_fail
                ld    de,0
                ret
cpc_page_found ld    a,c
                ld    hl,CPC_PAGE_GEN
                ld    b,0
                add   hl,bc
                ld    d,(hl)                 ; wm_alloc_page advanced this generation
                ld    a,c
                inc   a
                ld    e,a
                call  cpc_page_count_free
                ret
cpc_page_free  push  hl
                call  cpc_page_validate
                pop   hl
                jr    nc,cpc_page_stale
                ld    a,l
                dec   a
                ld    c,a
                ld    b,0
                ld    hl,APP_PAGES
                add   hl,bc
                ld    a,(hl)
                call  wm_free_page
                call  cpc_page_count_free
                xor   a
                ret
cpc_page_check
                call  cpc_page_validate
                ld    a,2                    ; stale
                ret   nc
                xor   a
                ret
cpc_page_stale ld    a,2
                ret

; GB_APP subset used by the universal bootstrap. Existing CPC applications are
; already compositor-owned; unsupported lifecycle operations return 1.
k_cpc_app
                cp    1                      ; publish
                jr    z,cpc_app_ok
                cp    2                      ; terminate current window
                jr    z,cpc_app_quit
                cp    3                      ; current window handle
                jp    z,SCHED_CPC_WINDOW_ENTRY
                cp    4                      ; close explicit handle (current only)
                jr    z,cpc_app_close
                cp    5                      ; validate window handle
                jr    z,cpc_app_check
                cp    6                      ; free compositor slots
                jr    z,cpc_app_free
                cp    7                      ; current app window count
                jr    z,cpc_app_count
                cp    8                      ; kernel-owned managed-window drag
                jr    z,cpc_app_drag
                ld    a,1                    ; future operations not yet installed
                ret
cpc_app_quit   call  k_wm_close
cpc_app_ok     xor   a
                ret
cpc_app_close  push  hl
                call  SCHED_CPC_WINDOW_ENTRY
                pop   hl
                or    a
                sbc   hl,de
                ld    a,2
                ret   nz
                call  k_wm_close
                xor   a
                ret
cpc_app_check  push  hl
                call  SCHED_CPC_WINDOW_ENTRY
                pop   hl
                or    a
                sbc   hl,de
                ld    a,2
                ret   nz
                xor   a
                ret
cpc_app_free   ld    a,(WM_NWIN)
                ld    b,a
                ld    a,WM_MAXWIN
                sub   b
                ret
cpc_app_count  ld    a,(WM_NWIN)
                or    a
                ret   z
                ld    a,1
                ret
cpc_app_drag   ld    hl,cpc_drag_name
                call  run_data_module
                ld    a,1
                ret   nc
                xor   a
                ret
cpc_drag_name  db    "GBDRAG  MOD"

; CPC semantic line command. The universal mailbox at #C030 lies in the
; continuously repainted top bar on CPC; consume it synchronously before the
; compositor restores that row. Coordinates are 320x200 top-left pixels.
k_cpc_line
                ld    a,(#C038)
                and   3
                call  GRA_SET_PEN
                ld    de,(#C030)
                sla   e
                rl    d
                ld    hl,199
                ld    bc,(#C032)
                or    a
                sbc   hl,bc
                add   hl,hl
                call  GRA_MOVE_ABS
                ld    de,(#C034)
                sla   e
                rl    d
                ld    hl,199
                ld    bc,(#C036)
                or    a
                sbc   hl,bc
                add   hl,hl
                jp    GRA_LINE_ABS

cpc_sysinfo_template
                db    48,6,1,0               ; size, version, inherited ABI 1.0
                db    2,1                    ; CPC, Mode 1
                dw    320,200
                db    2,4                    ; canonical 2bpp, four pens
                db    0,0,0,8                ; memory/pool/free patched, windows
                dw    CPC_CAPS_LOW,0
                db    8,1,8,0                ; apps, record ABI, windows/app, reserved
                db    8,4,1,0                ; shared bounded deferred-message contract
                db    0
                dw    512
                db    1                      ; serialized filesystem API v1
                dw    CPC_CAPS_HIGH
                db    80,200,4,4             ; logical geometry and semantic pens
                dw    #4000,#7F00,#8000
                db    2,0,3,0                ; universal ABI 2.0, native-Z80 profile
                assert $-cpc_sysinfo_template==CPC_SYSINFO_SIZE,"CPC sysinfo v6 template size"
