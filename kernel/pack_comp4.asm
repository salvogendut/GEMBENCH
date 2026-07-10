;; pack_comp4.asm - COMPANION floppy, pass 4 of 4 (#363).
;;
;; WGET.APP does not fit in pass 1 beside Paint, Telnet, Xaos and PENGUIN.PIC.
;; A fresh RASM address space appends it to the same companion image.
                org   #4000
wget_img        incbin "../build/WGET.RAW"
wget_imgend
                save  "WGET.APP",wget_img,wget_imgend-wget_img,DSK,"build/companion.dsk"
