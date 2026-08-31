; Cooperative CPC architecture shim for the compile-once GEOBENCH-2 ABI.
;
; The CPC resident kernel has only a guarded 256-byte stack gap below UniDOS,
; so persistent metadata lives in the unused cooperative scheduler block at
; #3C00. Code remains resident here; the larger GBAP v4 validator is loaded
; into the ordinary #2200 module workspace only while admitting an app.

                assert !PREEMPTIVE,"CPC v6 metadata currently requires the cooperative #3C00 block"

CPC_SYSINFO_SIZE equ 48

; Low-word capabilities implemented by the restored shared kernel plus this
; shim: windows, events, filesystem, page allocation, owner identity, runtime
; video, applications, and multiple windows.
CPC_CAPS_LOW    equ   #07C7
; High-word capabilities initially proved by the CPC gate: strict universal
; loading, runtime geometry, semantic drawing, and normalised pointer input.
CPC_CAPS_HIGH   equ   #000F

CPC_GBAP4_GATE      equ #2200
CPC_GBAP4_GATE_SIZE equ 1201
; The floppy backend admits AMSDOS files using their record-rounded size
; before it strips the 128-byte header.  The 1201-byte gate therefore needs
; three 512-byte staging sectors even though the validated payload ends at
; #26B1.
CPC_GBAP4_STAGE_SIZE equ #0600

; Reload the strict validator before each launch.  Paged helpers share #2200,
; so retaining it across arbitrary application activity would be unsafe.
cpc_gbap4_gate_load
                ld    hl,fs_req_name
                ld    de,CPC_GATE_NAME
                call  copy11
                ld    hl,cpc_gbap4_name
                ld    de,fs_req_name
                call  copy11
                ld    hl,CPC_GBAP4_GATE
                ld    (fs_load_dst),hl
                ld    hl,CPC_GBAP4_STAGE_SIZE
                ld    (fs_load_max),hl
                call  fs_load_sys
                jr    nc,cpc_gbap4_bad
                ld    hl,(fs_ent_size+2)
                ld    a,h
                or    l
                jr    nz,cpc_gbap4_bad
                ld    hl,(fs_ent_size)
                ld    de,CPC_GBAP4_GATE_SIZE
                or    a
                sbc   hl,de
                jr    nz,cpc_gbap4_bad
                ld    hl,(CPC_GBAP4_GATE+3)
                ld    de,#4247                 ; "GB"
                or    a
                sbc   hl,de
                jr    nz,cpc_gbap4_bad
                scf
                jr    cpc_gbap4_restore
cpc_gbap4_bad  or    a
cpc_gbap4_restore
                push  af
                ld    hl,CPC_GATE_NAME
                ld    de,fs_req_name
                call  copy11
                pop   af
                ret
cpc_gbap4_name db    "GBAPV4  MOD"

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
                ld    bc,CPC_PAGE_MAX+WM_MAXWIN-1 ; page + window generations
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

; GB_OWNER: the restored CPC compositor has one code page per application.
; Window slots therefore provide a compact generation-tagged identity until
; the multi-window owner table is moved into this block later in Gate 3.
k_cpc_owner
                ld    a,(WM_NWIN)
                or    a
                jr    z,cpc_owner_none
                ld    a,(WM_FOCUS)
                ld    c,a
                inc   a
                ld    e,a                    ; low byte = one-based compositor slot
                ld    hl,CPC_WIN_GEN
                ld    a,c
                add   a,l
                ld    l,a
                ld    d,(hl)                 ; high byte = nonzero reuse generation
                ret
cpc_owner_none ld    de,0
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
                ld    a,(hl)
                inc   a
                jr    nz,cpc_page_gen_ok
                inc   a
cpc_page_gen_ok
                ld    (hl),a
                ld    d,a
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
                jp    z,k_cpc_owner
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
                call  k_cpc_owner
                pop   hl
                or    a
                sbc   hl,de
                ld    a,2
                ret   nz
                call  k_wm_close
                xor   a
                ret
cpc_app_check  push  hl
                call  k_cpc_owner
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
                db    0,0,0,0                ; no deferred-message queue yet
                db    0
                dw    512
                db    1                      ; serialized filesystem API v1
                dw    CPC_CAPS_HIGH
                db    80,200,4,4             ; logical geometry and semantic pens
                dw    #4000,#7F00,#8000
                db    2,0,3,0                ; universal ABI 2.0, native-Z80 profile
                assert $-cpc_sysinfo_template==CPC_SYSINFO_SIZE,"CPC sysinfo v6 template size"
