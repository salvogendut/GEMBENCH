; Shared MSX launch transaction; providers bind storage/admission and bank state.
; k_wm_open (GB_WMOPEN): HL = 8.3 app name in the caller page. Load it into a free
; bank page and CALL its entry once (its main registers a window via GB_WMADD and
; returns), then restore the caller's page. Non-blocking: the app becomes a live
; window the master loop services, rather than running its own loop.
k_wm_open
                ld    de,fs_req_name
                call  copy11
                ld    hl,launch_arg               ; opened with no file -> blank the arg
                ld    b,11                          ; so the app starts file-less
                xor   a
kwo_blank       ld    (hl),a
                inc   hl
                djnz  kwo_blank
                jr    wm_open_go

; k_wm_launch (GB_WMLAUNCH): superseded. File-type -> app routing moved into the
; File Manager (C); it now calls GB_WMLAUNCHAS with the app it chose. The slot
; stays fixed (addresses) and -> k_noop (#148).

; k_wm_launch_as (GB_WMLAUNCHAS): HL = the 8.3 app name to open as a co-resident
; window. The current dir entry (fs_ent_name) becomes the new window's file arg, so
; a data file auto-opens in the app the caller chose (the File Manager picks it by
; extension - see apps/filemgr/main.c).
k_wm_launch_as
                push  hl                           ; app name
                ld    hl,fs_ent_name              ; current entry -> the launch file arg
                ld    de,launch_arg
                call  copy11
                pop   hl                           ; app name -> fs_req_name
                ld    de,fs_req_name
                call  copy11
wm_open_go
                ld    a,(WM_NWIN)                 ; memory pages and window slots are independent
                cp    WM_MAXWIN
                ret   nc
                call  owner_alloc
                ret   nc
                ld    (CORE_PENDING_OWNER),de
                ld    b,GB_PAGE_APPLICATION
                call  page_alloc_owned
                jr    nc,wmo_owner_fail
                call  app_bind_code_page
                ld    (wm_open_page),a
                ld    a,(bank_cur)
                ld    (wm_open_back),a
                di
                ld    a,(wm_open_page)
                call  bank_set
                ld    hl,APP_LOAD_MAX
                ld    (fs_load_max),hl
                ld    hl,APP_BASE
                ld    (fs_load_dst),hl
                ld    a,(WM_OPEN_STRICT)
                or    a
                jr    z,wmo_load_sys
                xor   a
                ld    (WM_OPEN_STRICT),a
                call  fs_load_cur_sys             ; strict open: current drive, no boot fallback
                jr    wmo_loaded
wmo_load_sys    call  fs_load_sys                 ; normal app open: boot-first, browse-fallback
wmo_loaded      jr    nc,wmo_fail
                call  APP_ADMISSION_GATE            ; v4 validates before outer JP/publication
                jr    nc,wmo_fail               ; owner/page rollback is shared and complete
                ei
                call  APP_BASE                    ; main -> GB_WMADD + paint, then ret
                di
                ld    a,(wm_open_back)
                call  bank_set
                ld    de,(CORE_PENDING_OWNER)      ; a non-registering/bad app cannot leak its owner
                ld    a,d
                or    e
                call  nz,owner_release
                ei
                ret
wmo_fail
                ld    a,(wm_open_back)
                call  bank_set
                ld    de,(CORE_PENDING_OWNER)
                call  owner_release              ; also releases the primary code page
                ei
                ret
wmo_owner_fail  ld    de,(CORE_PENDING_OWNER)
                call  owner_release
                ret
