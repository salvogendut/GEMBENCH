;; pack_comp5.asm - COMPANION floppy, pass 5 of 5.
;;
;; Keep MAHJONG.APP in its own assembler address space: pass 4 is already close
;; to the #4000..#FFFF incbin ceiling with Browser, WGET, and Shell. Browser's
;; save worker and the optional hand cursor moved here to make room for
;; GBAPICK.MOD on the boot floppy (#426).
                org   #4000
mah_img         incbin "../build/MAHJONG.RAW"
mah_imgend
                save  "MAHJONG.APP",mah_img,mah_imgend-mah_img,DSK,"build/companion.dsk"
brsave_img      incbin "../build/BRSAVE.RAW"
brsave_imgend
                save  "BRSAVE.APP",brsave_img,brsave_imgend-brsave_img,DSK,"build/companion.dsk"
hand_img        incbin "../build/HAND.SPR"
hand_imgend
                save  "HAND.SPR",hand_img,hand_imgend-hand_img,DSK,"build/companion.dsk"
