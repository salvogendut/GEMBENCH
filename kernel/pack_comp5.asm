;; pack_comp5.asm - COMPANION floppy, pass 5 of 5.
;;
;; Keep MAHJONG.APP in its own assembler address space: pass 4 is already close
;; to the #4000..#FFFF incbin ceiling with Browser, WGET, and Shell.
                org   #4000
mah_img         incbin "../build/MAHJONG.RAW"
mah_imgend
                save  "MAHJONG.APP",mah_img,mah_imgend-mah_img,DSK,"build/companion.dsk"
