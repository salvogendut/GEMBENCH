; ---------------------------------------------------------------------------
; lib/gbapp.inc - GEOBENCH app ABI (Phase 1/2 skeleton).
;
; Apps are separate binaries assembled at APP_BASE, loaded into an expansion
; bank and entered there. They reach kernel services by CALLing fixed addresses
; in the resident kernel region (GB_*), which stays mapped (#8000-#BFFF) while a
; bank is paged. Windowed apps register with the WM and return from their entry;
; older modal apps return by RET. GB_QUIT is a reserved no-op stub.
;
; Memory model (see geobench-kernel-banking): the #4000-#7FFF window holds one
; 16K page at a time. We carve the first expansion bank (bank 0) into pages:
;   PAGE_DATA = kernel buffers (icon set, font, fs dir, ...)
;   PAGE_APP0 = the first application
; A kernel service that touches a banked buffer saves the caller's page
; (bank_cur), swaps to PAGE_DATA, works, then restores the caller's page.
; Params therefore pass in registers or a resident transfer buffer, never in
; the window (it gets swapped out under the service).
;
; The kernel region is a jump table at GB_KERNEL: each entry is a 3-byte `jp`,
; so the addresses below are stable as the kernel grows (keep the table order).
; ---------------------------------------------------------------------------

APP_BASE        equ   #4000        ; the #4000-#7FFF paging window
                ifdef PLATFORM_PCW
APP_LOAD_MAX    equ   #3F80        ; CP/M record-rounded Browser ends at #7F80
                else
APP_LOAD_MAX    equ   #3F00        ; keep CPC/MSX app loads below #7F00
                endif

; Screen extents (#287): byte columns / lines per platform - the asm-side
; counterpart of gb.h's GB_COLS/GB_LINES. CPC values keep the image identical.
                ifdef PLATFORM_MSX
SCR_COLS        equ   128          ; MSX2 Screen 6: 512px / 4 per byte
SCR_LINES       equ   212
                else
                ifdef PLATFORM_PCW
SCR_COLS        equ   90           ; PCW CGA2: 360px / 4 per byte (#331)
SCR_LINES       equ   248          ; 31 cellrows; scanlines 248-255 letterbox
                else
SCR_COLS        equ   80           ; CPC Mode 1: 320px / 4 per byte
SCR_LINES       equ   200
                endif
                endif

                ifdef PLATFORM_PCW
PAGE_DATA       equ   #8E          ; phys block 14 -> kernel data buffers (#331)
PAGE_APP0       equ   #86          ; phys block 6 -> the desktop (always APP_PAGES[0])
                else
                ifndef PLATFORM_MSX
PAGE_DATA       equ   #C4          ; bank 0, block 0 -> kernel data buffers
PAGE_APP0       equ   #C5          ; bank 0, block 1 -> the desktop (always APP_PAGES[0])
                endif
                endif
                                   ; Further app pages are no longer fixed constants: the
                                   ; kernel builds a pool (APP_PAGES) across every detected
                                   ; bank at boot - see app_pool_init / wm_alloc_page (#84).
; LD_A_PAGE_DATA: A = the PAGE_DATA page value. On the CPC that is the build-time
; gate-array constant; on the MSX2 target (#287) DOS 2 hands out mapper segments at
; runtime, so the allocated segment number is read from a page-3 glue cell
; (MSX_PAGE_DATA, lib/msx/glue.inc). Shared code (to_data, run_data_module, the
; asset loaders) uses this macro instead of `ld a,PAGE_DATA`.
                ifdef PLATFORM_MSX
                macro LD_A_PAGE_DATA
                ld    a,(MSX_PAGE_DATA)
                mend
                else
                macro LD_A_PAGE_DATA
                ld    a,PAGE_DATA
                mend
                endif

DATA_BUF        equ   #4000        ; base of the kernel data buffers (in PAGE_DATA)
DATA_FONT       equ   DATA_BUF     ; font set lives at the start of PAGE_DATA
DATA_ICONS      equ   #4400        ; icon set (.IST) follows the font in PAGE_DATA
DATA_TITLE      equ   #5E00        ; issue #458: canonical .TBR theme in PAGE_DATA
DATA_TITLE_CLOSE equ  DATA_TITLE+56 ; 8x10 close tile, two bytes per row
DATA_TITLE_MAX  equ   DATA_TITLE_CLOSE+20 ; 12x10 maximize tile, three bytes per row
DATA_TITLE_SIZE equ   106           ; repeated background + two reusable gadget tiles
DATA_TITLE_RUN  equ   DATA_TITLE+DATA_TITLE_SIZE ; CPC renderer follows the theme
DATA_MODTOP     equ   #6000        ; ceiling of the icon region in PAGE_DATA: the on-demand
                                   ; write module (GBFAT on IDE builds) loads here, so the icon
                                   ; set must stay below it. Build-independent (#104) - the IDE
                                   ; backend's GBFAT_LOAD aliases this; an Albireo write module
                                   ; would reuse the same slot.

GB_KERNEL       equ   #8000        ; resident kernel base (fixed, RUN entry)
GB_PARAMS       equ   GB_KERNEL+213 ; #80D5 ABI 2.1: HL=16-byte record, BC=16 -> A=status E=value
GB_INIT         equ   GB_KERNEL+0  ; #8000  kernel boot (kernel only)
GB_CLS          equ   GB_KERNEL+3  ; #8003  clear screen / home cursor
GB_SETINK       equ   GB_KERNEL+6  ; #8006  set a palette colour live: A=pen (0-3, or
                                   ;        4=border), B/C=CPC ink number. CPC -> SCR_SET_INK/
                                   ;        BORDER; MSX -> V9938 palette (#287, was GB_PRINT)
GB_LINE         equ   GB_KERNEL+9  ; #8009  draw a line (MSX: V9938 LINE command from the
                                   ;        GLINE_* glue cells; inert on CPC - CLOCK uses
                                   ;        GRA_* firmware there). #287 (was GB_QUIT)
GB_TEXT         equ   GB_KERNEL+12 ; #800C  6x8 font text: B=col C=line D=pen
                                   ;        E=paper HL=string (in the caller's page)
GB_WINDOW       equ   GB_KERNEL+15 ; #800F  draw a window: B=x C=y D=w E=h
                                   ;        HL=title (caller's page)
GB_DIR1         equ   GB_KERNEL+18 ; #8012  first dir entry -> CF set, HL=name
                                   ;        (resident, "NAME.EXT", 0-term); NC=empty
GB_DIRN         equ   GB_KERNEL+21 ; #8015  next dir entry  -> CF set, HL=name; NC=end
GB_BLITE        equ   GB_KERNEL+24 ; #8018  reserved legacy current-entry icon
                                   ;        slot; currently a vsync-compatible stub
GB_CURSHOW      equ   GB_KERNEL+27 ; #801B  draw the pointer (after drawing UI)
GB_POLL         equ   GB_KERNEL+30 ; #801E  frame-paced input poll -> B=cursor
                                   ;        byte col, C=cursor line, D bit0=click
                                   ;        edge, bit1=quit (ESC), bit2=fire held.
                                   ;        IRQs must be on.
GB_FRAME        equ   GB_KERNEL+33 ; #8021  rectangle outline: B=x C=y D=w E=h
                                   ;        A=pen (0..3)
GB_CURHIDE      equ   GB_KERNEL+36 ; #8024  lift the pointer (before drawing under
                                   ;        it; pair with GB_CURSHOW after)
GB_REPAINTTOP   equ   GB_KERNEL+39 ; #8027  repaint only the opaque z-top; retired
                                   ;        modal GB_LAUNCH slot reused (#477)
GB_LAUNCH       equ   GB_REPAINTTOP ; legacy source alias; no longer launches
GB_GETARG       equ   GB_KERNEL+42 ; #802A  -> HL = launch arg (11-byte 8.3 name
                                   ;        of the file the app was opened with)
GB_RUN          equ   GB_KERNEL+45 ; #802D  reserved legacy modal-run slot.
                                   ;        PCW/MSX reuse it to set the software
                                   ;        clock: B=hour C=min D=sec.
GB_ICON         equ   GB_KERNEL+48 ; #8030  full icon blit: A=slot B=x C=y
GB_FILL         equ   GB_KERNEL+51 ; #8033  filled rect: B=x C=y D=w E=h A=pen
GB_SAVERECT     equ   GB_KERNEL+54 ; #8036  save a screen rect to a buffer:
                                   ;        B=x C=y D=w E=h HL=buf (w*h bytes)
GB_RESTORERECT  equ   GB_KERNEL+57 ; #8039  restore a screen rect from a buffer
GB_PICOPEN      equ   GB_KERNEL+60 ; #803C  load opened .PIC into borrowed app bank.
                                   ;        A=bank/page on success, A=0 fallback.
                                   ;        This reuses the old GB_XORFRAME slot.
GB_FSLOAD       equ   GB_KERNEL+63 ; #803F  load the file this app was opened with
                                   ;        (the launch arg) into a buffer: HL=dst
                                   ;        (caller's page), DE=max bytes. -> BC =
                                   ;        byte count (0 = missing / too big), CF
                                   ;        set on success. AMSDOS header stripped.
GB_FSSAVE       equ   GB_KERNEL+66 ; #8042  save the file this app was opened with:
                                   ;        HL=src (caller's page), DE=byte count.
                                   ;        Overwrites in place (the file must exist
                                   ;        and the data must fit its current
                                   ;        allocation). CF set = saved.
GB_GETKEY       equ   GB_KERNEL+69 ; #8045  -> A = a typed character from the
                                   ;        keyboard buffer, or 0 if none waiting.
                                   ;        Non-blocking; IRQs must be on.
GB_PICEDIT      equ   GB_KERNEL+72 ; #8048  banked .PIC tile edit/save service (#288;
                                   ;        retired GB_VSYNC slot). A=0 get 100x100
                                   ;        tile into PIC_EDIT_BUF, A=1 put tile back,
                                   ;        A=2 copy fs_save_len bytes to PIC_EDIT_BUF,
                                   ;        A=3 write a short chunk to bank 1, A=4
                                   ;        canonical Mode-1 -> native display bytes.
                                   ;        -> A=1 success, A=0 unsupported/failure.
GB_ONEVENT      equ   GB_KERNEL+75 ; #804B  register an event handler: HL = address
                                   ;        of a void(void) function in the app, 0 to
                                   ;        clear. The kernel CALLs it during GB_POLL
                                   ;        when a top-bar click occurs, with a typed
                                   ;        message at GB_MSG (#1302): type, p0, p1,
                                   ;        p2. type GB_MSG_MENU(1) -> p0 = byte col.
                                   ;        Handler must return promptly (no GB_POLL).
GB_TASKENABLE   equ   GB_ONEVENT   ; #477 preemptive builds: opt the calling legacy
                                   ;        window into task service after GB_WMADD.
GB_MENU         equ   GB_KERNEL+78 ; #804E  register the top-bar menu: HL = blob
                                   ;        (count, then {col, 8-byte label} per
                                   ;        title) in the caller page. Kernel copies
                                   ;        it resident and draws the titles in the
                                   ;        bar. Cleared for a child app / on quit.
GB_SETNAME      equ   GB_KERNEL+81 ; #8051  set the current file name (launch arg):
                                   ;        HL = 11-byte 8.3 name. For New / Save As /
                                   ;        opening a picked file.
GB_PICBLIT      equ   GB_KERNEL+84 ; #8054  blit from the borrowed picture bank:
                                   ;        B=x C=y D=wbytes E=h HL=source offset.
                                   ;        This reuses the old GB_ONREPAINT slot.
GB_RESTPAR      equ   GB_KERNEL+87 ; #8057  repaint every ancestor app bottom-up
                                   ;        so a moved/closed window's area shows
                                   ;        what was under it. Restores the caller's
                                   ;        page; caller redraws on top.
GB_WMRUN        equ   GB_KERNEL+90 ; #805A  window-manager master loop (#45): HL = a
                                   ;        descriptor { u8 x,y,w,h; on_frame(2);
                                   ;        on_repaint(2) } in the app page. Registers
                                   ;        the window (page = caller), takes focus,
                                   ;        then loops: poll, CALL the focused
                                   ;        window's on_frame. Does not return.
                                   ;        on_frame reads gb_flags/gb_mx/gb_my; the
                                   ;        poll result is published at POLL_MX #1306
                                   ;        / POLL_MY #1307 / POLL_FLAGS #1308.
GB_WMADD        equ   GB_KERNEL+93 ; #805D  register a co-resident window: HL =
                                   ;        descriptor in the caller page; returns
                                   ;        to the opener after registration.
GB_WMOPEN       equ   GB_KERNEL+96 ; #8060  open an app as a co-resident window:
                                   ;        HL = 8.3 app name in caller page.
GB_WMCLOSE      equ   GB_KERNEL+99 ; #8063  close/free the focused calling window.
GB_WMSETPOS     equ   GB_KERNEL+102 ; #8066  move focused window hit rect:
                                    ;         A=x, L=y.
GB_PICCLOSE     equ   GB_KERNEL+105 ; #8069  release borrowed picture bank.
                                    ;         This reuses the old GB_WMLAUNCH slot.
GB_ISDIR        equ   GB_KERNEL+108 ; #806C  A=1 if current dir entry is a folder.
GB_CHDIR        equ   GB_KERNEL+111 ; #806F  descend into current dir entry.
GB_BACK         equ   GB_KERNEL+114 ; #8072  go to parent directory.
GB_ENTNAME      equ   GB_KERNEL+117 ; #8075  HL = current raw 11-byte 8.3 name.
GB_DRAGSTART    equ   GB_KERNEL+120 ; #8078  HL=name11; drag item until release,
                                    ;         A=1 if dropped on another window.
GB_FSDELETE     equ   GB_KERNEL+123 ; #807B  HL=name11; CF set if deleted.
GB_DRIVES       equ   GB_KERNEL+126 ; #807E  A = available-drive bitmask.
GB_SETDRIVE     equ   GB_KERNEL+129 ; #8081  A = active drive.
GB_GETDRIVE     equ   GB_KERNEL+132 ; #8084  A = active drive.
GB_COPYBEGIN    equ   GB_KERNEL+135 ; #8087  switch to drag source drive/context.
GB_WMLAUNCHAS   equ   GB_KERNEL+138 ; #808A  HL = app 8.3 name; launch it with
                                    ;         current dir entry as file arg.
GB_TIME         equ   GB_KERNEL+141 ; #808D  refresh GB_TIME_BUF (#1240).
GB_EXIT         equ   GB_KERNEL+144 ; #8090  leave GEOBENCH and return to AMSDOS.
GB_COPYEND      equ   GB_KERNEL+147 ; #8093  restore target drive/context.
GB_ONBAR        equ   GB_KERNEL+150 ; #8096  HL = desktop top-bar draw handler.
GB_WMSETSIZE    equ   GB_KERNEL+153 ; #8099  resize focused window hit rect:
                                    ;         A=w, L=h.
GB_FSFREE       equ   GB_KERNEL+156 ; #809C  HL = free KiB; CF set if known.
GB_ICONHALF     equ   GB_KERNEL+159 ; #809F  half-height icon blit:
                                    ;         A=slot B=x C=y.
GB_MXP          equ   GB_KERNEL+162 ; #80A2  HL = pointer pixel x (0..319).
GB_CLIPSET      equ   GB_KERNEL+165 ; #80A5  HL=src, DE=len; copy to clipboard.
GB_CLIPGET      equ   GB_KERNEL+168 ; #80A8  HL=dst, DE=max; BC=copied bytes.
GB_CLIPLEN      equ   GB_KERNEL+171 ; #80AB  BC = clipboard length.
GB_UI           equ   GB_KERNEL+174 ; #80AE  run paged dialog module; BC=UI_RES.
GB_WMMANAGED    equ   GB_KERNEL+177 ; #80B1  register kernel-managed window.
GB_WMDAMAGE     equ   GB_KERNEL+180 ; #80B4  set repaint damage rect.
GB_BACKDROP     equ   GB_KERNEL+183 ; #80B7  fill rect with desktop backdrop.
GB_RELOAD       equ   GB_KERNEL+186 ; #80BA  reload font/icons/cursor/backdrop.
GB_NET          equ   GB_KERNEL+189 ; #80BD  run active paged network module; BC=GBNET_RES.
                ifdef PLATFORM_MSX
GB_SHELL        equ   GB_KERNEL+192 ; #80C0  GEMBENCH shell register/find/send service.
GB_SYSINFO      equ   GB_KERNEL+195 ; #80C3  MSX2 versioned runtime capabilities (#31/#32/#35).
GB_OWNER        equ   GB_KERNEL+198 ; #80C6  current generation-tagged owner handle.
GB_PAGE         equ   GB_KERNEL+201 ; #80C9  opaque 16 KiB page allocate/free/check.
GB_APP          equ   GB_KERNEL+204 ; #80CC  MSX2 application/window lifecycle (#32).
GB_DEFER        equ   GB_KERNEL+207 ; #80CF  MSX2 bounded deferred application messages (#35).
GB_FSCTX        equ   GB_KERNEL+210 ; #80D2  MSX2 explicit filesystem contexts (#37).
                endif
