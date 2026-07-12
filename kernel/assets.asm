; kernel/assets.asm - font/icon/cursor/backdrop and boot splash assets.
;
; The resident kernel owns loading visual assets into PAGE_DATA or fixed low RAM,
; and exposes reload/backdrop services through GB_RELOAD and GB_BACKDROP.

; --- font in PAGE_DATA ----------------------------------------------------
; font_init: page PAGE_DATA in, load <FONT>.FNT into it, cache the geometry.
; The 8.3 filename was built by the GBCFG module (KCFG_FONTNAME); just copy it.
font_init
                di
                LD_A_PAGE_DATA
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
                LD_A_PAGE_DATA
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
                ifdef PIC_RUNTIME_CONVERT      ; icon packs use canonical CPC Mode-1 bytes;
                call  c,icon_convert          ; keep the .IST payload unified across targets
                endif
                call  bank_normal
                ei
                ret

; icon_convert: transcode a loaded .IST in-place from canonical CPC Mode-1 icon
; bytes to the current platform's runtime encoding. The file format itself is
; unchanged (magic/version/directory); only the icon bitmap payload bytes are
; rewritten at DATA_ICONS+offset. CPC keeps the source as-is.
                ifdef PIC_RUNTIME_CONVERT
icon_convert
                ld    hl,DATA_ICONS
                ld    a,(hl)
                cp    'G'
                ret   nz
                inc   hl
                ld    a,(hl)
                cp    'B'
                ret   nz
                inc   hl
                ld    a,(hl)
                cp    'I'
                ret   nz
                inc   hl
                ld    a,(hl)
                cp    'S'
                ret   nz
                ld    hl,DATA_ICONS+4
                ld    a,(hl)
                cp    2
                ret   nz
                ld    a,(DATA_ICONS+5)
                or    a
                ret   z
                ld    l,a                    ; payload starts after the 16-byte header
                ld    h,0                    ; and count four-byte directory entries
                add   hl,hl
                add   hl,hl
                ld    de,16
                add   hl,de                  ; HL = payload offset
                ld    de,(fs_ent_size)
                ex    de,hl                  ; HL = loaded size, DE = payload offset
                or    a
                sbc   hl,de                  ; HL = bounded payload length
                ret   c                      ; truncated directory
                ld    a,h
                or    l
                ret   z
                push  hl
                ld    hl,DATA_ICONS
                add   hl,de                  ; HL = first canonical bitmap byte
                pop   de                     ; DE = bytes left

; mode1_convert: transcode DE non-zero canonical Mode-1 bytes in-place at HL
; to the target's runtime UI-bitmap encoding. MSX uses Screen-6 pen space. PCW
; UI bitmaps use that same pen space and are permuted only when drawn.
mode1_convert
                ld    a,(hl)
                ld    (mode1_conv_lut+1),a
mode1_conv_lut
                ld    a,(pic_m1_to_native)    ; canonical Mode-1 -> native display byte
                ifdef PLATFORM_PCW
                ; PCW picture bytes include the final CGA2 pen permutation. UI
                ; bitmaps stay in GB pen space, so undo that final step here.
                ld    c,a
                and   #AA
                rrca
                ld    b,a
                ld    a,c
                cpl
                and   #55
                add   a,a
                or    b
                endif
                ld    (hl),a
                inc   hl
                dec   de
                ld    a,d
                or    e
                jr    nz,mode1_convert
                ret
                endif


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
                ifdef PLATFORM_MSX            ; #287: (re)upload the loaded sprite to VDP
                jr    nc,ci_blank             ; pattern/colour VRAM (lib/msx/cursor.asm)
                jp    cursor_apply
ci_blank
                else
                ret   c
                endif
                ld    hl,CUR_LOW             ; missing -> blank the sprite buffer
                ld    de,CUR_LOW+1
                ld    bc,255
                ld    (hl),0
                ldir
                ifdef PLATFORM_MSX
                jp    cursor_apply            ; blank pattern = invisible pointer, never garbage
                else
                ret
                endif
def_spr         db    "DEFAULT SPR"

