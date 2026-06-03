; ---------------------------------------------------------------------------
; lib/gbapp.inc - GEOBENCH app ABI (Phase 1 skeleton).
;
; Apps are separate binaries assembled at APP_BASE. The kernel loads an app into
; an expansion bank and CALLs its entry with that bank paged into #4000-#7FFF.
; The app reaches kernel services by CALLing fixed addresses in the resident
; kernel region (GB_*), which stays mapped (#8000-#BFFF) while a bank is paged.
; An app returns to the desktop by RET, or by CALL GB_QUIT.
;
; The kernel region is a jump table at GB_KERNEL: each entry is a 3-byte `jp`,
; so the addresses below are stable as the kernel grows (keep the table order).
; ---------------------------------------------------------------------------

APP_BASE        equ   #4000        ; apps run in the #4000-#7FFF bank window

GB_KERNEL       equ   #8000        ; resident kernel base (fixed, RUN entry)
GB_INIT         equ   GB_KERNEL+0  ; #8000  kernel boot (kernel only)
GB_CLS          equ   GB_KERNEL+3  ; #8003  clear screen / home cursor
GB_PRINT        equ   GB_KERNEL+6  ; #8006  HL = 0-term string -> text output
GB_QUIT         equ   GB_KERNEL+9  ; #8009  app -> return to the desktop
