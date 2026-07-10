;; pack_comp1.asm - COMPANION floppy, pass 1 of 3 (#250).
;;
;; The GEOBENCH floppy distribution is split into two 3" disks: the Main floppy
;; (build/gbkern.dsk -> QA/GEOBENCH.DSK, bootable, OS + core apps) and this Companion
;; DATA floppy (build/companion.dsk -> QA/COMPANION.DSK, no kernel) carrying the
;; extras: Paint, Telnet, Xaos, the screensavers, and the gallery pictures. The
;; Companion is meant for drive B (Main stays in A); the kernel app/module loader now
;; tries the boot drive (A) first, then falls back to the browse drive (B), so a
;; Companion app loads from B while its shared deps (GBUI.MOD/GBNET.MOD/PAINT.IST,
;; which stay only on Main) load from A - NO duplicates are needed here (lib/fs.asm
;; fs_load_sys, #250).
;;
;; Like pack_apps*.asm: each pass is a fresh 64K rasm image whose `save ...,DSK,...`
;; APPENDS to the same .dsk; pass 1 here CREATES build/companion.dsk (build_kernel.sh
;; `rm -f`s it first). The org is irrelevant - the blobs are only assembled so the
;; save directive can write them to the disk catalogue. Keep each pass's incbin span
;; below #FFFF (org #4000 -> <= ~49KB).
;;
;; Pass 1: the three original Companion apps + one gallery picture (~43 KB).
                org   #4000
pnt_img         incbin "../build/PAINT.RAW"     ; PAINT.APP (#114) - moved off Main (#250)
pnt_imgend
                save  "PAINT.APP",pnt_img,pnt_imgend-pnt_img,DSK,"build/companion.dsk"
tel_img         incbin "../build/TELNET.RAW"    ; TELNET.APP (#238) - was card-only; now floppy too
tel_imgend
                save  "TELNET.APP",tel_img,tel_imgend-tel_img,DSK,"build/companion.dsk"
xao_img         incbin "../build/XAOS.RAW"      ; XAOS.APP (#116) - moved off Main (#250)
xao_imgend
                save  "XAOS.APP",xao_img,xao_imgend-xao_img,DSK,"build/companion.dsk"
pen_img         incbin "../assets/pictures/PENGUIN.PIC" ; sample 200x200 picture -> PENGUIN.PIC
pen_imgend
                save  "PENGUIN.PIC",pen_img,pen_imgend-pen_img,DSK,"build/companion.dsk"
