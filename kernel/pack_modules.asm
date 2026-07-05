;; pack_modules.asm - extra .dsk packaging pass for paged kernel modules.
;;
;; FLOPPYSV.MOD grew beyond the slack in gbkern.asm's high packaging region.
;; It is not resident in that image; the incbin existed only so RASM could save
;; it into build/gbkern.dsk. Keep that catalogue write in its own pass.
                org   #4000
flsv_img        incbin "../build/FLOPPYSV.RAW"
flsv_imgend
                save  "FLOPPYSV.MOD",flsv_img,flsv_imgend-flsv_img,DSK,"build/gbkern.dsk"
