; gbkern - GEOBENCH banked-kernel skeleton (Phase 2).
;
; Resident at GB_KERNEL (#8000), it owns the machine and the stack and never
; lives in the #4000-#7FFF window, so it can page apps and its own data buffers
; in and out. It exposes a fixed API jump table (see lib/gbapp.inc), loads a
; real app binary off disk into PAGE_APP0, and runs it there.
;
; Services with banked buffers follow the page-swap discipline: a service saves
; the caller's page (bank_cur), swaps to PAGE_DATA, touches its buffer, and
; restores the caller's page. gb_text_draw is the first real one - it renders
; the 6x8 font, whose glyphs live in PAGE_DATA. Strings come from the caller's
; page, so they are copied to a resident scratch BEFORE swapping to the font.
;
; Build: tools/build_kernel.sh   Run: 1984 --memory=128 --disk-a=build/gbkern.dsk --autostart=GBKERN

                include "../lib/gbapp.inc"
                include "../lib/firmware.inc"

; Config transfer area - resident low RAM (stays main RAM under banking, so the
; paged-in GBCFG module can reach it). The kernel fills text/len, runs the
; module, then reads the parsed ICONS=/FONT= stems back. See kernel/kc/.
KCFG_TEXT       equ   #1000        ; GEOBENCH.CFG contents (<=512 bytes)
KCFG_LEN        equ   #1200        ; word: cfg-text byte count (0 = no file)
KCFG_ICONNAME   equ   #1202        ; 11-byte 8.3 icon filename, built by the module
KCFG_FONTNAME   equ   #120D        ; 11-byte 8.3 font filename, built by the module
KCFG_MEMKB      equ   #1218        ; word: total RAM in KB (kernel -> module)
KCFG_MEMSTR     equ   #121A        ; "<decimal>K" top-bar string (module -> kernel)
KCFG_CURSORNAME equ   #1221        ; 11-byte 8.3 cursor filename (CURSOR=), built by module
; CLOCK.APP support (#72): a tiny time read-out (kept minimal - the BCD->binary
; conversion lives in the C app; the clock draws its hands by calling the firmware
; graphics directly, so no resident line primitive is needed).
GB_TIME_BUF     equ   #1240        ; raw time: +0 hours(&3F), +1 min, +2 sec, +3 binmode
BOOT_SP         equ   #1244        ; word: SP at kernel_main entry (GB_EXIT, #74)
GB_KSIZE        equ   #1246        ; word: resident kernel size in bytes (System>Ram Usage)
                                    ; (binmode 0 = BCD regs, nonzero = already binary)
BAR_HANDLER     equ   #1248        ; word: top-bar handler, run every WM frame in PAGE_APP0
                                    ; regardless of focus (0 = none); bar-as-app expt (#77)

; Callback API (issue #32) - kernel->app event delivery, state in low RAM so it
; costs no resident image bytes (low RAM stays main RAM under banking).
APP_HANDLER     equ   #1300        ; word: registered app event handler (0 = none)
GB_MSG          equ   #1302        ; message record: type, p0, p1, p2 (4 bytes)
GB_MSG_MENU     equ   1            ; message type: top-bar click, p0 = byte column
GB_MSG_DROP     equ   2            ; message type: a file was dropped on this window
                                   ; (DnD, #62); name at WM_DRAGNAME, pos at POLL_MX/MY
POLL_MX         equ   #1306        ; last poll: cursor byte column (mx)
POLL_MY         equ   #1307        ; last poll: cursor line (my)
POLL_FLAGS      equ   #1308        ; last poll: flags (bit0 click, bit1 quit, bit2 fire)
MENU_DEF        equ   #1310        ; app menu: count, then {col, 8-byte label} *count
REPAINT_HDLR    equ   #1340        ; per-depth full-repaint handlers (4 words), for
                                   ; restoring the background under a moved window (#43)

; Window manager (issue #45) - the kernel owns the master loop and a table of
; co-resident windows; each app registers one and becomes callback-driven. State
; in low RAM (0 resident image bytes). Phase 2: multiple windows + click-to-focus.
WM_NWIN         equ   #1350        ; number of live windows
WM_FOCUS        equ   #1351        ; slot index of the focused window
WM_TABLE        equ   #1352        ; WM_MAXWIN * WM_ESZ-byte entries:
WM_ESZ          equ   25           ;   page,x,y,w,h, on_frame(2),on_repaint(2),
WM_MAXWIN       equ   8            ;   on_event(2), menu(2), flags(1), arg(11)
                                   ; #84: 8 = desktop + 7 windows (table #1352..#1419)
WM_Z            equ   #141A        ; z-order: WM_NWIN slot indices, [0]=bottom
WM_FPREV        equ   #1422        ; previously focused slot (menu-swap edge detect)
WM_DRAGNAME     equ   #1423        ; drag-and-drop (#62): dragged 11-byte 8.3 name,
                                   ; app-visible (the drop target reads it on GB_MSG_DROP)
WM_DRAGSRC      equ   #142E        ; source window slot of the active drag
WM_DRAGMOV      equ   #142F        ; 1 once the pointer moved (a drag, not a click)
WM_DRAGX0       equ   #1430        ; last drag position (byte col / line); movement
WM_DRAGY0       equ   #1431        ; vs this drives both the ghost and click/drag tell
WM_DRAGDRV      equ   #1432        ; source drive of the active drag (for cross-drive copy)
WM_DRAGDIR      equ   #1433        ; source directory cluster (4 bytes), captured at start
; --- app bank-page pool (#84): built at boot from the detected RAM. The old fixed
; 3-bit page bitmap (first expansion bank only) is gone; the pool now spans every
; detected bank, capped at WM_MAXWIN. The desktop (first claim) always gets [0]. ---
APP_NPAGES      equ   #1437        ; usable app-page count (3 on 128K, up to WM_MAXWIN)
APP_PAGES       equ   #1438        ; WM_MAXWIN port values; [0] = PAGE_APP0 (#C5, desktop)
APP_BUSY        equ   #1440        ; WM_MAXWIN busy flags (0 free / 1 busy), parallel
GHOST_W         equ   8            ; drag ghost outline box: 8 byte-cols x 16 lines
GHOST_H         equ   16           ; (an icon footprint); save-under in fs_secbuf
CUR_LOW         equ   #1500        ; low-RAM cursor sprite buffer (#65): DEFAULT.SPR is
                                   ; loaded here at boot so the bitmaps aren't resident
                                   ; (256B used; 512 reserved to #16FF for the sector copy)
WM_FR_X         equ   1            ; entry field offsets (after +0 page):
WM_FR_FRAME     equ   5
WM_FR_REPAINT   equ   7
WM_FR_EVENT     equ   9
WM_FR_MENU      equ   11
WM_FR_FLAGS     equ   13
WM_FR_ARG       equ   14           ;   11-byte 8.3 file arg, captured at gb_wm_add

                org   GB_KERNEL
; --- fixed API jump table (order is the ABI; see lib/gbapp.inc) -----------
                jp    kernel_main            ; GB_INIT  #8000
                jp    k_cls                  ; GB_CLS   #8003
                jp    k_print                ; GB_PRINT #8006
                jp    k_quit                 ; GB_QUIT  #8009
                jp    gb_text_draw           ; GB_TEXT   #800C
                jp    gb_open_window         ; GB_WINDOW #800F
                jp    gb_fs_dir_first        ; GB_DIR1   #8012
                jp    gb_fs_dir_next         ; GB_DIRN   #8015
                jp    gb_blit_entry          ; GB_BLITE  #8018
                jp    k_curshow              ; GB_CURSHOW #801B
                jp    k_poll                 ; GB_POLL    #801E
                jp    k_frame                ; GB_FRAME   #8021
                jp    cursor_erase           ; GB_CURHIDE #8024
                jp    k_launch               ; GB_LAUNCH  #8027
                jp    k_getarg               ; GB_GETARG  #802A
                jp    k_run                  ; GB_RUN     #802D
                jp    k_icon                 ; GB_ICON    #8030
                jp    k_fill                 ; GB_FILL    #8033
                jp    k_saverect             ; GB_SAVERECT    #8036
                jp    k_restorerect          ; GB_RESTORERECT #8039
                jp    k_xorframe             ; GB_XORFRAME    #803C
                jp    k_fsload               ; GB_FSLOAD      #803F
                jp    k_fssave               ; GB_FSSAVE      #8042
                jp    k_getkey               ; GB_GETKEY      #8045
                jp    k_vsync                ; GB_VSYNC       #8048
                jp    k_onevent              ; GB_ONEVENT     #804B
                jp    k_menu                 ; GB_MENU        #804E
                jp    k_setname              ; GB_SETNAME     #8051
                jp    k_onrepaint            ; GB_ONREPAINT   #8054
                jp    k_restore_parent       ; GB_RESTPAR     #8057
                jp    k_wm_run               ; GB_WMRUN       #805A
                jp    k_wm_add               ; GB_WMADD       #805D
                jp    k_wm_open              ; GB_WMOPEN      #8060
                jp    k_wm_close             ; GB_WMCLOSE     #8063
                jp    k_wm_setpos            ; GB_WMSETPOS    #8066
                jp    k_wm_launch            ; GB_WMLAUNCH    #8069
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
                jp    gb_blit_entry_full     ; GB_BLITEFULL   #809C (B=x C=y, full icon #88)

; ---------------------------------------------------------------------------
kernel_main
                ld    (BOOT_SP),sp           ; entry SP, for GB_EXIT's clean return (#74)
                ld    a,1
                call  SCR_SET_MODE           ; mode 1, screen cleared
                call  TXT_CUR_DISABLE        ; no blinking firmware cursor blob
                call  TXT_CUR_OFF
                call  KM_DISARM_BREAK        ; ESC is ours, not a reset-to-BASIC key:
                ld    a,#C9                   ; disarm the break event AND patch the
                ld    (#BDEE),a               ; KM TEST BREAK indirection to RET (that's
                                              ; what actually resets on ESC; disarm alone
                                              ; doesn't touch it)
                call  disarm_joy_keys        ; joystick keys must not feed the char
                                              ; buffer, or moving the pointer floods
                                              ; gb_getkey (the keyboard is the joystick)
                call  set_palette            ; GEOBENCH 4-pen palette
                call  fs_init                ; pick storage backend (floppy here)
                call  input_init             ; enable the SymbiFace mouse if present
                di                            ; probe RAM BEFORE PAGE_DATA is filled
                call  mem_detect             ; (it pokes every bank's #4000)
                ei
                ld    (md_banks),a           ; keep the raw bank count for app_pool_init (#84)
                ld    l,a                     ; total KB = 64 + banks*64
                ld    h,0
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                add   hl,hl
                ld    de,64
                add   hl,de
                ld    (KCFG_MEMKB),hl        ; -> KCFG_MEMSTR (formatted by GBCFG)
                call  cfg_boot               ; parse GEOBENCH.CFG (C module) ->
                                             ; KCFG_ICONS / KCFG_FONT (before the
                                             ; font/icon loaders consume them)
                call  font_init              ; load the font into PAGE_DATA
                call  icon_init              ; load the icon set into PAGE_DATA
                call  cursor_init            ; load the cursor sprite into low RAM (#65)
                call  clock_init             ; detect RTC + seed the software clock (#77:
                                              ; the desktop draws the bar, not the kernel)
                ld    hl,WM_NWIN            ; clear WM low-RAM state (counts, focus, table
                ld    de,WM_NWIN+1          ; incl. alive flags, z-order)
                ld    bc,WM_Z+WM_MAXWIN-WM_NWIN-1
                ld    (hl),0
                ldir
                call  app_pool_init          ; build the app-page pool from md_banks (#84)
                ld    a,#FF                   ; no previous focus yet -> first map_focus
                ld    (WM_FPREV),a           ; installs the desktop's menu
                ld    hl,kern_end-GB_KERNEL  ; resident kernel size -> GB_KSIZE (Ram Usage)
                ld    (GB_KSIZE),hl
                ld    hl,name_desktop        ; the desktop is the first app
                call  launch_app             ; run DESKTOP in PAGE_APP0 (the WM master loop
                                              ; runs forever; only GB_EXIT gets past here)
km_finish                                      ; reached by k_exit's longjmp
                ei
                ld    a,2                     ; back to BASIC's 80-col mode
                call  SCR_SET_MODE
                ret                           ; -> AMSDOS / BASIC

; k_exit (GB_EXIT #8090): leave GEOBENCH and return to AMSDOS. The WM master loop
; never returns, so longjmp out of the whole nested call chain by restoring SP to
; the boot value, then fall into km_finish's clean exit (#74).
k_exit
                di
                call  bank_normal             ; main RAM at #4000-#7FFF (for BASIC)
                ld    sp,(BOOT_SP)
                jp    km_finish
name_desktop    db    "DESKTOP APP"

; disarm_joy_keys: the CPC joystick is keyboard matrix row 9 (key numbers 72..77 =
; up/down/left/right/fire1/fire2). By default those keys translate to characters,
; so moving the pointer (= the joystick) floods the firmware key buffer and any
; app that calls gb_getkey (Notepad) redraws on every move. Set their normal /
; shift / control translation to &FF (no character). KM_GET_JOYSTICK / KM_TEST_KEY
; read the matrix directly and are unaffected, so the pointer still works.
disarm_joy_keys
                ld    c,72
djk_loop
                ld    a,c
                ld    b,#FF
                push  bc
                call  KM_SET_TRANSLATE
                pop   bc
                ld    a,c
                ld    b,#FF
                push  bc
                call  KM_SET_SHIFT
                pop   bc
                ld    a,c
                ld    b,#FF
                push  bc
                call  KM_SET_CONTROL
                pop   bc
                inc   c
                ld    a,c
                cp    78
                jr    c,djk_loop
                ret

; --- palette -------------------------------------------------------------
INK_DESKTOP     equ   1            ; blue  -> pen 0 (paper / backdrop)
INK_LIGHT       equ   26           ; white -> pen 1 (text)
INK_DARK        equ   0            ; black -> pen 2 (outlines / title bar)
INK_ACCENT      equ   6            ; red   -> pen 3 (accents)
set_palette
                ld    a,0
                ld    b,INK_DESKTOP
                ld    c,INK_DESKTOP
                call  SCR_SET_INK
                ld    a,1
                ld    b,INK_LIGHT
                ld    c,INK_LIGHT
                call  SCR_SET_INK
                ld    a,2
                ld    b,INK_DARK
                ld    c,INK_DARK
                call  SCR_SET_INK
                ld    a,3
                ld    b,INK_ACCENT
                ld    c,INK_ACCENT
                call  SCR_SET_INK
                ld    b,INK_DESKTOP
                ld    c,INK_DESKTOP
                jp    SCR_SET_BORDER

; --- input + cursor services ---------------------------------------------
; k_curshow: draw the pointer (the app calls this once after drawing its UI).
k_curshow
                jp    cursor_show

; k_poll: frame-paced input poll. Moves the cursor by the held directions and
; redraws it; returns B = cursor byte col, C = cursor line, D flags: bit0 = a
; fresh click (fire just pressed), bit1 = quit (ESC). Interrupts must be on so
; the firmware scans the keyboard.
k_poll
                call  input_poll             ; in_dx/in_dy + in_fire/in_quit
                call  poll_move              ; -> DE = new x, HL = new y (clamped)
                call  MC_WAIT_FLYBACK        ; pace to 50 Hz; do the move in the blank
                call  cursor_move_to         ; erases+redraws ONLY if the position
                                             ; actually changed (re-drawing in place,
                                             ; e.g. holding a key into the edge clamp,
                                             ; corrupts the save-under). In the flyback
                                             ; blank so the move isn't seen mid-frame.
                                             ; MUST precede clock_tick: it consumes the
                                             ; DE/HL target that clock_tick would clobber.
                call  clock_tick             ; keep the top-bar clock live
                ld    hl,(cursor_x)          ; cursor byte col = cursor_x / 8
                srl   h
                rr    l
                srl   h
                rr    l
                srl   h
                rr    l
                ld    a,l
                ld    (poll_byte),a
                ld    hl,(cursor_y)          ; cursor line = 199 - cursor_y / 2
                srl   h
                rr    l
                ld    a,199
                sub   l
                ld    (poll_line),a
                ld    d,0
                ld    a,(in_fire)            ; click edge = fire & !last_fire
                ld    e,a
                ld    a,(poll_lastfire)
                cpl
                and   e
                jr    z,gp_noclick
                set   0,d
gp_noclick
                ld    a,e
                ld    (poll_lastfire),a
                ld    a,(in_quit)
                or    a
                jr    z,gp_noquit
                set   1,d
gp_noquit
                ld    a,(in_fire)            ; bit2 = fire currently held (for drag)
                or    a
                jr    z,gp_nohold
                set   2,d
gp_nohold
                call  menu_dispatch          ; kernel-owned top-bar click -> app
                ld    a,d                     ; publish the result to fixed low RAM so a
                ld    (POLL_FLAGS),a          ; WM callback can read it without re-polling
                ld    a,(poll_byte)           ; (gb_mx/gb_my/gb_flags read these)
                ld    (POLL_MX),a
                ld    b,a
                ld    a,(poll_line)
                ld    (POLL_MY),a
                ld    c,a
                ret
poll_lastfire   db    0
poll_byte       db    0
poll_line       db    0

; poll_move: apply the per-frame pointer delta (in_dx/in_dy, from input_poll -
; joystick step and/or SymbiFace mouse) to the cursor, clamped to the screen.
; Returns DE = new x, HL = new y. Does NOT write cursor_x/y - cursor_move_to does
; that, redrawing only when the position actually changes.
poll_move
                ld    hl,(cursor_x)
                ld    de,(in_dx)             ; signed delta this frame
                add   hl,de
                call  clamp638
                ld    (pm_newx),hl
                ld    hl,(cursor_y)
                ld    de,(in_dy)
                add   hl,de
                call  clamp398
                ld    de,(pm_newx)
                ret
pm_newx         dw    0
clamp638
                ld    de,638
                jr    clamp_hl
clamp398
                ld    de,398
clamp_hl                                       ; clamp HL to [0, DE]
                bit   7,h                     ; negative -> 0
                jr    z,ch_hi
                ld    hl,0
                ret
ch_hi
                push  hl
                or    a
                sbc   hl,de
                pop   hl
                ret   c                        ; HL < DE -> keep
                ex    de,hl                    ; clamp to DE
                ret

; fill_xywh: B=x C=y D=w E=h -> set fb_* then fill_block (fb_val preset). Shared
; rectangle/edge filler so k_frame and kwin_frame don't each repeat the fb_* stores.
fill_xywh
                ld    a,b
                ld    (fb_x),a
                ld    a,c
                ld    (fb_y),a
                ld    a,d
                ld    (fb_w),a
                ld    a,e
                ld    (fb_h),a
                jp    fill_block

; copy11: HL=src DE=dst -> copy 11 bytes (an 8.3 name). Shared by the many name-copy
; sites (fs_req_name / launch_arg / window arg) to drop the per-site ld bc,11 + ldir.
copy11
                ld    bc,11
                ldir
                ret

; k_frame (GB_FRAME): draw a 1px rectangle outline. B=x C=y D=w E=h (screen
; byte/line), A=pen (0..3). Screen only (no banked buffer), so no page swap.
k_frame
                ld    (gf_pen),a             ; save params FIRST: pen_to_byte below
                ld    a,b                     ; clobbers E (height), so capture it now
                ld    (gf_x),a
                ld    a,c
                ld    (gf_y),a
                ld    a,d
                ld    (gf_w),a
                ld    a,e
                ld    (gf_h),a
                ld    a,(gf_pen)
                call  pen_to_byte            ; pen -> Mode 1 fill byte
                ld    (fb_val),a
                ld    a,(gf_x)               ; top edge: (x, y, w, 1)
                ld    b,a
                ld    a,(gf_y)
                ld    c,a
                ld    a,(gf_w)
                ld    d,a
                ld    e,1
                call  fill_xywh
                ld    a,(gf_x)               ; bottom edge: (x, y+h-1, w, 1)
                ld    b,a
                ld    a,(gf_y)
                ld    c,a
                ld    a,(gf_h)
                add   a,c
                dec   a
                ld    c,a
                ld    a,(gf_w)
                ld    d,a
                ld    e,1
                call  fill_xywh
                ld    a,(gf_x)               ; left edge: (x, y, 1, h)
                ld    b,a
                ld    a,(gf_y)
                ld    c,a
                ld    d,1
                ld    a,(gf_h)
                ld    e,a
                call  fill_xywh
                ld    a,(gf_x)               ; right edge: (x+w-1, y, 1, h)
                ld    b,a
                ld    a,(gf_w)
                add   a,b
                dec   a
                ld    b,a
                ld    a,(gf_y)
                ld    c,a
                ld    d,1
                ld    a,(gf_h)
                ld    e,a
                jp    fill_xywh
gf_x            db    0
gf_y            db    0
gf_w            db    0
gf_h            db    0
gf_pen          db    0

; --- firmware text (kernel boot messages) --------------------------------
k_cls
                ld    a,1
                jp    SCR_SET_MODE            ; mode 1 clears; returns to caller
k_print                                        ; GB_PRINT: stub (unused early debug
                ret                            ; print; no binding). Slot kept fixed.
k_quit
                ret                            ; (skeleton: app RETs anyway)

; to_data / from_data: save the caller's bank page and map PAGE_DATA (the font /
; icon page), then restore it. One shared save slot (dp_save) - these swaps are
; never nested (each service swaps, calls only non-swapping helpers, restores).
; Replaces the open-coded save/swap/restore at every PAGE_DATA service.
to_data
                ld    a,(bank_cur)
                ld    (dp_save),a
                ld    a,PAGE_DATA
                jp    bank_set
from_data
                ld    a,(dp_save)
                jp    bank_set
dp_save         db    0

; --- gb_text_draw: 6x8 font text service ---------------------------------
; B = byte col, C = line, D = pen, E = paper, HL = string (caller's page).
; Copy the string to resident scratch (caller page still mapped), set up the
; renderer, then swap to PAGE_DATA for the glyphs, draw, and restore.
gb_text_draw
                ld    a,b                     ; position
                ld    (tc_x),a
                ld    a,c
                ld    (tc_y),a
                ld    b,d                     ; pens: B = pen, C = paper
                ld    c,e
                push  hl
                call  set_text_pens
                pop   hl
                ld    de,gtd_scratch          ; copy string out of the caller's page
                call  gtd_copy
                call  to_data                 ; swap to the font page
                ld    hl,gtd_scratch
                call  draw_text
                jp    from_data               ; restore caller's page
gtd_copy                                       ; (HL) -> (DE) until NUL, cap 48
                ld    b,48
gtd_cloop
                ld    a,(hl)
                ld    (de),a
                or    a
                ret   z
                inc   hl
                inc   de
                djnz  gtd_cloop
                xor   a                        ; truncate + terminate
                ld    (de),a
                ret
gtd_scratch     defs  49

; --- gb_open_window: draw a window frame + title -------------------------
; B = x (byte col), C = y (line), D = w (bytes), E = h (lines), HL = title.
; The frame is plain fills (screen only); the title needs the font, so swap to
; PAGE_DATA for it. No save-under: closing a window redraws the desktop.
gb_open_window
                ld    a,b
                ld    (kw_x),a
                ld    a,c
                ld    (kw_y),a
                ld    a,d
                ld    (kw_w),a
                ld    a,e
                ld    (kw_h),a
                ld    de,kw_title            ; copy title out of the caller's page
                call  gtd_copy
                call  kwin_frame             ; frame: fills to screen, no font
                call  to_data                 ; title needs the font page
                ld    b,1                     ; white on black title bar
                ld    c,2
                call  set_text_pens
                ld    a,(kw_x)
                add   a,4
                ld    (tc_x),a
                ld    a,(kw_y)
                add   a,3
                ld    (tc_y),a
                ld    hl,kw_title
                call  draw_text
                jp    from_data

; kwin_frame: blue interior, black title bar + borders, white close gadget.
kwin_frame
                xor   a                       ; interior (blue): (x, y, w, h)
                ld    (fb_val),a
                ld    a,(kw_x)
                ld    b,a
                ld    a,(kw_y)
                ld    c,a
                ld    a,(kw_w)
                ld    d,a
                ld    a,(kw_h)
                ld    e,a
                call  fill_xywh
                ld    a,#F0                   ; title bar: white base (x, y, w, 14)
                ld    (fb_val),a
                ld    a,(kw_x)
                ld    b,a
                ld    a,(kw_y)
                ld    c,a
                ld    a,(kw_w)
                ld    d,a
                ld    e,14
                call  fill_xywh
                ld    a,#0F                   ; ... black horizontal stripes (1-line
                ld    (fb_val),a             ; fills, every other line; fb_x/fb_w
                ld    a,1                     ; stay kw_x/kw_w from the fill above)
                ld    (fb_h),a
                ld    a,(kw_y)
                ld    (kf_sy),a
                ld    b,7
kf_stripe       ld    a,(kf_sy)
                ld    (fb_y),a
                push  bc
                call  fill_block
                pop   bc
                ld    a,(kf_sy)
                add   a,2
                ld    (kf_sy),a
                djnz  kf_stripe
                ld    a,(kw_x)               ; black borders via k_frame (all 4 edges; the
                ld    b,a                     ; top edge coincides with the first title
                ld    a,(kw_y)               ; stripe, so it is behavior-neutral) - was
                ld    c,a                     ; three separate left/right/bottom fills
                ld    a,(kw_w)
                ld    d,a
                ld    a,(kw_h)
                ld    e,a
                ld    a,2                     ; pen 2 = black (#0F)
                call  k_frame
                ld    a,#F0                   ; close gadget (white): (x+1, y+2, 2, 10)
                ld    (fb_val),a
                ld    a,(kw_x)
                inc   a
                ld    b,a
                ld    a,(kw_y)
                add   a,2
                ld    c,a
                ld    d,2
                ld    e,10
                jp    fill_xywh
kw_x            db    0
kw_y            db    0
kw_w            db    0
kw_h            db    0
kf_sy           db    0            ; kwin_frame: current title-bar stripe line
kw_title        defs  24

; --- directory enumeration services --------------------------------------
; Return CF set with HL -> a resident "NAME.EXT" string (0-term) for the entry,
; or NC at end of directory. fs_ent_* are resident, so no page swap is needed;
; the floppy backend is di-safe and uses its own resident buffers.
gb_fs_dir_first
                call  fs_dir_first
                jr    gdir_done
gb_fs_dir_next
                call  fs_dir_next
gdir_done
                ret   nc                       ; no/Last entry
                call  fmt_entry              ; fs_ent_name -> dir_namebuf
                ld    hl,dir_namebuf
                scf
                ret

; fmt_entry: fs_ent_name (8.3, space padded) -> dir_namebuf as the bare "NAME", 0.
; (Name only - the type is conveyed by the entry's icon; the old extension-display
; branch was dead, showext was never set.)
fmt_entry
                ld    de,dir_namebuf
                ld    hl,fs_ent_name
                ld    b,8
fe_name
                ld    a,(hl)
                cp    ' '
                jr    z,fe_end
                ld    (de),a
                inc   de
                inc   hl
                djnz  fe_name
fe_end
                xor   a
                ld    (de),a
                ret
dir_namebuf     defs  14

; --- gb_blit_entry: half-height type icon for the current entry ----------
; B = byte col, C = line. Picks the icon by fs_ent_name's extension, reads the
; bitmap + size from the .IST in PAGE_DATA, and blits its middle band.
gb_blit_entry
                ld    a,b
                ld    (be_x),a
                ld    a,c
                ld    (be_y),a
                call  ext_to_icon            ; A = slot (reads resident fs_ent_name)
                ld    (be_slot),a
                call  to_data
                ld    a,(be_slot)
                call  icon_geom              ; sets bm_src/bm_w/bm_h/bm_x/bm_y
                call  blit_bitmap
                jp    from_data
be_x            db    0
be_y            db    0
be_slot         db    0
ig_w            db    0
ig_h            db    0

; gb_blit_entry_full (GB_BLITEFULL): like gb_blit_entry, but the FULL icon (all
; rows) instead of the half-height middle band - the File Manager's icon-grid view
; uses it so tall art (e.g. the geobench lollipop) isn't cut. B = x, C = y. picks
; the slot by the current entry, then hands to k_icon's full blit. ext_to_icon
; clobbers B (cmp_name), so save x,y across it.
gb_blit_entry_full
                push  bc
                call  ext_to_icon            ; A = slot for the current entry
                pop   bc
                jp    k_icon                  ; full blit: A = slot, B = x, C = y

; icon_geom: A = slot -> from the .IST directory (DATA_ICONS) set up a
; half-height blit (middle band) at (be_x, be_y). PAGE_DATA must be mapped.
icon_geom
                ld    l,a                     ; dir entry = DATA_ICONS+16 + slot*4
                ld    h,0
                add   hl,hl
                add   hl,hl
                ld    de,DATA_ICONS+16
                add   hl,de
                ld    e,(hl)                  ; offset (word)
                inc   hl
                ld    d,(hl)
                inc   hl
                ld    a,(hl)                  ; width (bytes)
                ld    (ig_w),a
                inc   hl
                ld    a,(hl)                  ; height (rows)
                ld    (ig_h),a
                ld    hl,DATA_ICONS          ; bitmap base = DATA_ICONS + offset
                add   hl,de
                ld    a,(ig_h)               ; + (h/4)*w  (skip the top quarter)
                srl   a
                srl   a
                ld    b,a
                ld    a,(ig_w)
                ld    e,a
                ld    d,0
ig_skip
                ld    a,b
                or    a
                jr    z,ig_done
                add   hl,de
                dec   b
                jr    ig_skip
ig_done
                ld    (bm_src),hl
                ld    a,(ig_w)
                ld    (bm_w),a
                ld    a,(ig_h)               ; half height
                srl   a
                ld    (bm_h),a
                ld    a,(be_x)
                ld    (bm_x),a
                ld    a,(be_y)
                ld    (bm_y),a
                ret

; ext_to_icon: A = icon slot for the current entry (fs_ent_name + fs_ent_attr).
; Table-driven (#95, was a long chain of inline cmp_ext / cmp_name8 checks): a
; folder check, the kernel-name special case, then an ext table ({3 chars, slot};
; APP's slot #FF means "look the name up in the app-name table"), else binary.
ext_to_icon
                ld    a,(fs_ent_attr)         ; directory -> folder (slot 9)
                and   #10
                jr    nz,eti_folder
                ld    hl,name_kernel          ; the kernel binary -> geobench icon (slot 4)
                call  cmp_name
                jr    z,eti_geo
                ld    hl,ext_table            ; scan {3-char ext, slot byte}
eti_el          ld    a,(hl)
                or    a
                jr    z,eti_bin               ; 0 terminator -> binary default
                call  cmp_ext                 ; 3 chars at HL vs ext; HL preserved
                jr    z,eti_eh
                inc   hl                        ; next entry (3 ext + 1 slot)
                inc   hl
                inc   hl
                inc   hl
                jr    eti_el
eti_eh          inc   hl                        ; HL -> the slot byte
                inc   hl
                inc   hl
                ld    a,(hl)
                inc   a                          ; #FF (the .APP sentinel) -> 0
                jr    z,eti_appname
                dec   a                          ; restore the real slot
                ret
eti_bin         ld    a,6
                ret
eti_folder      ld    a,9
                ret
eti_geo         ld    a,4
                ret
; .APP name sub-dispatch: scan {8-char name, slot}, else the generic app icon (10).
eti_appname     ld    hl,appname_table
eti_al          ld    a,(hl)
                or    a
                jr    z,eti_appdef
                call  cmp_name                ; 8 chars at HL vs name; HL preserved
                jr    z,eti_ah
                ld    bc,9                      ; next entry (8 name + 1 slot)
                add   hl,bc
                jr    eti_al
eti_ah          ld    de,8                      ; HL -> the slot byte
                add   hl,de
                ld    a,(hl)
                ret
eti_appdef      ld    a,10
                ret

; cmp_ext: Z if the 3 chars at HL == fs_ent_name+8. HL preserved. Clobbers A, DE.
cmp_ext
                push  hl
                ld    de,fs_ent_name+8
                ld    a,(de)
                cp    (hl)
                jr    nz,cmpe_x
                inc   hl
                inc   de
                ld    a,(de)
                cp    (hl)
                jr    nz,cmpe_x
                inc   hl
                inc   de
                ld    a,(de)
                cp    (hl)
cmpe_x          pop   hl
                ret
; cmp_name: Z if the 8 chars at HL == fs_ent_name[0..7]. HL preserved. Clobbers A,B,DE.
cmp_name
                push  hl
                ld    de,fs_ent_name
                ld    b,8
cmpn_l          ld    a,(de)
                cp    (hl)
                jr    nz,cmpn_x
                inc   hl
                inc   de
                djnz  cmpn_l
cmpn_x          pop   hl
                ret

; ext table: {3-char ext, slot}. APP -> #FF = sentinel for the app-name table.
ext_table       db    "BAS",5
                db    "SCR",7
                db    "PIC",7
                db    "TXT",8
                db    "CFG",8
                db    "FNT",13
                db    "IST",14
                db    "APP",#FF
                db    0
; app-name sub-table: {8-char name, slot}. (GBKERN handled separately above.)
appname_table   db    "NOTEPAD ",11
                db    "ICONED  ",12
                db    "CLOCK   ",2
                db    "DESKTOP ",15
                db    "FILEMGR ",16
                db    0
name_kernel     db    "GBKERN  "

; --- config (C kernel module) --------------------------------------------
; cfg_boot: seed defaults, load GEOBENCH.CFG into the transfer area, then run the
; GBCFG C module (paged into a bank) to parse it into KCFG_ICONS / KCFG_FONT.
; Absent file -> length 0 -> the parser is a no-op and the defaults stand.
cfg_boot
                ld    hl,0                    ; default: no config text (module then
                ld    (KCFG_LEN),hl           ; emits the DEFAULT names itself)
                ld    hl,cfg_fname           ; fs_req_name = "GEOBENCH.CFG"
                ld    de,fs_req_name
                call  copy11
                ld    hl,#0200               ; cfg text buffer is 512 bytes
                ld    (fs_load_max),hl
                ld    hl,KCFG_TEXT
                ld    (fs_load_dst),hl
                call  fs_load_file
                jr    nc,cfgb_run            ; no file -> KCFG_LEN stays 0
                ld    hl,(fs_ent_size)        ; file <512 so the low word is the size
                ld    (KCFG_LEN),hl
cfgb_run
                jp    run_cfgmod
cfg_fname       db    "GEOBENCHCFG"          ; "GEOBENCH.CFG" (8.3)

; run_cfgmod: load GBCFG.BIN into PAGE_APP0 and CALL it (it parses the transfer
; area). Mirrors launch_app's load path; runs under DI (the module needs no
; interrupts) with no top-bar/ESC handling - this is boot time.
run_cfgmod
                ld    hl,cfgmod_name
                ld    de,fs_req_name
                call  copy11
                ld    a,(bank_cur)           ; save the current page
                push  af
                di
                ld    a,PAGE_APP0
                call  bank_set
                ld    hl,#3F00
                ld    (fs_load_max),hl
                ld    hl,APP_BASE
                ld    (fs_load_dst),hl
                call  fs_load_file
                jr    nc,rcm_done            ; module missing -> keep defaults
                call  APP_BASE               ; crt0 _start -> main -> gb_cfg_parse
rcm_done
                pop   af                       ; restore the caller's page
                call  bank_set
                ei
                ret
cfgmod_name     db    "GBCFG   BIN"          ; 8.3, space-padded

; --- font in PAGE_DATA ----------------------------------------------------
; font_init: page PAGE_DATA in, load <FONT>.FNT into it, cache the geometry.
; The 8.3 filename was built by the GBCFG module (KCFG_FONTNAME); just copy it.
font_init
                di
                ld    a,PAGE_DATA
                call  bank_set
                ld    hl,KCFG_FONTNAME       ; fs_req_name = the config font name
                ld    de,fs_req_name
                call  copy11
                ld    hl,#1000               ; font fits easily
                ld    (fs_load_max),hl
                ld    hl,DATA_FONT           ; load into PAGE_DATA
                ld    (fs_load_dst),hl
                ld    hl,def_fnt             ; fall back to DEFAULT.FNT if missing
                call  load_or_default
                ld    hl,DATA_FONT           ; cache geometry (font_glyphs -> PAGE_DATA)
                call  font_apply_header
                call  bank_normal
                ei
                ret
def_fnt         db    "DEFAULT FNT"
def_ist         db    "DEFAULT IST"

; load_or_default: fs_req_name holds the wanted 8.3 name and fs_load_dst/max are
; set. Try it; if the file is missing (a bad ICONS=/FONT= value), retry with the
; 11-byte default name at HL so a typo can't leave the screen drawing garbage.
load_or_default                                ; HL = default 8.3 name (11 bytes)
                push  hl
                call  fs_load_file
                pop   hl
                ret   c                         ; wanted file loaded
                ld    de,fs_req_name           ; missing -> use the default name
                call  copy11
                jp    fs_load_file              ; (dst/max unchanged by the miss)

; icon_init: load <ICONS>.IST into PAGE_DATA at DATA_ICONS.
icon_init
                di
                ld    a,PAGE_DATA
                call  bank_set
                ld    hl,KCFG_ICONNAME       ; fs_req_name = the config icon name
                ld    de,fs_req_name
                call  copy11
                ld    hl,GBFAT_LOAD-DATA_ICONS-#200  ; cap = the free icon region: from
                ld    (fs_load_max),hl               ; DATA_ICONS up to GBFAT_LOAD (the FAT
                                                     ; write module also lives in PAGE_DATA),
                                                     ; less a sector. ~#1A00 (~25 icons),
                                                     ; derived so it never needs hand-tuning.
                ld    hl,DATA_ICONS
                ld    (fs_load_dst),hl
                ld    hl,def_ist             ; fall back to DEFAULT.IST if missing
                call  load_or_default
                call  bank_normal
                ei
                ret

; cursor_init (#65): load the cursor sprite (<CURSOR>.SPR from GEOBENCH.CFG, built
; by the GBCFG module into KCFG_CURSORNAME) into low RAM at CUR_LOW, so the 256-byte
; bitmaps need not be resident. Loads into low RAM (always mapped) so no PAGE_DATA
; swap. fs_load_max = 512 (the IDE reader copies a whole sector); CUR_LOW..+#1FF is
; reserved for that. Falls back to DEFAULT.SPR if the configured name is missing; if
; even that is absent, the buffer is blanked (empty cursor, never garbage).
cursor_init
                ld    hl,KCFG_CURSORNAME     ; fs_req_name = the config cursor name
                ld    de,fs_req_name
                call  copy11
                ld    hl,512
                ld    (fs_load_max),hl
                ld    hl,CUR_LOW
                ld    (fs_load_dst),hl
                ld    hl,def_spr            ; fall back to DEFAULT.SPR if missing
                di
                call  load_or_default
                ei
                ret   c
                ld    hl,CUR_LOW             ; missing -> blank the sprite buffer
                ld    de,CUR_LOW+1
                ld    bc,255
                ld    (hl),0
                ldir
                ret
def_spr         db    "DEFAULT SPR"

; --- app launch ----------------------------------------------------------
; launch_app: HL = 8.3 app name. Load it into the next bank page (PAGE_APP0 +
; launch depth) and run it; restore the caller's page when it quits. Apps nest
; (desktop -> filemgr -> viewer); the caller's page is kept on the stack so any
; depth restores correctly.
launch_app
                ld    de,fs_req_name         ; name -> fs_req_name (HL in caller page)
                call  copy11
                call  wm_alloc_page          ; grab a free bank page (not depth-based,
                or    a                       ; so it never collides with a co-resident
                ret   z                       ; WM window) -> A=page, 0 = none free
                ld    c,a                      ; C = target page
                push  bc                       ; save target page to free on return
                ld    a,(bank_cur)           ; save caller's page (per depth) on stack
                push  af
                ld    hl,(APP_HANDLER)       ; save the parent's event handler and clear
                push  hl                       ; it, so a top-bar click during the child
                ld    hl,0                     ; cannot call the parent's handler (whose
                ld    (APP_HANDLER),hl        ; page is not mapped while the child runs)
                ld    a,(MENU_DEF)           ; save & clear the parent's menu so the
                push  af                       ; child starts with a clean top bar
                xor   a
                ld    (MENU_DEF),a
                ld    hl,launch_depth
                inc   (hl)
                di
                ld    a,c
                call  bank_set
                ld    hl,#3F00
                ld    (fs_load_max),hl
                ld    hl,APP_BASE
                ld    (fs_load_dst),hl
                call  fs_load_file
                jr    nc,la_done             ; missing -> just unwind
                ei
                call  APP_BASE
                di
la_done
                ld    hl,launch_depth
                dec   (hl)
                pop   af                       ; restore the parent's menu count
                ld    (MENU_DEF),a
                pop   hl                       ; restore the parent's event handler
                ld    (APP_HANDLER),hl
                pop   af                       ; caller's page
                call  bank_set
                pop   bc                       ; target page -> release it
                ld    a,c
                call  wm_free_page
                                              ; (#77: the desktop redraws the bar via its
                                              ; always-run handler, no draw_topbar here)
                ld    a,(WM_NWIN)            ; if WM windows are live underneath (a modal
                or    a                       ; app launched from one), repaint them so
                call  nz,wm_repaint_all      ; the modal app's screen area is restored
                ei
la_escwait                                     ; if the app quit on ESC, wait for the
                ld    a,66                     ; key to be released before the parent
                call  KM_TEST_KEY              ; runs - else the same press quits it too,
                jr    nz,la_escwait            ; cascading all the way back to BASIC
                ret
launch_depth    db    0

; app_pool_init (#84): build the app-page pool from the detected bank count
; (md_banks). Index 0..2 = bank 0 blocks 1..3 (#C5..#C7; block 0 is PAGE_DATA);
; then each further bank contributes all four blocks (&C4 + bank*8 + block), the
; same value lib/bank.asm's bank_page forms. Appends until the list reaches
; WM_MAXWIN entries or RAM runs out. Sets APP_NPAGES; zeroes APP_BUSY. So the
; desktop (first claim) always lands in APP_PAGES[0] = PAGE_APP0 = #C5, and a
; plain 128K machine yields exactly 3 pages (desktop + 2), as before.
app_pool_init
                ld    hl,APP_PAGES
                ld    (hl),#C5               ; bank 0 block 1
                inc   hl
                ld    (hl),#C6               ; bank 0 block 2
                inc   hl
                ld    (hl),#C7               ; bank 0 block 3
                inc   hl
                ld    c,3                      ; C = entries so far
                ld    a,(md_banks)
                ld    b,a                      ; B = detected bank count
                ld    d,1                      ; D = bank index, from 1
api_bank        ld    a,d
                cp    b
                jr    nc,api_done             ; bank index >= count -> done
                ld    a,d
                add   a,a
                add   a,a
                add   a,a                      ; A = bank*8
                add   a,#C4                     ; A = &C4 + bank*8 (this bank's block 0)
                ld    e,a                       ; E = current port value
                add   a,4
                ld    (api_end),a              ; sentinel = base + 4 (one past block 3)
api_blk         ld    a,c
                cp    WM_MAXWIN
                jr    nc,api_done             ; list full -> stop
                ld    (hl),e                    ; store this block's port value
                inc   hl
                inc   c
                inc   e
                ld    a,(api_end)
                cp    e
                jr    nz,api_blk               ; more blocks in this bank
                inc   d                          ; next bank
                jr    api_bank
api_done        ld    a,c
                ld    (APP_NPAGES),a
                ld    hl,APP_BUSY              ; mark every page free
                ld    de,APP_BUSY+1
                ld    bc,WM_MAXWIN-1
                ld    (hl),0
                ldir
                ret
api_end         db    0
md_banks        db    0

; wm_alloc_page: claim the lowest free app page -> A = its port value, or 0 if all
; APP_NPAGES pages are in use. wm_free_page: A = the port value to release. The pool
; serves both co-resident WM windows (wm_open_go) and modal launch_app calls.
wm_alloc_page
                ld    a,(APP_NPAGES)
                or    a
                ret   z                         ; (defensive) no pages at all
                ld    b,a                        ; B = page count
                ld    hl,APP_BUSY
                ld    de,APP_PAGES
wap_scan        ld    a,(hl)
                or    a
                jr    z,wap_take                ; busy flag clear -> free slot
                inc   hl
                inc   de
                djnz  wap_scan
                xor   a                          ; none free
                ret
wap_take        ld    (hl),1                     ; mark busy
                ld    a,(de)                      ; A = its port value
                ret
wm_free_page                                     ; A = port value to release
                ld    b,a                         ; B = target port
                ld    a,(APP_NPAGES)
                or    a
                ret   z
                ld    c,a                          ; C = page count
                ld    hl,APP_PAGES
                ld    de,APP_BUSY
wfp_scan        ld    a,(hl)
                cp    b
                jr    z,wfp_hit
                inc   hl
                inc   de
                dec   c
                jr    nz,wfp_scan
                ret                                ; not found (defensive)
wfp_hit         xor   a
                ld    (de),a                       ; clear the parallel busy flag
                ret

; k_run (GB_RUN): run a named app. HL = 8.3 name (in the caller's page).
k_run
                jp    launch_app

; k_launch (GB_LAUNCH): the old MODAL open-the-current-entry. Superseded by the
; co-resident open path and no longer called by any app; kept as a stub so the
; jump-table address stays fixed.
k_launch
                ret

; Directory navigation (issue #54). The FAT backend enumerates the directory at
; fs_dir_clus; gb_chdir descends into the positioned entry (pushing the parent on
; a small stack) and gb_back pops it. On the floppy backend these touch FAT-only
; state the AMSDOS reader ignores, and gb_isdir is always 0 (no subdirectories),
; so the file manager simply never descends there.

; k_isdir (GB_ISDIR): A = 1 if the last-enumerated entry is a directory, else 0.
k_isdir
                ld    a,(fs_ent_attr)
                and   #10
                ret   z
                ld    a,1
                ret

; k_chdir (GB_CHDIR): descend into the positioned entry's directory - push the
; current dir cluster, then set it to the entry's start cluster. The next listing
; rewinds there. Refuses (no-op) when the stack is full.
k_chdir
                ld    a,(fs_dir_sp)
                cp    4                          ; DIRSTACK depth
                ret   nc
                add   a,a                         ; slot = fs_dir_stack + sp*4
                add   a,a
                ld    e,a
                ld    d,0
                ld    hl,fs_dir_stack
                add   hl,de
                ex    de,hl                       ; DE = slot
                ld    hl,fs_dir_clus             ; push current dir
                ld    bc,4
                ldir
                ld    hl,fs_dir_sp
                inc   (hl)
                ld    hl,fs_ent_clus             ; descend: dir = entry's cluster
                ld    de,fs_dir_clus
                ld    bc,4
                ldir
                ret

; k_back (GB_BACK): pop the dir stack into fs_dir_clus (parent directory); no-op
; at the top level.
k_back
                ld    a,(fs_dir_sp)
                or    a
                ret   z
                dec   a
                ld    (fs_dir_sp),a
                add   a,a                         ; slot = fs_dir_stack + sp*4
                add   a,a
                ld    e,a
                ld    d,0
                ld    hl,fs_dir_stack
                add   hl,de
                ld    de,fs_dir_clus
                ld    bc,4
                ldir
                ret

; k_entname (GB_ENTNAME): HL = the last-enumerated entry's raw 11-byte 8.3 name
; (space-padded, no dot) so an app can show the extension (gb_dir* return name-only).
k_entname
                ld    hl,fs_ent_name
                ret

; focus_arg_ptr: HL = the focused window's 11-byte file arg (per-window, so two
; editors keep separate files). Each window captured the pending launch_arg at
; gb_wm_add; getarg/setname/fsload/fssave all act on the focused window's copy.
focus_arg_ptr
                ld    a,(WM_FOCUS)
                call  wm_entry
                ld    de,WM_FR_ARG
                add   hl,de
                ret

; k_getarg (GB_GETARG): HL = the launch arg (the 8.3 file name the app opened).
k_getarg
                jp    focus_arg_ptr

; k_setname (GB_SETNAME): set the current file name so a later GB_FSLOAD/GB_FSSAVE
; targets it - how an app does New / Save As / open a picked file. HL = an 11-byte
; 8.3 name in the caller's page. Writes the focused window's per-window arg.
k_setname
                push  hl                       ; HL = src name
                call  focus_arg_ptr           ; HL = dst (focused window's arg)
                ex    de,hl                     ; DE = dst
                pop   hl                       ; HL = src
                call  copy11
                ret

; k_fsload (GB_FSLOAD): load the file the app was opened with (launch_arg) into a
; caller buffer. HL = dst (in the caller's page, which stays mapped through the
; FDC read - fsam_buf is resident, so no page swap), DE = max bytes. Returns
; BC = byte count (0 = missing / too big), CF set on success.
k_fsload
                ld    (fs_load_dst),hl
                ex    de,hl
                ld    (fs_load_max),hl
                call  focus_arg_ptr          ; load by the focused window's file name
                ld    de,fs_req_name
                call  copy11
                di
                call  fs_load_file
                ei
                ld    bc,0
                ret   nc                      ; not found / too big -> BC=0, NC
                ld    bc,(fs_ent_size)        ; content length (header already stripped)
                scf
                ret

; k_fssave (GB_FSSAVE): save the file the app was opened with (launch_arg). HL =
; src (caller's page, stays mapped), DE = byte count. Overwrites in place. CF set
; on success.
k_fssave
                ld    (fs_save_src),hl
                ex    de,hl
                ld    (fs_save_len),hl
                call  focus_arg_ptr          ; save by the focused window's file name
                ld    de,fs_req_name
                call  copy11
                di
                call  fs_save_file
                ei
                ret                            ; CF = saved

; k_getkey (GB_GETKEY): A = a typed character from the keyboard buffer, or 0 if
; none is waiting. Non-blocking (the firmware's IRQ scan fills the buffer).
; k_drive_poll (GB_DRIVES, #65): probe the drives GEOBENCH can reach and return a
; bitmask in A: bit0 = floppy A, bit1 = floppy B, bit2 = IDE (Disk C). Probing a
; floppy spins the motor + recalibrates (slow, noisy) - call at boot and on demand.
k_drive_poll
                ld    c,0                          ; result bits
                call  fs_ide_present               ; IDE -> Disk C (bit2)
                jr    nc,kdp_a
                set   2,c
kdp_a
                push  bc
                xor   a                             ; floppy A = unit 0
                ld    (fsam_unit),a
                call  fsam_present
                pop   bc
                jr    nc,kdp_b
                set   0,c
kdp_b
                push  bc
                ld    a,1                           ; floppy B = unit 1
                ld    (fsam_unit),a
                call  fsam_present
                pop   bc
                jr    nc,kdp_done
                set   1,c
kdp_done
                xor   a                             ; leave the floppy backend on unit 0
                ld    (fsam_unit),a
                ld    a,c
                ret

; k_get_drive (GB_GETDRIVE, #65): A = the current active drive (0=IDE/C, 1=A, 2=B).
; A window reads this at startup to learn which drive it was opened on. (GB_SETDRIVE
; jumps straight to fs_set_drive.)
k_get_drive
                ld    a,(fs_cur_drive)
                ret

; Cross-drive copy (#65 phase 3): the orchestration moved into the File Manager (C)
; to reclaim resident space (#74). The kernel just flips the active drive+dir context
; between the dragged file's source (captured at drag start) and the drop target; the
; app does the load->save itself through the shared staging buffer (GBFAT_DATA).
;
; k_copy_begin (GB_COPYBEGIN): save the current (target) drive+dir, then switch to the
; source drive+dir, so the caller can load the dragged file. Pairs with k_copy_end.
k_copy_begin
                ld    a,(fs_cur_drive)        ; save the caller's (target) context
                ld    (cb_tdrv),a
                ld    hl,fs_dir_clus
                ld    de,cb_tdir
                ld    bc,4
                ldir
                ld    a,(WM_DRAGDRV)         ; switch to the drag source drive + dir
                call  fs_set_drive
                ld    hl,WM_DRAGDIR
                ld    de,fs_dir_clus
                ld    bc,4
                ldir
                ret
; k_copy_end (GB_COPYEND): restore the saved (target) drive+dir, so the caller can
; re-list its own directory.
k_copy_end
                ld    a,(cb_tdrv)
                call  fs_set_drive
                ld    hl,cb_tdir
                ld    de,fs_dir_clus
                ld    bc,4
                ldir
                ret
cb_tdrv         db    0
cb_tdir         defs  4

; k_fs_delete (GB_FSDELETE, #62): HL = 11-byte 8.3 name in the caller page. Delete
; that file from the current directory (free clusters + clear the dir entry) via
; the paged GBFAT module. CF set = deleted. Used by drag-to-Trash.
k_fs_delete
                ld    de,fs_req_name
                call  copy11
                di
                call  fs_delete_file
                ei
                ret

k_getkey
                call  KM_READ_CHAR           ; CF + A = char, or NC = none. (Apps frame
                jr    nc,kgk_none            ; on IY now, so KM_READ_CHAR clobbering IX
                                              ; is harmless - see build_capp.sh.)
                ; The pointer is the joystick/cursor keys, and the firmware also
                ; buffers those as characters - so moving the pointer would flood a
                ; keyboard app (Notepad redrawing on every move). While any pointing
                ; direction is physically held, the "char" is the pointer, not
                ; typing: drop it. KM_TEST_KEY preserves B/DE/HL.
                ld    (kgk_char),a           ; save char in memory (KM_TEST_KEY may
                ld    hl,kgk_dirkeys         ; corrupt HL/BC, so don't trust regs)
                ld    b,(hl)
kgk_test
                inc   hl
                ld    a,(hl)
                push  hl
                push  bc
                call  KM_TEST_KEY
                pop   bc
                pop   hl
                jr    nz,kgk_none            ; a direction held -> discard the char
                djnz  kgk_test
                ld    a,(kgk_char)           ; a genuine typed character
                ret
kgk_none
                xor   a
                ret
kgk_char        db    0
kgk_dirkeys     db    10, 0,1,2,8, 72,73,74,75, 76,77 ; cursor + joystick dirs + fire
                                              ; (fire = the click; it also buffers a
                                              ; char, e.g. 'Z' - drop it while held)

; k_vsync (GB_VSYNC): no longer used - apps are frame-paced by the WM loop (on_frame
; runs once per k_poll) rather than driving their own gb_vsync loop. Stubbed to a
; sane "no ESC" return; ABI slot kept so the jump-table address stays fixed.
k_vsync
                xor   a
                ret

; k_onevent (GB_ONEVENT): register the calling app's event handler. HL = handler
; address (a void(void) C function in the app's page), 0 to unregister. The
; kernel calls it from menu_dispatch with a message in GB_MSG.
k_onevent
                ld    (APP_HANDLER),hl
                ret

; k_onrepaint (GB_ONREPAINT): now a no-op kept for ABI. Under the window manager
; an app's repaint handler lives in its gb_win_t (on_repaint); the old per-depth
; REPAINT_HDLR table is unused. Left as a stub so the jump-table address is fixed.
k_onrepaint
                ret

; k_restore_parent (GB_RESTPAR): repaint everything behind the caller. Under the
; window manager (issue #45) the live windows below a modal app are exactly the WM
; windows, so this repaints them all bottom-up (wm_repaint_all) - e.g. a modal
; Notepad dragging its window restores the desktop + file manager underneath, then
; redraws itself on top. (Replaces the old per-depth REPAINT_HDLR walk, which the
; co-resident model made obsolete.)
k_restore_parent
                jp    wm_repaint_all

; ---- cooperative window manager (issue #45, phase 2) --------------------------
; The kernel owns the master loop (wm_loop) and a table of co-resident windows.
; The root window (desktop) enters the loop via GB_WMRUN; further windows are
; opened non-blocking with GB_WMOPEN (load app -> its main calls GB_WMADD and
; returns). The loop polls, then on a fresh click hit-tests the windows top-down
; (z-order) and raises+focuses the one clicked, then calls the focused window's
; on_frame. A window closes itself with GB_WMCLOSE.
;
; A descriptor is { u8 x,y,w,h; on_frame(2); on_repaint(2); on_event(2) }.

; wm_register: HL = descriptor in the caller's page. Allocate a table slot, store
; page = caller, copy the descriptor, mark alive, push onto z-order top and focus.
wm_register
                ld    (wm_desc),hl
                call  wm_free_slot               ; A = first dead slot
                ld    (wm_slot),a
                call  wm_entry                    ; HL = WM_TABLE[slot]
                ld    a,(bank_cur)               ; +0 page = caller
                ld    (hl),a
                inc   hl
                ex    de,hl                       ; DE = entry+1
                ld    hl,(wm_desc)
                ld    bc,12                       ; x,y,w,h,on_frame,on_repaint,on_event,menu
                ldir
                ld    a,1                          ; entry+13 flags = alive
                ld    (de),a
                inc   de                            ; entry+14 = arg: capture the pending
                ld    hl,launch_arg               ; launch arg as this window's own file
                call  copy11
                ld    a,(wm_slot)                 ; focus the new window
                ld    (WM_FOCUS),a
                ld    hl,WM_Z                      ; WM_Z[NWIN] = slot (new z-top)
                ld    a,(WM_NWIN)
                add   a,l
                ld    l,a
                ld    a,(wm_slot)
                ld    (hl),a
                ld    hl,WM_NWIN
                inc   (hl)
                ret

; wm_free_slot: -> A = lowest table slot whose alive flag is clear.
wm_free_slot
                ld    hl,WM_TABLE+WM_FR_FLAGS
                ld    de,WM_ESZ
                ld    c,0
wfs_l           ld    a,(hl)
                and   1
                jr    z,wfs_found
                add   hl,de
                inc   c
                ld    a,c
                cp    WM_MAXWIN
                jr    c,wfs_l
                ld    c,WM_MAXWIN-1               ; full (shouldn't happen) -> reuse last
wfs_found       ld    a,c
                ret

; k_wm_run (GB_WMRUN): register the caller (the root/desktop window) and enter the
; master loop. Never returns.
k_wm_run
                call  wm_register
wm_loop
                call  wm_map_focus               ; bank focused page; APP_HANDLER = its
                call  k_poll                      ; on_event, so a top-bar click reaches
                call  wm_focus_click             ; the right app. then route the click.
                call  wm_map_focus               ; focus may have changed
                ld    a,(WM_FOCUS)               ; call the focused window's on_frame
                call  wm_entry
                ld    de,WM_FR_FRAME
                add   hl,de
                ld    a,(hl)
                inc   hl
                ld    h,(hl)
                ld    l,a
                call  md_call
                ld    hl,(BAR_HANDLER)            ; top-bar hook (#77): run the bar handler
                ld    a,h                          ; every frame in the desktop's page, so the
                or    l                            ; bar stays live regardless of which window
                jr    z,wm_loop                    ; has focus
                ld    a,PAGE_APP0
                call  bank_set
                ld    hl,(BAR_HANDLER)
                call  md_call
                jr    wm_loop

; k_on_bar (GB_ONBAR #77): HL = a handler the WM loop runs every frame in PAGE_APP0
; (the desktop's page) to draw the top bar, independent of focus. 0 to clear.
k_on_bar
                ld    (BAR_HANDLER),hl
                ret

; k_wm_add (GB_WMADD): register the caller's window (used by an app opened with
; GB_WMOPEN); returns to the opener. The kernel's wm_loop then services it.
k_wm_add
                jp    wm_register

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
; File Manager (C); it now calls GB_WMLAUNCHAS with the app it chose. Kept as a
; stub so the jump-table address stays fixed.
k_wm_launch
                ret

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
                call  wm_alloc_page
                or    a
                ret   z                            ; no free page
                ld    (wm_open_page),a
                ld    a,(bank_cur)
                ld    (wm_open_back),a
                di
                ld    a,(wm_open_page)
                call  bank_set
                ld    hl,#3F00
                ld    (fs_load_max),hl
                ld    hl,APP_BASE
                ld    (fs_load_dst),hl
                call  fs_load_sys                 ; app binary -> always the boot drive,
                jr    nc,wmo_fail                 ; not the window's browse drive (#65)
                ei
                call  APP_BASE                    ; main -> GB_WMADD + paint, then ret
                di
                ld    a,(wm_open_back)
                call  bank_set
                ei
                ret
wmo_fail
                ld    a,(wm_open_back)
                call  bank_set
                ld    a,(wm_open_page)
                call  wm_free_page
                ei
                ret

; k_wm_close (GB_WMCLOSE): close the focused (calling) window - free its page, drop
; it from the table and z-order, refocus the new z-top, and repaint. The caller's
; on_frame must return immediately after. Mapping is unchanged on return so the
; closing on_frame can still execute (its page content survives until reused).
k_wm_close
                ld    a,(WM_FOCUS)
                call  wm_set_clip                 ; damage = the closing window's rect
                ld    a,(WM_FOCUS)
                ld    c,a                          ; C = slot being closed
                call  wm_entry                    ; HL = entry
                push  hl
                ld    a,(hl)                       ; page
                call  wm_free_page
                pop   hl
                ld    de,WM_FR_FLAGS
                add   hl,de
                ld    (hl),0                       ; mark dead
                ld    hl,WM_Z                      ; compact WM_Z, dropping slot C
                ld    de,WM_Z
                ld    a,(WM_NWIN)
                ld    b,a
wmc_l           ld    a,(hl)
                cp    c
                jr    z,wmc_skip
                ld    (de),a
                inc   de
wmc_skip        inc   hl
                djnz  wmc_l
                ld    hl,WM_NWIN
                dec   (hl)
                ld    a,(WM_NWIN)                  ; new focus = z-top = WM_Z[NWIN-1]
                dec   a
                ld    hl,WM_Z
                add   a,l
                ld    l,a
                ld    a,(hl)
                ld    (WM_FOCUS),a
                jp    wm_repaint_all               ; repaint remaining windows + return

; k_wm_setpos (GB_WMSETPOS): A = x, L = y -> move the focused window's hit rect to
; (x,y), so click-to-focus follows a window the app has dragged. Also sets the fill
; clip to the damage = the bounding box of the old and new window rects, so the
; following gb_restore_parent only repaints there (no full-screen flicker).
k_wm_setpos
                ld    (sp_x),a                    ; new x
                ld    a,l
                ld    (sp_y),a                    ; new y
                ld    a,(WM_FOCUS)
                call  wm_entry                    ; HL = entry (+0); damage_axis keeps HL
                inc   hl                            ; +1 old x
                ld    b,(hl)
                inc   hl
                inc   hl                            ; +3 w
                ld    c,(hl)
                ld    a,(sp_x)
                call  damage_axis                 ; D = min(ox,nx), E = span
                ld    a,d
                ld    (clip_x),a
                ld    a,e
                ld    (clip_w),a
                dec   hl                            ; +2 old y
                ld    b,(hl)
                inc   hl
                inc   hl                            ; +4 h
                ld    c,(hl)
                ld    a,(sp_y)
                call  damage_axis
                ld    a,d
                ld    (clip_y),a
                ld    a,e
                ld    (clip_h),a
                dec   hl                            ; +4 -> +1 (x)
                dec   hl
                dec   hl
                ld    a,(sp_x)                     ; commit the new position
                ld    (hl),a
                inc   hl
                ld    a,(sp_y)
                ld    (hl),a
                ret
sp_x            db    0
sp_y            db    0

; k_wm_setsize (GB_WMSETSIZE, #81): A = new w, L = new h. Resize the focused window's
; rect (top-left stays put). Damage clip = its (x,y) covering max(old,new) size, so the
; following gb_restore_parent repaints any area a shrink vacated.
k_wm_setsize
                ld    (ss_w),a
                ld    a,l
                ld    (ss_h),a
                ld    a,(WM_FOCUS)
                call  wm_entry                    ; HL = entry (+0 page)
                inc   hl                            ; +1 x
                ld    a,(hl)
                ld    (clip_x),a                  ; clip x = window x (unchanged)
                inc   hl                            ; +2 y
                ld    a,(hl)
                ld    (clip_y),a
                inc   hl                            ; +3 w
                ld    b,(hl)                       ; old w
                ld    a,(ss_w)                     ; clip w = max(old, new)
                cp    b
                jr    nc,kss_w
                ld    a,b
kss_w
                ld    (clip_w),a
                ld    a,(ss_w)
                ld    (hl),a                       ; commit new w
                inc   hl                            ; +4 h
                ld    b,(hl)                       ; old h
                ld    a,(ss_h)
                cp    b
                jr    nc,kss_h
                ld    a,b
kss_h
                ld    (clip_h),a
                ld    a,(ss_h)
                ld    (hl),a                       ; commit new h
                ret
ss_w            db    0
ss_h            db    0

; damage_axis: B = old, A = new, C = size -> D = min(old,new), E = span =
; max(old,new) + size - min. The 1-D damage extent of a move. Preserves HL.
damage_axis
                cp    b
                jr    nc,dax_oldmin              ; new >= old -> min = old, max = new
                ld    d,a                           ; min = new
                ld    a,b                           ; max = old
                jr    dax_span
dax_oldmin      ld    d,b                           ; min = old (A = new = max)
dax_span        add   a,c                           ; max + size
                sub   d                             ; - min
                ld    e,a
                ret

; wm_map_focus: bank to the focused window's page and point APP_HANDLER at its
; on_event (so menu_dispatch in k_poll delivers top-bar clicks to the focused app).
; On a focus change, also swap the top-bar menu to the focused window's (or clear
; it) so the bar shows the right menu and clicks reach the right handler.
wm_map_focus
                ld    a,(WM_FOCUS)
                call  wm_entry                    ; HL = entry
                ld    a,(hl)                       ; page (+0)
                call  bank_set                     ; preserves HL
                push  hl
                ld    de,WM_FR_EVENT
                add   hl,de
                ld    a,(hl)
                inc   hl
                ld    h,(hl)
                ld    l,a
                ld    (APP_HANDLER),hl
                pop   hl                            ; HL = entry
                ld    a,(WM_FOCUS)               ; focus changed since last frame?
                ld    de,WM_FPREV
                ld    a,(de)
                ld    b,a
                ld    a,(WM_FOCUS)
                cp    b
                ret   z                            ; no change -> leave the bar as is
                ld    (de),a                       ; WM_FPREV = focus
                ld    de,WM_FR_MENU               ; focused window's menu def ptr
                add   hl,de
                ld    a,(hl)
                inc   hl
                ld    h,(hl)
                ld    l,a
                ld    a,h
                or    l
                jp    z,menu_clear                 ; no menu -> empty the bar
                jp    menu_install                 ; install the focused window's menu

; wm_focus_click: if a fresh click landed on a window other than the focused one,
; move focus there. App windows also rise to the z-top (and the stack repaints) if
; not already on top; the desktop (slot 0) stays pinned at the bottom. The click is
; not consumed - it is then delivered to the newly focused window's on_frame.
wm_focus_click
                ld    a,(POLL_FLAGS)
                bit   0,a
                ret   z                            ; no fresh click
                call  wm_hit_test                  ; CF set = no window hit (e.g. top bar)
                ret   c
                ld    b,a
                ld    a,(WM_FOCUS)
                cp    b
                ret   z                            ; already focused -> deliver
                ld    a,b
                ld    (WM_FOCUS),a               ; focus the clicked window
                or    a
                ret   z                            ; desktop: keep it at the bottom
                ld    c,a                          ; c = clicked app slot
                ld    a,(WM_NWIN)               ; already the z-top? then nothing to raise
                dec   a
                ld    hl,WM_Z
                add   a,l
                ld    l,a
                ld    a,(hl)
                cp    c
                ret   z
                ld    a,c
                call  wm_raise                     ; bring it to the front
                ld    a,(WM_FOCUS)               ; damage = the raised window's rect
                call  wm_set_clip
                jp    wm_repaint_all               ; restack the screen (clipped)

; wm_hit_test: -> A = slot of the top-most window whose rect contains the pointer
; (POLL_MX, POLL_MY), scanning z-order top->bottom; CF set if none.
wm_hit_test
                ld    a,(WM_NWIN)
                ld    (wm_hz),a
wht_l           ld    a,(wm_hz)
                or    a
                jr    z,wht_none
                dec   a
                ld    (wm_hz),a
                ld    hl,WM_Z
                add   a,l
                ld    l,a
                ld    a,(hl)                       ; slot = WM_Z[i]
                call  wm_entry                     ; HL = entry
                inc   hl                            ; +1 x
                ld    a,(POLL_MX)
                sub   (hl)
                jr    c,wht_l                       ; mx < x
                ld    c,a                            ; mx - x
                inc   hl                            ; +2 y
                inc   hl                            ; +3 w
                ld    a,c
                cp    (hl)
                jr    nc,wht_l                      ; mx-x >= w
                dec   hl                            ; +2 y
                ld    a,(POLL_MY)
                sub   (hl)
                jr    c,wht_l                       ; my < y
                ld    c,a                            ; my - y
                inc   hl                            ; +3 w
                inc   hl                            ; +4 h
                ld    a,c
                cp    (hl)
                jr    nc,wht_l                      ; my-y >= h
                ld    a,(wm_hz)                     ; hit -> recover slot
                ld    hl,WM_Z
                add   a,l
                ld    l,a
                ld    a,(hl)
                or    a                             ; clear CF
                ret
wht_none        scf
                ret

; k_drag_start (GB_DRAGSTART, #62): HL = 11-byte 8.3 name of the dragged item in
; the caller (source) page. Record it, then run a drag loop (the WM loop is
; suspended) that follows the pointer until the fire button is released. On release,
; if the pointer moved and the drop point is over a different live window that has
; an on_event handler, deliver a GB_MSG_DROP to it (its page mapped) - it reads the
; name from WM_DRAGNAME and the drop position from gb_mx/gb_my. Returns A = 1 if it
; was dropped on a target, A = 0 if it was just a click (no move / no target /
; dropped on itself) so the source can fall through to its normal click handling.
k_drag_start
                ld    de,WM_DRAGNAME              ; stash the dragged name
                call  copy11
                ld    a,(bank_cur)               ; remember the source page to restore
                ld    (wm_drag_pg),a
                ld    a,(WM_FOCUS)               ; source = the focused (calling) window
                ld    (WM_DRAGSRC),a
                ld    a,(fs_cur_drive)           ; capture the source drive + directory now
                ld    (WM_DRAGDRV),a             ; (active = the source FM's) for a later
                ld    hl,fs_dir_clus             ; cross-drive copy (#65 phase 3)
                ld    de,WM_DRAGDIR
                ld    bc,4
                ldir
                xor   a
                ld    (WM_DRAGMOV),a             ; moved = 0, ghost not shown yet
                ld    (ghost_on),a
                ld    a,(POLL_MX)                ; seed the last position
                ld    (WM_DRAGX0),a
                ld    a,(POLL_MY)
                ld    (WM_DRAGY0),a
ds_loop
                call  k_poll                      ; pace 50Hz + track pointer + POLL_*
                ld    a,(POLL_MX)                ; moved since last frame?
                ld    hl,WM_DRAGX0
                cp    (hl)
                jr    nz,ds_moved
                ld    a,(POLL_MY)
                ld    hl,WM_DRAGY0
                cp    (hl)
                jr    z,ds_held                   ; stationary -> leave the ghost as is
ds_moved        ld    a,(POLL_MX)                ; record the new last position
                ld    (WM_DRAGX0),a
                ld    a,(POLL_MY)
                ld    (WM_DRAGY0),a
                ld    a,1
                ld    (WM_DRAGMOV),a
                ld    a,(ghost_on)               ; ghost already up? -> move it
                or    a
                jr    nz,ds_gtrack
                call  cursor_erase                ; first movement: hide the arrow and
                ld    a,1                          ; show a box that follows the pointer
                ld    (cur_supp),a
                ld    (ghost_on),a
                ld    a,GHOST_W                   ; the box's save-under is fixed-size in
                ld    (sb_w),a                     ; the idle IDE sector buffer; set once
                ld    a,GHOST_H
                ld    (sb_h),a
                ld    hl,fs_secbuf
                ld    (sb_buf),hl
                jr    ds_gpaint
ds_gtrack       call  restore_block               ; erase the box at its old place
ds_gpaint       call  ghost_place
                call  ghost_draw
ds_held         ld    a,(POLL_FLAGS)            ; fire still held -> keep dragging
                bit   2,a
                jr    nz,ds_loop
                ld    a,(ghost_on)               ; released: tear the ghost down and
                or    a                            ; bring the arrow back
                jr    z,ds_norel
                call  restore_block               ; erase the box
                xor   a
                ld    (ghost_on),a
                ld    (cur_supp),a               ; A = 0 -> cursor visible again
                call  cursor_draw
ds_norel
                ld    a,(WM_DRAGMOV)            ; never moved -> a plain click
                or    a
                jr    z,ds_click
                call  wm_hit_test                 ; CF = nothing under the drop point
                jr    c,ds_click
                ld    b,a                          ; B = target slot
                ld    a,(WM_DRAGSRC)
                cp    b
                jr    z,ds_click                   ; dropped on itself -> no-op
                ld    a,b
                call  wm_entry                     ; HL = target entry
                ld    c,(hl)                       ; C = target page (+0)
                ld    de,WM_FR_EVENT               ; target's on_event handler
                add   hl,de
                ld    a,(hl)
                inc   hl
                ld    h,(hl)
                ld    l,a
                ld    a,h
                or    l
                jr    z,ds_click                   ; no handler -> treat as a click
                ld    a,GB_MSG_DROP
                ld    (GB_MSG),a
                ld    a,c                           ; map the target's page, call it
                call  bank_set                      ; (it reads WM_DRAGNAME + POLL_MX/MY)
                call  md_call
                ld    a,(wm_drag_pg)              ; restore the source page
                call  bank_set
                ld    a,1
                ret
ds_click
                ld    a,(wm_drag_pg)              ; ensure the source page is mapped
                call  bank_set
                xor   a
                ret
wm_drag_pg      db    0

; ghost_place: sb_x/sb_y = the pointer (POLL_MX/MY), clamped so the GHOST_W x
; GHOST_H box stays on screen. sb_w/sb_h/sb_buf were set once when the ghost first
; appeared (they only change when the cursor save-under runs, which is suppressed
; during the drag), so erase = restore_block and draw = save_block + outline.
ghost_place
                ld    a,(POLL_MX)
                cp    80-GHOST_W+1
                jr    c,gpl_x
                ld    a,80-GHOST_W
gpl_x           ld    (sb_x),a
                ld    a,(POLL_MY)
                cp    200-GHOST_H+1
                jr    c,gpl_y
                ld    a,200-GHOST_H
gpl_y           ld    (sb_y),a
                ret

; ghost_draw: save the screen under the box, then draw a red outline there.
ghost_draw
                call  save_block
                ld    a,(sb_x)
                ld    b,a
                ld    a,(sb_y)
                ld    c,a
                ld    d,GHOST_W
                ld    e,GHOST_H
                ld    a,3
                jp    k_frame

ghost_on        db    0

; wm_raise: A = slot -> move it to z-order top and focus it (keeps the others'
; relative order). Compacts WM_Z removing the slot, then re-appends it at the end.
wm_raise
                ld    (WM_FOCUS),a
                ld    c,a
                ld    hl,WM_Z
                ld    de,WM_Z
                ld    a,(WM_NWIN)
                ld    b,a
wr_l            ld    a,(hl)
                cp    c
                jr    z,wr_skip
                ld    (de),a
                inc   de
wr_skip         inc   hl
                djnz  wr_l
                ld    a,c
                ld    (de),a                       ; slot back on top
                ret

; wm_repaint_all: repaint every window bottom-up (each in its own page, via its
; on_repaint), then restore the caller's page. The cursor is left to the handlers:
; each on_repaint redraws over the old pointer (a full backdrop fill, or a leading
; gb_curhide) and ends with gb_curshow, so the cursor stays correct with no double
; save-under here. WM_Z[0] is always the desktop, so its full paint runs first.
wm_repaint_all
                ld    a,(bank_cur)
                ld    (wm_rp_back),a
                di
                xor   a
                ld    (wm_rp_i),a
wra_l           ld    a,(wm_rp_i)
                ld    hl,WM_NWIN
                cp    (hl)
                jr    nc,wra_done
                ld    hl,WM_Z
                add   a,l
                ld    l,a
                ld    a,(hl)                       ; slot = WM_Z[i]
                call  wm_entry                     ; HL = entry
                ld    a,(hl)                       ; page
                call  bank_set
                ld    de,WM_FR_REPAINT
                add   hl,de
                ld    a,(hl)
                inc   hl
                ld    h,(hl)
                ld    l,a
                ld    a,h
                or    l
                jr    z,wra_next                   ; no handler
                call  md_call
wra_next        ld    a,(wm_rp_i)
                inc   a
                ld    (wm_rp_i),a
                jr    wra_l
wra_done        ld    a,(wm_rp_back)
                call  bank_set
                call  clip_set_full              ; repaints are clip-limited; restore the
                ei                                ; full-screen clip for normal drawing
                ret

; clip_set_full: reset the fill clip to the whole screen (no clipping).
clip_set_full
                xor   a
                ld    (clip_x),a
                ld    (clip_y),a
                ld    a,80
                ld    (clip_w),a
                ld    a,200
                ld    (clip_h),a
                ret

; wm_set_clip: A = slot -> set the fill clip to that window's rect, so the next
; wm_repaint_all only erases inside the window's area (its damage region).
wm_set_clip
                call  wm_entry                    ; HL = entry
                inc   hl                            ; +1 x
                ld    a,(hl)
                ld    (clip_x),a
                inc   hl                            ; +2 y
                ld    a,(hl)
                ld    (clip_y),a
                inc   hl                            ; +3 w
                ld    a,(hl)
                ld    (clip_w),a
                inc   hl                            ; +4 h
                ld    a,(hl)
                ld    (clip_h),a
                ret

; wm_entry: A = slot index -> HL = WM_TABLE + A*WM_ESZ. Clobbers A,B,DE.
wm_entry
                ld    hl,WM_TABLE
                or    a
                ret   z
                ld    b,a
                ld    de,WM_ESZ
we_add
                add   hl,de
                djnz  we_add
                ret

wm_desc         dw    0            ; wm_register: descriptor ptr
wm_slot         db    0            ; wm_register: chosen slot
wm_open_page    db    0            ; k_wm_open: page being loaded
wm_open_back    db    0            ; k_wm_open: caller's page to restore
wm_hz           db    0            ; wm_hit_test: z scan index
wm_rp_back      db    0            ; wm_repaint_all: caller's page
wm_rp_i         db    0            ; wm_repaint_all: z index

; menu_dispatch: called from k_poll. If a fresh click (D bit0) landed in the
; kernel-owned top bar and the app registered a handler, deliver a GB_MSG_MENU
; message (p0 = byte column) and consume the click. The app's page is mapped
; (it called GB_POLL), so the handler is a direct CALL - no bank trampoline.
menu_dispatch
                bit   0,d                     ; fresh click this frame?
                ret   z
                ld    a,(poll_line)
                cp    8                        ; inside the 8px top bar (rows 0..7)?
                ret   nc
                ld    hl,(APP_HANDLER)        ; handler registered?
                ld    a,h
                or    l
                ret   z
                res   0,d                      ; consume the click (the app's poll
                ld    a,GB_MSG_MENU            ; loop won't also see it)
                ld    (GB_MSG),a
                ld    a,(poll_byte)
                ld    (GB_MSG+1),a            ; p0 = clicked byte column
                push  de                       ; preserve the poll flags across the
                call  md_call                  ; C handler (call (hl))
                pop   de
                ret
md_call         jp    (hl)

; k_menu (GB_MENU): register the calling app's top-bar menu. HL = a blob in the
; app page: count, then per title { col (byte), 8-byte NUL/space-padded label }.
; Copied into resident MENU_DEF; the desktop's bar handler watches MENU_DEF and
; redraws the titles when it changes (#77). launch_app clears it for a child app.
k_menu
menu_install                                    ; HL = menu def (mapped page) -> MENU_DEF
                ld    a,(hl)                  ; count
                cp    5
                ret   nc                       ; > 4 titles unsupported -> ignore
                ld    e,a                       ; len = count*9 + 1
                add   a,a
                add   a,a
                add   a,a
                add   a,e
                inc   a
                ld    c,a
                ld    b,0
                ld    de,MENU_DEF
                ldir
                ret
; menu_clear: empty the top-bar menu (focus moved to a window with no menu).
menu_clear
                xor   a
                ld    (MENU_DEF),a
                ret

; (menu titles are rendered by the desktop's bar handler now, from MENU_DEF - #77)

; (File-type -> app routing lives in the File Manager now; the kernel just opens
; the app the FM names, via GB_WMLAUNCHAS. The old resident app_for_ext + its name
; tables were removed to reclaim space - the kernel->C migration that funds the
; .APP launch model, #70.)
launch_arg      defs  11

; k_icon (GB_ICON): blit a full icon. A = slot, B = x, C = y. Reads the bitmap
; from the .IST in PAGE_DATA, so swap pages around it.
k_icon
                ld    (gi_slot),a
                ld    a,b
                ld    (gi_x),a
                ld    a,c
                ld    (gi_y),a
                call  to_data
                ld    a,(gi_slot)
                call  icon_full_geom
                call  blit_bitmap
                jp    from_data
icon_full_geom                                 ; A = slot -> bm_src/w/h, bm_x/y
                ld    l,a
                ld    h,0
                add   hl,hl
                add   hl,hl                     ; slot*4
                ld    de,DATA_ICONS+16
                add   hl,de
                ld    e,(hl)                  ; offset
                inc   hl
                ld    d,(hl)
                inc   hl
                ld    a,(hl)                  ; width
                ld    (bm_w),a
                inc   hl
                ld    a,(hl)                  ; height (full)
                ld    (bm_h),a
                ld    hl,DATA_ICONS
                add   hl,de
                ld    (bm_src),hl
                ld    a,(gi_x)
                ld    (bm_x),a
                ld    a,(gi_y)
                ld    (bm_y),a
                ret
gi_slot         db    0
gi_x            db    0
gi_y            db    0

; k_fill (GB_FILL): filled rectangle. B=x C=y D=w E=h A=pen. Capture the params
; before pen_to_byte (it clobbers E).
k_fill
                ld    (kf_pen),a
                ld    a,b
                ld    (fb_x),a
                ld    a,c
                ld    (fb_y),a
                ld    a,d
                ld    (fb_w),a
                ld    a,e
                ld    (fb_h),a
                ld    a,(kf_pen)
                call  pen_to_byte
                ld    (fb_val),a
                jp    fill_block
kf_pen          db    0

; k_saverect / k_restorerect (GB_SAVERECT / GB_RESTORERECT): save/restore a
; screen rectangle to/from a caller buffer. B=x C=y D=w E=h HL=buffer (w*h
; bytes). The buffer lives in the caller's page (mapped during the call); the
; screen is resident, so no page swap is needed.
; k_saverect / k_restorerect (GB_SAVERECT / GB_RESTORERECT): stubs. No app uses
; them and there is no gb_saverect/gb_restorerect binding; bodies removed to
; reclaim resident space. Slots kept so addresses are fixed. (save_block /
; restore_block remain - the cursor save-under still uses them.)
k_saverect
k_restorerect
                ret

; k_xorframe (GB_XORFRAME): stub. The rubber-band XOR frame was never wired up
; (no app uses it, no gb_xorframe binding); body removed to reclaim resident
; space for the callback API. The jump-table slot stays so addresses are fixed.
k_xorframe
                ret

; ===========================================================================
; Top bar (kernel-owned): total RAM (left) + clock (right) on lines 0-7. The
; kernel keeps the clock ticking via clock_tick in k_poll, so it stays live
; whatever app is focused. Apps must keep clear of the top 8 lines.
; ===========================================================================
CLK_COL         equ   68
TICKS_PER_SEC   equ   50
RTC_ADDR        equ   #FD15        ; Dallas RTC on SymbiFace II / Cyboard
RTC_DATA        equ   #FD14

; clock_tick: once per frame from k_poll. Advances the software clock (when there is
; no RTC) every 50 frames, so gb_time stays correct. The desktop draws the bar now,
; so there is no clock drawing here (#77).
clock_tick
                ld    a,(clk_frames)
                inc   a
                cp    TICKS_PER_SEC
                jr    c,ct_keep
                xor   a
                ld    (clk_frames),a
                ld    a,(have_rtc)
                or    a
                call  z,sw_tick
                ret
ct_keep
                ld    (clk_frames),a
                ret

clock_init                                      ; detect the RTC + seed the software clock
                xor   a
                ld    (sw_sec),a
                ld    (sw_min),a
                ld    (sw_hour),a
                ld    (clk_frames),a
                call  rtc_detect
                ret
rtc_detect
                ld    e,#5A
                call  rtc_nvram_rw
                cp    #5A
                jr    nz,rd_none
                ld    e,#A5
                call  rtc_nvram_rw
                cp    #A5
                jr    nz,rd_none
                ld    a,1
                ld    (have_rtc),a
                ret
rd_none
                xor   a
                ld    (have_rtc),a
                ret
rtc_nvram_rw                                   ; E = value -> A = read-back of NVRAM 0x0E
                ld    a,#0E
                ld    bc,RTC_ADDR
                out   (c),a
                ld    bc,RTC_DATA
                out   (c),e
                ld    a,#0E
                ld    bc,RTC_ADDR
                out   (c),a
                ld    bc,RTC_DATA
                in    a,(c)
                ret
read_rtc_reg                                   ; A = reg -> A = value
                ld    bc,RTC_ADDR
                out   (c),a
                ld    bc,RTC_DATA
                in    a,(c)
                ret
; (read_time / put_bcd2 / bin_to_bcd removed: the desktop formats the clock from
; gb_time now - #77. sw_tick stays: it advances the software clock for gb_time.)
sw_tick
                ld    a,(sw_sec)
                inc   a
                cp    60
                jr    c,swt_sec
                xor   a
                ld    (sw_sec),a
                ld    a,(sw_min)
                inc   a
                cp    60
                jr    c,swt_min
                xor   a
                ld    (sw_min),a
                ld    a,(sw_hour)
                inc   a
                cp    24
                jr    c,swt_hour
                xor   a
swt_hour
                ld    (sw_hour),a
                ret
swt_min
                ld    (sw_min),a
                ret
swt_sec
                ld    (sw_sec),a
                ret
; k_time (GB_TIME #808D): current time -> GB_TIME_BUF (raw h, m, s + binmode). From
; the Dallas RTC (regs 4/2/0; binmode = reg B bit2) or the software clock (binary).
; The app converts BCD->binary when binmode is 0. Kept tiny (#72).
k_time
                ld    a,(have_rtc)
                or    a
                jr    z,kt_soft
                ld    a,#0B
                call  read_rtc_reg
                and   #04
                ld    (GB_TIME_BUF+3),a       ; binmode (0 = BCD)
                ld    a,#04
                call  read_rtc_reg
                and   #3F
                ld    (GB_TIME_BUF+0),a
                ld    a,#02
                call  read_rtc_reg
                ld    (GB_TIME_BUF+1),a
                ld    a,#00
                call  read_rtc_reg
                ld    (GB_TIME_BUF+2),a
                ret
kt_soft
                ld    a,(sw_hour)
                ld    (GB_TIME_BUF+0),a
                ld    a,(sw_min)
                ld    (GB_TIME_BUF+1),a
                ld    a,(sw_sec)
                ld    (GB_TIME_BUF+2),a
                ld    a,4                       ; nonzero -> already binary, no convert
                ld    (GB_TIME_BUF+3),a
                ret

; (fmt_mem migrated to the GBCFG C module: gb_fmt_mem in kernel/kc/kcfg.c. The
; kernel leaves the KB count in KCFG_MEMKB before cfg_boot; the module writes the
; "<decimal>K" string to KCFG_MEMSTR, which draw_topbar renders.)

; mem_detect: count present 64K expansion banks (port &7F00 value &C4+bank*8
; pages a bank's block 0 into #4000-#7FFF). MUST run resident and BEFORE
; PAGE_DATA is populated (it pokes every bank's #4000). Returns A = bank count.
mem_detect
                ld    hl,(#4000)
                ld    (md_save),hl
                ld    d,0
md_clear
                ld    e,0
                call  md_port
                ld    bc,#7F00
                out   (c),l
                xor   a
                ld    (#4000),a
                ld    (#4001),a
                inc   d
                ld    a,d
                cp    8
                jr    nz,md_clear
                ld    bc,#7FC0
                out   (c),c
                ld    a,#FF
                ld    (#4000),a
                ld    (#4001),a
                xor   a
                ld    (md_count),a
                ld    a,#FF
                ld    (md_last),a
                ld    (md_last+1),a
                ld    d,0
md_detect
                ld    e,0
                call  md_port
                ld    bc,#7F00
                out   (c),l
                call  md_valid
                jr    z,md_next
                ld    hl,md_count
                inc   (hl)
                call  md_update
md_next
                inc   d
                ld    a,d
                cp    8
                jr    nz,md_detect
                ld    bc,#7FC0
                out   (c),c
                ld    hl,(md_save)
                ld    (#4000),hl
                ld    a,(md_count)
                ret
md_port
                ld    a,d
                add   a,a
                add   a,a
                add   a,a
                or    #C4
                or    e
                ld    l,a
                ret
md_valid
                ld    a,(#4000)
                cp    #FF
                jr    z,md_invalid
                ld    e,a
                ld    a,(md_last)
                cp    e
                jr    z,md_invalid
                ld    a,(#4001)
                cp    #FF
                jr    z,md_invalid
                ld    e,a
                ld    a,(md_last+1)
                cp    e
                jr    z,md_invalid
                ld    a,1
                or    a
                ret
md_invalid
                xor   a
                ret
md_update
                ld    a,#FF
                ld    (#4000),a
                ld    (#4001),a
                ld    (md_last),a
                ld    (md_last+1),a
                ret

sw_sec          db    0            ; software clock (when no RTC); advanced by sw_tick,
sw_min          db    0            ; read by gb_time. The desktop draws/formats the bar.
sw_hour         db    0
clk_frames      db    0
have_rtc        db    0
md_save         dw    0
md_count        db    0
md_last         dw    0

                include "../lib/screen.asm"
                include "../lib/text.asm"
                include "../lib/cursor_arrow.asm"
                include "../lib/cursor.asm"
                include "../lib/input.asm"
                include "../lib/fs.asm"
                include "../lib/fs_ide_fat.asm"
                include "../lib/fs_amsdos.asm"
                include "../lib/bank.asm"
kern_end                                        ; GBKERN.BIN = #8000..kern_end only.

; --- STABILITY GUARD: the resident kernel must not eat the stack -----------------
; The CPC runs on the UniDOS stack, which grows DOWN from HIMEM (&A288) toward
; kern_end - the only stack space is the gap between them. If the kernel grows into
; the reserve the stack smashes the resident image on a deep call + interrupt (a
; silent crash). This assert turns that into a LOUD build failure so a too-big
; kernel is caught here, not in the field. (Reclaim, or move scratch out, to fix.)
HIMEM           equ   #A288        ; UniDOS HIMEM (stack top); see docs/AMSDOS notes
STACK_RESERVE   equ   256          ; min bytes kept free below HIMEM for the stack (#95)
                assert HIMEM-kern_end>=STACK_RESERVE,"GBKERN too big: <192B stack left under HIMEM - reclaim resident bytes"

; --- scratch buffers live in LOW RAM (always the main bank, below the stack) -----
; They used to sit just above kern_end, but as the kernel grew they landed in the
; UniDOS stack's path: HIMEM &A288 grows DOWN toward kern_end, so a 512-byte sector
; write during a deep call (a Notepad save) smashed the return stack and the IDE
; loop ran away. Low RAM #1800+ (the retired GBFAT transfer area) is clear of both
; the descending stack and the resident image. Fixed addresses, not loaded data.
fs_secbuf       equ   #1800            ; IDE sector buffer / aliased AMSDOS write sector
fsam_buf        equ   #1A00            ; floppy whole-directory buffer
                                                ; The packaging incbins below are
                                                ; never loaded at runtime, only read
                                                ; by `save`. The payload outgrew a
                                                ; single free region, so it is split:
                                                ; the modules/fonts/assets sit ABOVE
                                                ; the kernel, the (larger) app binaries
                                                ; in low memory at #0100 - both within
                                                ; the 64K image and clear of #8000..
                                                ; kern_end (GBKERN.BIN).
cfg_img         incbin "../build/GBCFG.RAW"     ; config-parser C module, as GBCFG.BIN
cfg_imgend
fat_img         incbin "../build/GBFAT.RAW"     ; FAT16/IDE write module, as GBFAT.BIN
fat_imgend
font_img        incbin "../build/DEFAULT.FNT"   ; packaged on the disk as DEFAULT.FNT
font_imgend
cfont_img       incbin "../build/CLASSIC.FNT"   ; alternate 8x8 font (FONT=CLASSIC)
cfont_imgend
icon_img        incbin "../build/DEFAULT.IST"   ; packaged on the disk as DEFAULT.IST
icon_imgend
                ; STABILITY GUARD: the icon set loads into PAGE_DATA at DATA_ICONS and
                ; must stay below GBFAT_LOAD (the FAT module shares PAGE_DATA) - else a
                ; save/delete/copy overwrites the end of the set (garbled icons, #88).
                assert icon_imgend-icon_img<=GBFAT_LOAD-DATA_ICONS-#200,"DEFAULT.IST too big: would collide with GBFAT in PAGE_DATA - fewer icons or raise GBFAT_LOAD"
wel_img         incbin "../assets/WELCOME.TXT"  ; a sample text file to open in VIEWER
wel_imgend
                include "../lib/cursor_data.asm" ; cur_spr_data..cur_spr_end -> DEFAULT.SPR
                include "../lib/cursor_hand_data.asm" ; cur_hand_data..end -> HAND.SPR
                                                ; ICONED + CHELLO ride in the ABOVE-kernel
                                                ; region too: the low #0100 app window
                                                ; (#0100..#7FFF, 32K) overflowed once the
                                                ; resizeable windows grew the apps, so the
                                                ; two least-coupled binaries moved up here.
ied_img         incbin "../build/ICONED.RAW"    ; packaged on the disk as ICONED.APP
ied_imgend
chl_img         incbin "../build/CHELLO.RAW"    ; C-app spike, packaged as CHELLO.APP
chl_imgend
                org   #0100                     ; --- app binaries, low region ---
dtp_img         incbin "../build/DESKTOP.RAW"   ; packaged on the disk as DESKTOP.APP
dtp_imgend
app_img         incbin "../build/FILEMGR.RAW"   ; packaged on the disk as FILEMGR.APP
app_imgend
vwr_img         incbin "../build/VIEWER.RAW"    ; packaged on the disk as VIEWER.APP
vwr_imgend
npd_img         incbin "../build/NOTEPAD.RAW"   ; packaged on the disk as NOTEPAD.APP
npd_imgend
clk_img         incbin "../build/CLOCK.RAW"     ; packaged on the disk as CLOCK.APP
clk_imgend
                save  "GBKERN.BIN",GB_KERNEL,kern_end-GB_KERNEL,DSK,"build/gbkern.dsk"
                save  "DESKTOP.APP",dtp_img,dtp_imgend-dtp_img,DSK,"build/gbkern.dsk"
                save  "FILEMGR.APP",app_img,app_imgend-app_img,DSK,"build/gbkern.dsk"
                save  "VIEWER.APP",vwr_img,vwr_imgend-vwr_img,DSK,"build/gbkern.dsk"
                save  "NOTEPAD.APP",npd_img,npd_imgend-npd_img,DSK,"build/gbkern.dsk"
                save  "ICONED.APP",ied_img,ied_imgend-ied_img,DSK,"build/gbkern.dsk"
                save  "CLOCK.APP",clk_img,clk_imgend-clk_img,DSK,"build/gbkern.dsk"
                save  "CHELLO.APP",chl_img,chl_imgend-chl_img,DSK,"build/gbkern.dsk"
                save  "GBCFG.BIN",cfg_img,cfg_imgend-cfg_img,DSK,"build/gbkern.dsk"
                save  "GBFAT.BIN",fat_img,fat_imgend-fat_img,DSK,"build/gbkern.dsk"
                save  "DEFAULT.FNT",font_img,font_imgend-font_img,DSK,"build/gbkern.dsk"
                save  "CLASSIC.FNT",cfont_img,cfont_imgend-cfont_img,DSK,"build/gbkern.dsk"
                save  "DEFAULT.IST",icon_img,icon_imgend-icon_img,DSK,"build/gbkern.dsk"
                save  "WELCOME.TXT",wel_img,wel_imgend-wel_img,DSK,"build/gbkern.dsk"
                save  "DEFAULT.SPR",cur_spr_data,cur_spr_end-cur_spr_data,DSK,"build/gbkern.dsk"
                save  "build/DEFAULT.SPR",cur_spr_data,cur_spr_end-cur_spr_data
                save  "HAND.SPR",cur_hand_data,cur_hand_end-cur_hand_data,DSK,"build/gbkern.dsk"
                save  "build/HAND.SPR",cur_hand_data,cur_hand_end-cur_hand_data
                save  "build/GBKERN.RAW",GB_KERNEL,kern_end-GB_KERNEL
