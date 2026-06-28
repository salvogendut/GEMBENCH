; kernel/assets.asm - font/icon/cursor/backdrop and boot splash assets.
;
; The resident kernel owns loading visual assets into PAGE_DATA or fixed low RAM,
; and exposes reload/backdrop services through GB_RELOAD and GB_BACKDROP.

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
                call  fs_load_sys             ; #134: fonts/icons/cursor live in /GEOBENCH
                pop   hl
                ret   c                         ; wanted file loaded
                ld    de,fs_req_name           ; missing -> use the default name
                call  copy11
                jp    fs_load_sys              ; (dst/max unchanged by the miss)

; icon_init: load <ICONS>.IST into PAGE_DATA at DATA_ICONS.
icon_init
                di
                ld    a,PAGE_DATA
                call  bank_set
                ld    hl,KCFG_ICONNAME       ; fs_req_name = the config icon name
                ld    de,fs_req_name
                call  copy11
                ld    hl,DATA_MODTOP-DATA_ICONS-#200 ; cap = the free icon region: from
                ld    (fs_load_max),hl               ; DATA_ICONS up to DATA_MODTOP (the write
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

; backdrop_init (#128): load the BACKDROP= tile (<name>.BDP, built by the GBCFG module
; into KCFG_BDPNAME) into BD_TILE so fill_pattern can tile it. BACKDROP=SOLID (the
; default) or a missing file leaves BD_SOLID=1 -> the plain pen-0 desktop (today's look).
backdrop_init
                ld    a,(BD_SOLID)           ; the GBCFG module set this (1 = solid / no tile)
                or    a
                ret   nz                       ; solid backdrop -> nothing to load
                ld    hl,KCFG_BDPNAME        ; fs_req_name = <name>.BDP
                ld    de,fs_req_name
                call  copy11
                ; #202: the floppy stores the tile with a 128-byte AMSDOS header (Rc=2 -> 256
                ; on-disk), and the AMSDOS reader grabs a whole 512-byte sector, so DON'T load
                ; straight into the 64-byte BD_TILE (it sits right below BD_SOLID + more state).
                ; Load into the 2KB fsam_buf dir scratch (already consumed by the entry scan;
                ; the reader strips the header so the tile lands at fsam_buf[0]), then copy the
                ; 64 tile bytes out. fs_load_max 512 clears the reader's Rc*128 > max guard.
                ld    hl,512
                ld    (fs_load_max),hl
                ld    hl,fsam_buf
                ld    (fs_load_dst),hl
                ld    a,(KCFG_BDDRIVE)
                inc   a
                jr    z,bdi_sys
                ld    a,(fs_cur_drive)
                push  af
                ld    a,(KCFG_BDDRIVE)
                call  fs_set_drive
                di
                call  fs_load_cur_sys
                ei
                ex    af,af'
                pop   af
                call  fs_set_drive
                ex    af,af'
                jr    bdi_loaded
bdi_sys         di
                call  fs_load_sys            ; from /GEOBENCH on the boot drive (#134)
                ei
bdi_loaded      jr    nc,bdi_solid           ; missing / refused -> solid fallback
                ld    hl,fsam_buf            ; copy the 64-byte tile into BD_TILE
                ld    de,BD_TILE
                ld    bc,64
                ldir
                ret                           ; loaded -> patterned (BD_SOLID stays 0)
bdi_solid       ld    a,1
                ld    (BD_SOLID),a           ; missing file -> solid fallback
                ret

; --- bootsplash (#196) ----------------------------------------------------
; A lollipop logo + a load progress bar shown during the boot's disk loads. The
; screen is already GEOBENCH-blue (pen 0) from SCR_SET_MODE + set_palette, so the
; lollipop's blue corners blit invisibly. The desktop's first repaint overwrites it.
SPL_X           equ   28           ; lollipop left byte col (centred: (80-24)/2)
SPL_Y           equ   12           ; lollipop top line
SPL_WB          equ   24           ; width in bytes (96 px)
SPL_H           equ   184          ; height in rows (logo + build id below the bar)
BAR_X           equ   16           ; progress bar left byte col
BAR_Y           equ   170          ; progress bar top line
BAR_WB          equ   48           ; full bar width in bytes (192 px)
BAR_H           equ   10           ; bar height in rows
BAR_SEG         equ   12           ; bytes per boot_tick; exactly 4 ticks fill BAR_WB
; boot_splash: load /GEOBENCH/SPLASH.BIN into PAGE_APP0 and blit it, then draw the
; empty (black) bar backing. Missing file -> skipped (CF clear). Called once from
; kernel_main, after set_palette and before assets_load.
boot_splash
                ld    a,(bank_cur)
                push  af
                di
                ld    hl,splash_name
                call  load_app0              ; -> APP_BASE in PAGE_APP0, CF = loaded
                jr    nc,bsp_done            ; no SPLASH.BIN -> plain blue boot
                ld    hl,spl_dims            ; sb_x,sb_y,sb_w,sb_h are consecutive (screen.asm)
                ld    de,sb_x
                ld    bc,4
                ldir
                ld    hl,APP_BASE
                ld    (sb_buf),hl
                call  restore_block          ; blit the lollipop to the screen
                ld    b,BAR_X                ; empty bar backing (pen-2 black) for contrast
                ld    c,BAR_Y
                ld    d,BAR_WB
                ld    e,BAR_H
                ld    a,#0F                  ; Mode-1 pen-2 (black) fill byte
                ld    (fb_val),a
                call  fill_xywh
bsp_done
                pop   af
                call  bank_set
                ei
                ret
splash_name     db    "SPLASH  MOD"          ; 8.3, space-padded
spl_dims        db    SPL_X,SPL_Y,SPL_WB,SPL_H

; boot_tick: advance the load bar by one red segment over the black backing, then hold
; for BOOT_HOLD frames. Called at each kernel_main load milestone (exactly 4 times, no
; clamp needed). The hold gives the splash a deliberate ~1.4 s minimum on fast storage
; (Albireo SD loads near-instantly); slow floppy adds its own load time on top. Writes
; screen RAM (#C000) only, so no bank management. bar_w starts 0 from its db (boot runs
; once per fresh kernel load, so no reset).
BOOT_HOLD       equ   18           ; frames held per segment (~0.36 s at 50 Hz)
boot_tick
                ld    a,(bar_w)
                add   a,BAR_SEG
                ld    (bar_w),a
                ld    b,BAR_X
                ld    c,BAR_Y
                ld    d,a
                ld    e,BAR_H
                ld    a,#FF                  ; Mode-1 pen-3 (red) fill byte
                ld    (fb_val),a
                call  fill_xywh
                ld    b,BOOT_HOLD
bt_hold
                push  bc
                call  MC_WAIT_FLYBACK        ; pace to 50 Hz (firmware RAM jumpblock)
                pop   bc
                djnz  bt_hold
                ret
bar_w           db    0

; assets_load: (re)load the font, icon set, cursor and backdrop tile from the names in
; the transfer area. Run at boot, and again by GB_RELOAD when the Settings app changes
; one of them (it writes the new name to the transfer area first) - so they apply with
; no reboot (#185).
assets_load
                call  font_init
                call  icon_init
                call  cursor_init
                jp    backdrop_init

; k_reload (GB_RELOAD #185): re-apply the assets at runtime, preserving the caller's
; page (the loaders page in PAGE_DATA). The Settings app populates the transfer area,
; calls this, then repaints. (Colours already apply live, so set_palette is not redone.)
k_reload
                ld    a,(bank_cur)
                push  af
                call  assets_load
                pop   af
                jp    bank_set

; k_backdrop (GB_BACKDROP): fill a rectangle with the desktop backdrop. B=x C=y D=w E=h.
; Solid (BD_SOLID) -> a plain pen-0 fill (== the old gb_fill(...,0)); else tile BD_TILE.
k_backdrop
                ld    a,b
                ld    (fb_x),a
                ld    a,c
                ld    (fb_y),a
                ld    a,d
                ld    (fb_w),a
                ld    a,e
                ld    (fb_h),a
                ld    a,(BD_SOLID)
                or    a
                jr    z,kb_pattern
                xor   a                        ; pen 0 byte = #00 (blue paper)
                ld    (fb_val),a
                jp    fill_block
kb_pattern
                jp    fill_pattern
