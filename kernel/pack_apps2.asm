;; pack_apps2.asm - THIRD-pass .dsk packaging for GEOBENCH (#142).
;;
;; Like pack_apps.asm: the main gbkern.asm image (kernel + apps/assets in one 64K
;; address space) filled up, and RASM's DSK save APPENDS across separate invocations,
;; so overflow binaries get packaged in their own fresh 64K pass into the SAME .dsk.
;; build_kernel.sh runs this right after pack_apps.asm (no rm in between).
;;
;; VIEWER and FILEMGR moved here when the gb_doc framework (#142) grew their code:
;; VIEWER no longer fit gbkern.asm's high (above-kernel) region and FILEMGR no longer
;; fit its low (#0100) region. They are independent of pack_apps.asm's blobs, so a
;; separate pass keeps each image well under 64K.
;;
;; These are #4000 app images (build_capp output); the org is irrelevant - they are
;; only assembled so the save directive can write them to the disk catalogue.
                org   #4000
vwr_img         incbin "../build/VIEWER.RAW"    ; packaged on the disk as VIEWER.APP (#45)
vwr_imgend
                save  "VIEWER.APP",vwr_img,vwr_imgend-vwr_img,DSK,"build/gbkern.dsk"
app_img         incbin "../build/FILEMGR.RAW"   ; packaged on the disk as FILEMGR.APP (#45)
app_imgend
                save  "FILEMGR.APP",app_img,app_imgend-app_img,DSK,"build/gbkern.dsk"
set_img         incbin "../build/SETTINGS.RAW"  ; packaged on the disk as SETTINGS.APP (#129)
set_imgend
                save  "SETTINGS.APP",set_img,set_imgend-set_img,DSK,"build/gbkern.dsk"
sav_img         incbin "../build/CIRCLE.RAW"    ; the test screensaver -> CIRCLE.SAV (#219)
sav_imgend
                save  "CIRCLE.SAV",sav_img,sav_imgend-sav_img,DSK,"build/gbkern.dsk"
deco_img        incbin "../build/DECO.RAW"      ; art-deco panels screensaver -> DECO.SAV
deco_imgend
                save  "DECO.SAV",deco_img,deco_imgend-deco_img,DSK,"build/gbkern.dsk"
mtx_img         incbin "../build/XMATRIX.RAW"   ; Matrix digital-rain screensaver -> XMATRIX.SAV
mtx_imgend
                save  "XMATRIX.SAV",mtx_img,mtx_imgend-mtx_img,DSK,"build/gbkern.dsk"
