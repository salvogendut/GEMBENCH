;; pack_comp4.asm - COMPANION floppy, pass 4 of 4 (#363/#365/#367).
;;
;; These network/utility apps do not fit in pass 1 beside Paint, Telnet, Xaos
;; and PENGUIN.PIC. A fresh RASM address space appends them to the image.
                org   #4000
wget_img        incbin "../build/WGET.RAW"
wget_imgend
                save  "WGET.APP",wget_img,wget_imgend-wget_img,DSK,"build/companion.dsk"
browser_img     incbin "../build/BROWSER.RAW"
browser_imgend
                save  "BROWSER.APP",browser_img,browser_imgend-browser_img,DSK,"build/companion.dsk"
shell_img       incbin "../build/SHELL.RAW"
shell_imgend
                save  "SHELL.APP",shell_img,shell_imgend-shell_img,DSK,"build/companion.dsk"
