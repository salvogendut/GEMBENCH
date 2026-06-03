; desktop - the GEOBENCH desktop, now a banked app (the kernel boots it into
; PAGE_APP0). Draws the backdrop, a help line and the drive/clock/trash icons,
; runs the pointer, and on a double-click of the Disk icon launches the file
; manager (GB_RUN "FILEMGR") in the next bank page; when it quits, redraw.
;
; (First migration cut: Disk + Clock + Trash, no top-bar clock/RAM or drag yet.)

                include "../../lib/gbapp.inc"

DCLICK          equ   40

FLOPPY_X        equ   8            ; icon boxes (full 32x32 icons = 8 bytes x 32)
FLOPPY_Y        equ   24
CLOCK_X         equ   60
CLOCK_Y         equ   24
TRASH_X         equ   60
TRASH_Y         equ   150

                org   APP_BASE
dt_entry
dt_redraw
                ld    b,0                     ; backdrop (whole screen, pen 0)
                ld    c,0
                ld    d,80
                ld    e,200
                xor   a
                call  GB_FILL

                ld    b,1                     ; help line
                ld    c,4
                ld    d,1
                ld    e,0
                ld    hl,help_msg
                call  GB_TEXT

                ld    a,0                     ; Disk icon (slot 0 = floppy)
                ld    b,FLOPPY_X
                ld    c,FLOPPY_Y
                call  GB_ICON
                ld    b,FLOPPY_X
                ld    c,FLOPPY_Y+34
                ld    d,1
                ld    e,0
                ld    hl,lbl_disk
                call  GB_TEXT

                ld    a,2                     ; Clock icon (slot 2)
                ld    b,CLOCK_X
                ld    c,CLOCK_Y
                call  GB_ICON
                ld    b,CLOCK_X
                ld    c,CLOCK_Y+34
                ld    d,1
                ld    e,0
                ld    hl,lbl_clock
                call  GB_TEXT

                ld    a,3                     ; Trash icon (slot 3)
                ld    b,TRASH_X
                ld    c,TRASH_Y
                call  GB_ICON
                ld    b,TRASH_X
                ld    c,TRASH_Y+34
                ld    d,1
                ld    e,0
                ld    hl,lbl_trash
                call  GB_TEXT

                call  GB_CURSHOW
                xor   a
                ld    (dc_timer),a
dt_loop
                call  GB_POLL                ; B=col, C=line, D=flags
                ld    a,(dc_timer)
                or    a
                jr    z,dt_flags
                dec   a
                ld    (dc_timer),a
dt_flags
                bit   1,d                     ; ESC -> quit to BASIC
                jp    nz,dt_done
                bit   0,d                     ; click?
                jr    z,dt_loop

                ld    a,b                     ; Disk icon box hit?
                cp    FLOPPY_X
                jr    c,dt_loop
                cp    FLOPPY_X+8
                jr    nc,dt_loop
                ld    a,c
                cp    FLOPPY_Y
                jr    c,dt_loop
                cp    FLOPPY_Y+32
                jr    nc,dt_loop

                ld    a,(dc_timer)           ; double-click -> open the file manager
                or    a
                jr    z,dt_setdc
                ld    hl,name_filemgr
                call  GB_RUN
                jp    dt_redraw              ; redraw the desktop on return
dt_setdc
                ld    a,DCLICK
                ld    (dc_timer),a
                jr    dt_loop
dt_done
                ret                            ; back to the kernel (-> BASIC)

help_msg        db    "GEOBENCH - double-click Disk",0
lbl_disk        db    "Disk A",0
lbl_clock       db    "Clock",0
lbl_trash       db    "Trash",0
name_filemgr    db    "FILEMGR BIN"
dc_timer        db    0
dt_end
                save  "build/DESKTOP.RAW",APP_BASE,dt_end-APP_BASE
