;; pack_apps.asm - second-pass .dsk packaging for GEOBENCH (#114).
;;
;; The main image (gbkern.asm) packs the kernel + every app/asset into one 64K rasm
;; address space and `save`s them into build/gbkern.dsk. That space filled up. RASM's
;; DSK save APPENDS to an existing .dsk across separate invocations, so the apps that
;; overflow the main image get packaged here, in their own fresh 64K pass, into the
;; SAME .dsk. build_kernel.sh runs this right after gbkern.asm (no rm in between).
;;
;; These blobs are #4000 app images (build_capp output); the org is irrelevant - they
;; are only assembled so the save directive can write them to the disk catalogue.
;;
;; #250: PAINT.APP, XAOS.APP and PENGUIN.PIC moved OFF the Main floppy to the new
;; Companion floppy (kernel/pack_comp*.asm -> build/companion.dsk). ICONED.APP +
;; GBUI.MOD stay on Main (ICONED is a core editor; GBUI is the shared dialog module
;; that every app - incl. the Companion apps - loads from the boot drive, #110/#250).
                org   #4000
ied_img         incbin "../build/ICONED.RAW"    ; packaged on the disk as ICONED.APP (moved
ied_imgend                                      ; to pass 2 - the main image filled up, #142)
                save  "ICONED.APP",ied_img,ied_imgend-ied_img,DSK,"build/gbkern.dsk"
ui_img          incbin "../build/GBUI.RAW"      ; paged dialog module -> GBUI.MOD (#142 step 1b, #234)
ui_imgend
                save  "GBUI.MOD",ui_img,ui_imgend-ui_img,DSK,"build/gbkern.dsk"
brsave_img      incbin "../build/BRSAVE.RAW"
brsave_imgend
                save  "BRSAVE.APP",brsave_img,brsave_imgend-brsave_img,DSK,"build/gbkern.dsk"
