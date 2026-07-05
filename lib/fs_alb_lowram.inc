; ---------------------------------------------------------------------------
; lib/fs_alb_lowram.inc - fixed low-RAM addresses shared by the resident kernel and
; the Albireo GEOBENCH.ROM (#152). The CH376 I/O backend runs from the read-only ROM,
; so its persistent path state + per-call save args must live in low RAM that both
; sides agree on. The entry/name/load I/O fields reuse the FSAM transfer area
; (lib/fs_rom_lowram.inc, #1270). Included whenever FS_ALB_LOWRAM is set: by gbkern
; (resident, for the stubs + fsalb_chdir/back/sysdir which edit alb_path) and by
; rom/geobench_rom.asm (the ROM, for the real CH376 code).
;
; Free gap used: #1293-#12FF - above the FSAM transfer area (ends #1292) and below the
; config text buffer (#1300). alb_path is PERSISTENT here (the current dir survives
; between ROM calls); nothing else touches this block, so a floppy listing can't clobber
; it (contrast the IDE's #1C00 state, which overlaps fsam_buf but self-heals on re-mount).
; ---------------------------------------------------------------------------

alb_path        equ   #1293        ; CH376 current dir, NUL-terminated, 64 bytes ("" = root)
fsalb_mounted   equ   #12D3        ; 1 once SET_USB_MODE + DISK_MOUNT has run (set by the ROM)
ALB_IO_SRC      equ   #12D4        ; save: source pointer in the caller's app page (2)
ALB_IO_SLEN     equ   #12D6        ; save: byte count (2)  -> ends #12D7, gap free to #12FF
alb_sysflag     equ   #12D8        ; nonzero while system loads use /GBENCH instead of alb_path
