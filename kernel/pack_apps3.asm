;; pack_apps3.asm - FOURTH-pass .dsk packaging: sync the floppy distribution with
;; the Albireo card (#198 follow-up).
;;
;; The card is staged by tools/stage_dist.sh, which globs backdrop tiles and custom
;; icon sets. The Main floppy keeps the same boot assets plus only LOGO.PIC for its
;; default wallpaper; the complete gallery is generated separately as EXTRAS.DSK.
;;
;; Like pack_apps/pack_apps2: RASM's DSK save APPENDS across invocations, so this runs
;; as its own fresh 64K image into the SAME build/gbkern.dsk. Keep this list in step
;; with the stage_dist.sh globs when assets change.
                org   #4000
cfg_geobench    incbin "../build/GEOBENCH.CFG"  ; #205: default config at the floppy root - the
cfg_geobench_e                                  ; Settings app reads/writes it (the card gets the
                save  "GEOBENCH.CFG",cfg_geobench,cfg_geobench_e-cfg_geobench,DSK,"build/gbkern.dsk" ; same file via stage_dist.sh)
cfg_default     incbin "../build/DEFAULT.CFG"   ; pristine source for Settings > Return to Defaults
cfg_default_e
                save  "DEFAULT.CFG",cfg_default,cfg_default_e-cfg_default,DSK,"build/gbkern.dsk"
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
pic_logo        incbin "../assets/pictures/LOGO.PIC"    ; boot wallpaper; all pictures also ship
pic_logo_e                                              ; on EXTRAS.DSK and card/MSX PICS folders
                save  "LOGO.PIC",pic_logo,pic_logo_e-pic_logo,DSK,"build/gbkern.dsk"
