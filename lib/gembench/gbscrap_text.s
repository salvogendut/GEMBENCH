; Compact typed-text client for code-constrained MSX2 applications.
;
; This exports the normal gb_scrap_set() contract plus gb_scrap_type(). Apps
; needing query/get/clear link the full C runtime instead. Payload bytes and the
; legacy length remain at #3E02/#3E00; the tag is published last at #133D.

        .module gbscrap_text
        .optsdcc -mz80 sdcccall(1)

        .globl _gb_scrap_set
        .globl _gb_scrap_type

GB_SCRAP_TYPE   = 0x133D
GB_CLIP_LEN     = 0x3E00
GB_CLIP_DATA    = 0x3E02
GB_CLIP_CAP     = 0x01FE

        .area _CODE

;; unsigned char gb_scrap_set(unsigned char type, const char *data,
;;                            unsigned int length)
;; A=type, DE=data, stack=[return][length]. The callee removes length.
_gb_scrap_set::
        pop     hl                      ; return
        pop     bc                      ; requested length
        push    hl                      ; restore return for RET
        ld      l,a                     ; L=type, H=result below
        cp      #1
        jr      c,gst_bad_type
        cp      #5
        jr      nc,gst_bad_type
        ld      a,b
        or      c
        jr      z,gst_empty
        ld      a,d
        or      e
        jr      z,gst_bad_argument

        ld      a,b                     ; length > 0x01FE?
        cp      #2
        jr      nc,gst_truncated
        or      a
        jr      z,gst_fits
        ld      a,c
        cp      #0xFF
        jr      z,gst_truncated
gst_fits:
        ld      h,#0                    ; GB_SCRAP_OK
        jr      gst_publish
gst_truncated:
        ld      bc,#GB_CLIP_CAP
        ld      h,#1                    ; GB_SCRAP_TRUNCATED
        jr      gst_publish
gst_empty:
        ld      l,#0                    ; empty scrap is normalized as untyped
        ld      h,#0

gst_publish:
        xor     a                       ; invalidate the old tag first
        ld      (GB_SCRAP_TYPE),a
        ld      (GB_CLIP_LEN),bc        ; raw length semantics stay unchanged
        push    hl                      ; save result/type across LDIR
        ld      h,d
        ld      l,e                     ; HL=source
        ld      de,#GB_CLIP_DATA
        ld      a,b
        or      c
        jr      z,gst_copied
        ldir
gst_copied:
        pop     hl
        ld      a,l
        ld      (GB_SCRAP_TYPE),a       ; publish type only after complete data
        ld      a,h
        ret

gst_bad_type:
        ld      a,#3                    ; GB_SCRAP_ERR_TYPE
        ret
gst_bad_argument:
        ld      a,#2                    ; GB_SCRAP_ERR_ARGUMENT
        ret

;; unsigned char gb_scrap_type(void)
_gb_scrap_type::
        ld      hl,(GB_CLIP_LEN)
        ld      a,h
        or      l
        jr      z,gst_untyped
        ld      a,(GB_SCRAP_TYPE)
        cp      #1
        jr      c,gst_untyped
        cp      #5
        ret     c
gst_untyped:
        xor     a
        ret
