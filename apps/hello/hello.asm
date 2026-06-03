; hello - the first GEOBENCH app: a separate binary that runs inside an
; expansion bank and reaches the kernel through the fixed API jump table.
; Proves the loader -> bank -> run -> kernel-API -> return cycle.
;
; Assembled at APP_BASE (#4000); the kernel copies this image into a bank and
; CALLs APP_BASE with the bank paged in. Returns to the kernel with RET.

                include "../../lib/gbapp.inc"

                org   APP_BASE
app_entry
                ld    hl,hello_msg
                call  GB_PRINT               ; firmware 8x8 line
                ld    b,2                     ; byte col
                ld    c,70                    ; pixel line
                ld    d,1                     ; pen 1
                ld    e,0                     ; paper 0
                ld    hl,font_msg            ; drawn with the kernel's 6x8 font
                call  GB_TEXT
                ret                            ; back to the desktop kernel

hello_msg       db    "HELLO FROM A BANKED APP!",13,10,0
font_msg        db    "6x8 font drawn by the kernel service",0
app_end
                save  "build/HELLO.RAW",APP_BASE,app_end-APP_BASE
