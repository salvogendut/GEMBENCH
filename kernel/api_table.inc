; kernel/api_table.inc - fixed GEOBENCH API jump table.
;
; The order is the ABI. Keep this table synchronized with ../lib/gbapp.inc and
; validate with tools/check_abi_table.py.

                org   GB_KERNEL
; --- fixed API jump table (order is the ABI; see lib/gbapp.inc) -----------
                jp    kernel_main            ; GB_INIT  #8000
                jp    k_cls                  ; GB_CLS   #8003
                jp    k_noop                 ; GB_PRINT #8006 (dead stub -> shared ret, #148)
                jp    k_noop                 ; GB_QUIT  #8009 (dead stub -> shared ret, #148)
                jp    gb_text_draw           ; GB_TEXT   #800C
                jp    gb_open_window         ; GB_WINDOW #800F
                jp    gb_fs_dir_first        ; GB_DIR1   #8012
                jp    gb_fs_dir_next         ; GB_DIRN   #8015
                jp    k_vsync                ; GB_BLITE  #8018 (removed: mapping->FM, #103)
                jp    cursor_show            ; GB_CURSHOW #801B (was jp k_curshow; #148)
                jp    k_poll                 ; GB_POLL    #801E
                jp    k_frame                ; GB_FRAME   #8021
                jp    cursor_erase           ; GB_CURHIDE #8024
                jp    k_noop                 ; GB_LAUNCH  #8027 (dead stub -> shared ret, #148)
                jp    focus_arg_ptr          ; GB_GETARG  #802A (k_getarg collapsed, #148)
                jp    launch_app             ; GB_RUN     #802D (k_run collapsed, #148)
                jp    k_icon                 ; GB_ICON    #8030
                jp    k_fill                 ; GB_FILL    #8033
                jp    k_saverect             ; GB_SAVERECT    #8036
                jp    k_restorerect          ; GB_RESTORERECT #8039
                ifdef WM_GADGETS
                jp    k_pic_open             ; GB_PICOPEN     #803C (#164; was dead GB_XORFRAME)
                else
                jp    k_ret0                 ; no banked picture support -> A=0 (Viewer falls back)
                endif
                jp    k_fsload               ; GB_FSLOAD      #803F
                jp    k_fssave               ; GB_FSSAVE      #8042
                jp    k_getkey               ; GB_GETKEY      #8045
                jp    k_vsync                ; GB_VSYNC       #8048
                jp    k_onevent              ; GB_ONEVENT     #804B
                jp    k_menu                 ; GB_MENU        #804E
                jp    k_setname              ; GB_SETNAME     #8051
                ifdef WM_GADGETS
                jp    k_pic_blit             ; GB_PICBLIT     #8054 (#164; was dead GB_ONREPAINT)
                else
                jp    k_noop                 ; (never called when GB_PICOPEN returned A=0)
                endif
                jp    wm_repaint_all         ; GB_RESTPAR     #8057 (was jp k_restore_parent; #148)
                jp    k_wm_run               ; GB_WMRUN       #805A
                jp    wm_register            ; GB_WMADD       #805D (was jp k_wm_add; #148)
                jp    k_wm_open              ; GB_WMOPEN      #8060
                jp    k_wm_close             ; GB_WMCLOSE     #8063
                jp    k_wm_setpos            ; GB_WMSETPOS    #8066
                ifdef WM_GADGETS
                jp    k_pic_close            ; GB_PICCLOSE    #8069 (#164; was dead GB_WMLAUNCH)
                else
                jp    k_noop                 ; (never called when GB_PICOPEN returned A=0)
                endif
                jp    k_isdir                ; GB_ISDIR       #806C
                jp    k_chdir                ; GB_CHDIR       #806F
                jp    k_back                 ; GB_BACK        #8072
                jp    k_entname              ; GB_ENTNAME     #8075
                jp    k_drag_start           ; GB_DRAGSTART   #8078
                jp    k_fs_delete            ; GB_FSDELETE    #807B
                jp    k_drive_poll           ; GB_DRIVES      #807E
                jp    fs_set_drive           ; GB_SETDRIVE    #8081 (A = drive)
                jp    k_get_drive            ; GB_GETDRIVE    #8084
                jp    k_copy_begin           ; GB_COPYBEGIN   #8087 (-> drag source ctx)
                jp    k_wm_launch_as         ; GB_WMLAUNCHAS  #808A (HL = app name)
                jp    k_time                 ; GB_TIME        #808D (-> GB_TIME_BUF h,m,s)
                jp    k_exit                 ; GB_EXIT        #8090 (leave -> AMSDOS)
                jp    k_copy_end             ; GB_COPYEND     #8093 (restore target ctx)
                jp    k_on_bar               ; GB_ONBAR       #8096 (HL = bar handler, #77)
                jp    k_wm_setsize           ; GB_WMSETSIZE   #8099 (A = w, L = h, #81)
                jp    k_vsync                ; GB_BLITEFULL   #809C (removed: mapping->FM, #103)
                jp    k_icon_half            ; GB_ICONHALF    #809F (A=slot B=x C=y, #103)
                jp    k_mxp                  ; GB_MXP         #80A2 -> HL = pointer pixel x (#114)
                jp    k_clip_set             ; GB_CLIPSET     #80A5 (HL=src, DE=len) shared clipboard (#142)
                jp    k_clip_get             ; GB_CLIPGET     #80A8 (HL=dst, DE=max) -> BC=copied
                jp    k_clip_len             ; GB_CLIPLEN     #80AB -> BC = clipboard length
                jp    k_ui                   ; GB_UI          #80AE run the paged dialog module -> BC=UI_RES
                jp    k_wm_managed           ; GB_WMMANAGED   #80B1 register a kernel-managed window (#146)
                jp    k_wm_damage            ; GB_WMDAMAGE    #80B4 set the repaint clip = a damage rect (#153)
                jp    k_backdrop             ; GB_BACKDROP    #80B7 fill a rect with the desktop backdrop (#128)
                jp    k_reload               ; GB_RELOAD      #80BA re-apply font/icons/cursor/backdrop (#185)
                jp    k_net                  ; GB_NET         #80BD run the paged W5100 net module -> BC=GBNET_RES (#238)
