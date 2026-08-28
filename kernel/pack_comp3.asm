;; pack_comp3.asm - COMPANION floppy, pass 3 of 4 (#250). See pack_comp1.asm header.
;;
;; Pass 3: the remaining xscreensaver ports. CATCLK moved to the extended
;; EXTRAS.DSK when configurable XMatrix outgrew the CF2 free space (#404);
;; HELIX joined it when MOUNTAIN gained its same-stem configuration module
;; (#446), and FOREST moved after incremental generation added an explicit
;; recursion stack (#477).
                org   #4000
mun_img         incbin "../build/MUNCH.RAW"     ; munching squares (xscreensaver port)
mun_imgend
                save  "MUNCH.SAV",mun_img,mun_imgend-mun_img,DSK,"build/companion.dsk"
ror_img         incbin "../build/RORSCH.RAW"    ; rorschach ink-blots
ror_imgend
                save  "RORSCH.SAV",ror_img,ror_imgend-ror_img,DSK,"build/companion.dsk"
tru_img         incbin "../build/TRUCHET.RAW"   ; truchet-tile maze
tru_imgend
                save  "TRUCHET.SAV",tru_img,tru_imgend-tru_img,DSK,"build/companion.dsk"
ant_img         incbin "../build/ANT.RAW"       ; Langton's ant
ant_imgend
                save  "ANT.SAV",ant_img,ant_imgend-ant_img,DSK,"build/companion.dsk"
lgt_img         incbin "../build/LIGHTN.RAW"    ; fractal lightning
lgt_imgend
                save  "LIGHTN.SAV",lgt_img,lgt_imgend-lgt_img,DSK,"build/companion.dsk"
pyr_img         incbin "../build/PYRO.RAW"      ; fireworks
pyr_imgend
                save  "PYRO.SAV",pyr_img,pyr_imgend-pyr_img,DSK,"build/companion.dsk"