; backdrop_init (#128): load the BACKDROP= tile (<name>.BDP, built by the GBCFG module
; into KCFG_BDPNAME) into BD_TILE so fill_pattern can tile it. BACKDROP=SOLID (the
; default) or a missing file leaves BD_SOLID=1 -> the plain pen-0 desktop (today's look).
backdrop_init
                if BACKDROP_TILE
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
bdi_try
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
                ifdef PIC_RUNTIME_CONVERT
                ld    hl,fsam_buf            ; on-disk BDP is canonical Mode-1
                ld    de,64                   ; convert once into native UI pen space
                call  mode1_convert
                endif
                ld    hl,fsam_buf            ; copy the 64-byte tile into BD_TILE
                ld    de,BD_TILE
                ld    bc,64
                ldir
                ret                           ; loaded -> patterned (BD_SOLID stays 0)
bdi_solid       ld    a,1
                ld    (BD_SOLID),a           ; missing file -> solid fallback
                ret
                else
                ret
                endif

; --- bootsplash (#196) ----------------------------------------------------
; A lollipop logo + a load progress bar shown during the boot's disk loads. The
; screen is already GEOBENCH-blue (pen 0) from SCR_SET_MODE + set_palette, so the
; lollipop's blue corners blit invisibly. The desktop's first repaint overwrites it.
                ifndef PLATFORM_MSX           ; (#287: the MSX boot skips the splash for now -
                ifndef PLATFORM_PCW           ;  SPLASH.MOD is Mode-1 art + CPC frame pacing)
SPL_X           equ   28           ; lollipop left byte col (centred: (80-24)/2)
SPL_Y           equ   12           ; lollipop top line
SPL_WB          equ   24           ; width in bytes (96 px)
SPL_H           equ   184          ; height in rows (logo + label below the bar)
BAR_X           equ   16           ; progress bar left byte col
BAR_Y           equ   170          ; progress bar top line
BAR_WB          equ   48           ; full bar width in bytes (192 px)
BAR_H           equ   10           ; bar height in rows
BAR_SEG         equ   12           ; bytes per boot_tick; exactly 4 ticks fill BAR_WB
; boot_splash: load the splash bitmap selected by GBCFG.MOD (fs_req_name holds
; SPLASH.MOD or DEBUG=TRUE's SPLASHD.MOD), blit it, then draw the empty black bar
; backing. Missing file -> skipped (CF clear). Called once from kernel_main, after
; set_palette and before assets_load.
boot_splash
                ld    a,(bank_cur)
                push  af
                di
                ld    hl,fs_req_name
                call  load_app0              ; -> APP_BASE in PAGE_APP0, CF = loaded
                jr    nc,bsp_done            ; no splash bitmap -> plain blue boot
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
                endif                          ; (ifndef PLATFORM_PCW around the bootsplash)
                endif                          ; (ifndef PLATFORM_MSX around the bootsplash)

; --- bootsplash, PCW (#331) -------------------------------------------------
; The MSX splash flow on the PCW driver: SPLASH.MOD is Screen-6-packed art
; that build_kernel_pcw.sh pre-permutes to CGA2 hardware space (restore_block
; writes raw bytes). Pacing = the frame flyback.
                ifdef PLATFORM_PCW
SPL_X           equ   33           ; lollipop left byte col (centred: (90-24)/2)
SPL_Y           equ   12
SPL_WB          equ   24           ; 96 px
SPL_H           equ   184
BAR_X           equ   21           ; load bar left byte col (centred: (90-48)/2)
BAR_Y           equ   170
BAR_WB          equ   48           ; 192 px full bar
BAR_H           equ   10
BAR_SEG         equ   12           ; 4 ticks fill BAR_WB
BOOT_HOLD       equ   18           ; frames held per tick (~0.36 s at 50 Hz)
boot_splash
                ld    a,(bank_cur)
                push  af
                di
                ld    hl,fs_req_name
                call  load_app0              ; selected splash -> APP_BASE, CF = loaded
                jr    nc,bsp_done            ; missing -> plain boot
                ld    a,SPL_X
                ld    (sb_x),a
                ld    a,SPL_Y
                ld    (sb_y),a
                ld    a,SPL_WB
                ld    (sb_w),a
                ld    a,SPL_H
                ld    (sb_h),a
                ld    hl,APP_BASE
                ld    (sb_buf),hl
                call  restore_block          ; blit the lollipop
                ld    b,BAR_WB               ; empty bar backing, pen 2 (black)
                ld    a,2
                call  bsp_bar
bsp_done
                pop   af
                call  bank_set
                ret

; bsp_bar: A = pen, B = width in bytes -> fill (BAR_X, BAR_Y, B, BAR_H).
bsp_bar
                push  bc
                call  pen_to_byte
                ld    (fb_val),a
                pop   bc
                ld    a,BAR_X
                ld    (fb_x),a
                ld    a,BAR_Y
                ld    (fb_y),a
                ld    a,b
                ld    (fb_w),a
                ld    a,BAR_H
                ld    (fb_h),a
                jp    fill_block

; boot_tick: advance the load bar one red segment, then hold BOOT_HOLD frames.
boot_tick
                ld    a,(bar_w)
                add   a,BAR_SEG
                ld    (bar_w),a
                ld    b,a
                call  bsp_bar_check           ; magenta/black checker over the backing
                ld    b,BOOT_HOLD
bt_hold
                push  bc
                call  pcw_wait_frame
                pop   bc
                djnz  bt_hold
                ret

; bsp_bar_check: B = width in bytes -> checker-fill (BAR_X, BAR_Y, B, BAR_H).
; Raw PCW hardware bytes: #AA = pen 3 (magenta), #00 = pen 2 (black).
bsp_bar_check
                ld    a,b
                or    a
                ret   z
                ld    (bsp_ck_w),a
                ld    a,BAR_Y
                ld    (bsp_ck_y),a
                ld    a,BAR_H
                ld    (bsp_ck_rows),a
bbck_row
                ld    a,BAR_X
                ld    d,a
                ld    a,(bsp_ck_y)
                ld    e,a
                call  pcw_addr
                ld    a,(bsp_ck_w)
                ld    b,a
                ld    a,(bsp_ck_y)            ; two scanlines per checker row
                and   2
                ld    c,#00
                jr    z,bbck_have
                ld    c,#AA
bbck_have
                ld    de,8                    ; x-neighbours are 8 bytes apart
bbck_col
                ld    (hl),c
                ld    a,c
                xor   #AA
                ld    c,a
                add   hl,de
                djnz  bbck_col
                ld    a,(bsp_ck_y)
                inc   a
                ld    (bsp_ck_y),a
                ld    a,(bsp_ck_rows)
                dec   a
                ld    (bsp_ck_rows),a
                jr    nz,bbck_row
                ret

bar_w           db    0
bsp_ck_w        db    0
bsp_ck_y        db    0
bsp_ck_rows     db    0
                endif                          ; (ifdef PLATFORM_PCW bootsplash)

; --- bootsplash, MSX2 (#287) ----------------------------------------------
; The MSX counterpart of the CPC bootsplash: the same lollipop + label
; (SPLASH*.MOD, now Screen-6 art) blitted centred, plus a 4-tick load bar. The
; screen is already pen-0 blue (msx_video_init + set_palette); the desktop's
; first repaint clears it. Uses the shared VRAM primitives restore_block /
; fill_block / pen_to_byte and the retrace-paced wait msx_wait_tick, so no CPC
; #C000 screen or firmware pacing is involved.
                ifdef PLATFORM_MSX
SPL_X           equ   52           ; lollipop left byte col (centred: (128-24)/2)
SPL_Y           equ   12
SPL_WB          equ   24           ; 96 px
SPL_H           equ   184
BAR_X           equ   40           ; load bar left byte col (centred: (128-48)/2)
BAR_Y           equ   170
BAR_WB          equ   48           ; 192 px full bar
BAR_H           equ   10
BAR_SEG         equ   12           ; 4 ticks fill BAR_WB
BOOT_HOLD       equ   18           ; frames held per tick (~0.36 s at 50 Hz)
; boot_splash: load the splash bitmap selected by GBCFG.MOD to APP_BASE, blit it,
; draw the black bar backing.
; Caller-of-load_app0 rule: save/restore the page + DI/EI here (like run_cfgmod).
boot_splash
                ld    a,(bank_cur)
                push  af
                di
                ld    hl,fs_req_name
                call  load_app0              ; selected splash -> APP_BASE, CF = loaded
                jr    nc,bsp_done            ; missing -> plain blue boot
                ld    a,SPL_X
                ld    (sb_x),a
                ld    a,SPL_Y
                ld    (sb_y),a
                ld    a,SPL_WB
                ld    (sb_w),a
                ld    a,SPL_H
                ld    (sb_h),a
                ld    hl,APP_BASE
                ld    (sb_buf),hl
                call  restore_block          ; blit the lollipop to VRAM
                ld    b,BAR_WB               ; empty bar backing, pen 2 (black)
                ld    a,2
                call  bsp_bar
bsp_done
                pop   af
                call  bank_set
                ei
                ret

; bsp_bar: A = pen, B = width in bytes -> fill (BAR_X, BAR_Y, B, BAR_H) via fill_block.
bsp_bar
                push  bc
                call  pen_to_byte            ; A = pen -> Screen-6 fill byte
                ld    (fb_val),a
                pop   bc
                ld    a,BAR_X
                ld    (fb_x),a
                ld    a,BAR_Y
                ld    (fb_y),a
                ld    a,b
                ld    (fb_w),a
                ld    a,BAR_H
                ld    (fb_h),a
                jp    fill_block

; boot_tick: advance the load bar one red segment, then hold BOOT_HOLD frames.
boot_tick
                ld    a,(bar_w)
                add   a,BAR_SEG
                ld    (bar_w),a
                ld    b,a
                ld    a,3                     ; pen 3 (red)
                call  bsp_bar
                ld    b,BOOT_HOLD
bt_hold
                push  bc
                call  msx_wait_tick          ; pace to one true video frame (S#2 VR)
                pop   bc
                djnz  bt_hold
                ret
bar_w           db    0
                endif                          ; (ifdef PLATFORM_MSX bootsplash)

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
                if BACKDROP_TILE
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
                xor   a                        ; pen 0 (blue paper) - through
                call  pen_to_byte              ; pen_to_byte: the PCW's CGA2 pen 0
                ld    (fb_val),a               ; byte is #55, not #00 (#331)
                jp    fill_block
kb_pattern
                jp    fill_pattern
                else
                xor   a
                jp    k_fill
                endif
