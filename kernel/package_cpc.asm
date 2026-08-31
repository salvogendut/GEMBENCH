; Incremental CPC floppy packer for the 54-A bootstrap.
; RASM appends each PACKAGE_PASS to the same DSK, avoiding a fake requirement
; that every staged file fit simultaneously in the Z80 address space.

                ifndef PACKAGE_PASS
PACKAGE_PASS    equ   1
                endif

                if PACKAGE_PASS==1
                org   #8000
kern_img        incbin "../build/cpc/GBKERN.RAW"
kern_img_e
                org   #0100
desktop_img     incbin "../build/cpc/DESKTOP.RAW"
desktop_img_e
                save  "GB.BIN",kern_img,kern_img_e-kern_img,DSK,"../build/cpc/GEOBENCH.DSK"
                save  "DESKTOP.APP",desktop_img,desktop_img_e-desktop_img,DSK,"../build/cpc/GEOBENCH.DSK"
                endif

                if PACKAGE_PASS==2
                org   #0100
filemgr_img     incbin "../build/cpc/FILEMGR.RAW"
filemgr_img_e
probe_img       incbin "../build/universal/ABIPROBE.APP"
probe_img_e
                save  "FILEMGR.APP",filemgr_img,filemgr_img_e-filemgr_img,DSK,"../build/cpc/GEOBENCH.DSK"
                save  "ABIPROBE.APP",probe_img,probe_img_e-probe_img,DSK,"../build/cpc/GEOBENCH.DSK"
                endif

                if PACKAGE_PASS==3
                org   #0100
clock_img       incbin "../build/universal/CLOCK.APP"
clock_img_e
calc_img        incbin "../build/universal/CALC.APP"
calc_img_e
cfgmod_img      incbin "../build/cpc/GBCFG.RAW"
cfgmod_img_e
title_img       incbin "../build/GBTITLE.RAW"
title_img_e
font_img        incbin "../build/cpc/DEFAULT.FNT"
font_img_e
icons_img       incbin "../build/cpc/DEFAULT.IST"
icons_img_e
splash_img      incbin "../build/cpc/SPLASH.BIN"
splash_img_e
config_img      incbin "../build/cpc/GEOBENCH.CFG"
config_img_e
                save  "CLOCK.APP",clock_img,clock_img_e-clock_img,DSK,"../build/cpc/GEOBENCH.DSK"
                save  "CALC.APP",calc_img,calc_img_e-calc_img,DSK,"../build/cpc/GEOBENCH.DSK"
                save  "GBCFG.MOD",cfgmod_img,cfgmod_img_e-cfgmod_img,DSK,"../build/cpc/GEOBENCH.DSK"
                save  "GBTITLE.MOD",title_img,title_img_e-title_img,DSK,"../build/cpc/GEOBENCH.DSK"
                save  "DEFAULT.FNT",font_img,font_img_e-font_img,DSK,"../build/cpc/GEOBENCH.DSK"
                save  "DEFAULT.IST",icons_img,icons_img_e-icons_img,DSK,"../build/cpc/GEOBENCH.DSK"
                save  "SPLASH.MOD",splash_img,splash_img_e-splash_img,DSK,"../build/cpc/GEOBENCH.DSK"
                save  "GEOBENCH.CFG",config_img,config_img_e-config_img,DSK,"../build/cpc/GEOBENCH.DSK"

                include "../lib/cursor_data.asm"
                save  "../build/cpc/DEFAULT.SPR",cur_spr_data,cur_spr_end-cur_spr_data
                endif

                if PACKAGE_PASS==4
                org   #0100
gate_img        incbin "../build/cpc/GBAPV4.RAW"
gate_img_e
                save  "GBAPV4.MOD",gate_img,gate_img_e-gate_img,DSK,"../build/cpc/GEOBENCH.DSK"
                edsk  putfile,"../build/cpc/GEOBENCH.DSK","../build/cpc/DEFAULT.SPR","DEFAULT.SPR"
                endif

                if PACKAGE_PASS==5
                org   #0100
drag_img        incbin "../build/cpc/GBDRAG.RAW"
drag_img_e
                save  "GBDRAG.MOD",drag_img,drag_img_e-drag_img,DSK,"../build/cpc/GEOBENCH.DSK"
                endif
