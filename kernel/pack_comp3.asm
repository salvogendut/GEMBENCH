;; pack_comp3.asm - COMPANION floppy, pass 3 of 4 (#250). See pack_comp1.asm header.
;;
;; Pass 3: the rest of the screensaver set (the xscreensaver ports + CATCLK, ~42 KB).
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
for_img         incbin "../build/FOREST.RAW"    ; fractal trees
for_imgend
                save  "FOREST.SAV",for_img,for_imgend-for_img,DSK,"build/companion.dsk"
hlx_img         incbin "../build/HELIX.RAW"     ; harmonograph curves
hlx_imgend
                save  "HELIX.SAV",hlx_img,hlx_imgend-hlx_img,DSK,"build/companion.dsk"
cat_img         incbin "../build/CATCLK.RAW"    ; Kit-Cat clock
cat_imgend
                save  "CATCLK.SAV",cat_img,cat_imgend-cat_img,DSK,"build/companion.dsk"
