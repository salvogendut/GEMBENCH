;; pack_apps3.asm - FOURTH-pass .dsk packaging: sync the floppy distribution with
;; the Albireo card (#198 follow-up).
;;
;; The card is staged by tools/stage_dist.sh, which GLOBS the backdrop tiles
;; (build/*.BDP), the tracked custom icon sets (assets/iconsets/*.IST) and the sample
;; pictures (assets/pictures/*.PIC). The floppy DSK is this hand-written save list, so
;; those assets never made it onto the floppy - BACKDROP=/ICONS= silently fell back and
;; only PENGUIN.PIC was viewable. This pass adds them (BIG.PIC omitted by request).
;;
;; Like pack_apps/pack_apps2: RASM's DSK save APPENDS across invocations, so this runs
;; as its own fresh 64K image into the SAME build/gbkern.dsk. Keep this list in step
;; with the stage_dist.sh globs when assets change.
                org   #4000
bdp_fancy       incbin "../build/FANCY.BDP"     ; backdrop tiles (BACKDROP=<name>, #128)
bdp_fancy_e
                save  "FANCY.BDP",bdp_fancy,bdp_fancy_e-bdp_fancy,DSK,"build/gbkern.dsk"
bdp_darker      incbin "../build/DARKER.BDP"
bdp_darker_e
                save  "DARKER.BDP",bdp_darker,bdp_darker_e-bdp_darker,DSK,"build/gbkern.dsk"
bdp_waves       incbin "../build/WAVES.BDP"
bdp_waves_e
                save  "WAVES.BDP",bdp_waves,bdp_waves_e-bdp_waves,DSK,"build/gbkern.dsk"
bdp_waves2      incbin "../build/WAVES2.BDP"
bdp_waves2_e
                save  "WAVES2.BDP",bdp_waves2,bdp_waves2_e-bdp_waves2,DSK,"build/gbkern.dsk"
ist_refined     incbin "../assets/iconsets/REFINED.IST" ; ICONS=REFINED custom set (6324 B, #198)
ist_refined_e
                save  "REFINED.IST",ist_refined,ist_refined_e-ist_refined,DSK,"build/gbkern.dsk"
pic_logo        incbin "../assets/pictures/LOGO.PIC"    ; the GEOBENCH logo - 176x176, 7758 B, the
pic_logo_e                                              ; only sample small enough to view on a bare
                save  "LOGO.PIC",pic_logo,pic_logo_e-pic_logo,DSK,"build/gbkern.dsk" ; 128K machine (<=VIEW_MAX)
pic_manado      incbin "../assets/pictures/MANADO.PIC"  ; bigger samples (need a spare RAM bank, 256K+)
pic_manado_e
                save  "MANADO.PIC",pic_manado,pic_manado_e-pic_manado,DSK,"build/gbkern.dsk"
pic_tleung      incbin "../assets/pictures/TLEUNG.PIC"
pic_tleung_e
                save  "TLEUNG.PIC",pic_tleung,pic_tleung_e-pic_tleung,DSK,"build/gbkern.dsk"
