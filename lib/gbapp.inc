; ---------------------------------------------------------------------------
; lib/gbapp.inc - GEOBENCH app ABI (Phase 1/2 skeleton).
;
; Apps are separate binaries assembled at APP_BASE, loaded into an expansion
; bank and entered there. They reach kernel services by CALLing fixed addresses
; in the resident kernel region (GB_*), which stays mapped (#8000-#BFFF) while a
; bank is paged. An app returns to the desktop by RET, or by CALL GB_QUIT.
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

PAGE_DATA       equ   #C4          ; bank 0, block 0 -> kernel data buffers
PAGE_APP0       equ   #C5          ; bank 0, block 1 -> app slot 0 (desktop)
PAGE_APP1       equ   #C6          ; bank 0, block 2 -> app slot 1
PAGE_APP2       equ   #C7          ; bank 0, block 3 -> app slot 2
                                   ; apps nest desktop -> filemgr -> viewer; the
                                   ; launcher uses PAGE_APP0 + launch depth
DATA_BUF        equ   #4000        ; base of the kernel data buffers (in PAGE_DATA)
DATA_FONT       equ   DATA_BUF     ; font set lives at the start of PAGE_DATA
DATA_ICONS      equ   #4400        ; icon set (.IST) follows the font in PAGE_DATA

GB_KERNEL       equ   #8000        ; resident kernel base (fixed, RUN entry)
GB_INIT         equ   GB_KERNEL+0  ; #8000  kernel boot (kernel only)
GB_CLS          equ   GB_KERNEL+3  ; #8003  clear screen / home cursor
GB_PRINT        equ   GB_KERNEL+6  ; #8006  HL = 0-term string -> firmware text
GB_QUIT         equ   GB_KERNEL+9  ; #8009  app -> return to the desktop
GB_TEXT         equ   GB_KERNEL+12 ; #800C  6x8 font text: B=col C=line D=pen
                                   ;        E=paper HL=string (in the caller's page)
GB_WINDOW       equ   GB_KERNEL+15 ; #800F  draw a window: B=x C=y D=w E=h
                                   ;        HL=title (caller's page)
GB_DIR1         equ   GB_KERNEL+18 ; #8012  first dir entry -> CF set, HL=name
                                   ;        (resident, "NAME.EXT", 0-term); NC=empty
GB_DIRN         equ   GB_KERNEL+21 ; #8015  next dir entry  -> CF set, HL=name; NC=end
GB_BLITE        equ   GB_KERNEL+24 ; #8018  blit the current entry's type icon
                                   ;        (half height) at B=col C=line
GB_CURSHOW      equ   GB_KERNEL+27 ; #801B  draw the pointer (after drawing UI)
GB_POLL         equ   GB_KERNEL+30 ; #801E  frame-paced input poll -> B=cursor
                                   ;        byte col, C=cursor line, D bit0=click
                                   ;        edge, bit1=quit (ESC), bit2=fire held.
                                   ;        IRQs must be on.
GB_FRAME        equ   GB_KERNEL+33 ; #8021  rectangle outline: B=x C=y D=w E=h
                                   ;        A=pen (0..3)
GB_CURHIDE      equ   GB_KERNEL+36 ; #8024  lift the pointer (before drawing under
                                   ;        it; pair with GB_CURSHOW after)
GB_LAUNCH       equ   GB_KERNEL+39 ; #8027  launch the app for the current entry
                                   ;        (fs_ent_name) into PAGE_APP1, run it,
                                   ;        return when it quits
GB_GETARG       equ   GB_KERNEL+42 ; #802A  -> HL = launch arg (11-byte 8.3 name
                                   ;        of the file the app was opened with)
GB_RUN          equ   GB_KERNEL+45 ; #802D  run a named app: HL = 8.3 app name;
                                   ;        runs in the next bank page, returns on quit
GB_ICON         equ   GB_KERNEL+48 ; #8030  full icon blit: A=slot B=x C=y
GB_FILL         equ   GB_KERNEL+51 ; #8033  filled rect: B=x C=y D=w E=h A=pen
GB_SAVERECT     equ   GB_KERNEL+54 ; #8036  save a screen rect to a buffer:
                                   ;        B=x C=y D=w E=h HL=buf (w*h bytes)
GB_RESTORERECT  equ   GB_KERNEL+57 ; #8039  restore a screen rect from a buffer
GB_XORFRAME     equ   GB_KERNEL+60 ; #803C  XOR a 1px rect outline into the screen
                                   ;        (rubber-band): B=x C=y D=w E=h. Draw
                                   ;        once to show, again to erase exactly.
GB_FSLOAD       equ   GB_KERNEL+63 ; #803F  load the file this app was opened with
                                   ;        (the launch arg) into a buffer: HL=dst
                                   ;        (caller's page), DE=max bytes. -> BC =
                                   ;        byte count (0 = missing / too big), CF
                                   ;        set on success. AMSDOS header stripped.
