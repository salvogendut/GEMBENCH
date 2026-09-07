; 3D-S: keep the font allocation before the F7 filesystem module. All disk
; candidates are staged/validated in the excluded F6 module bank first.
CPC_FONT_BASE equ #4000
                ifndef CPC_FONT_LIMIT
CPC_FONT_LIMIT equ #4400
                endif
CPC_FONT_STATUS equ #1850       ; 0 selected, 1 DEFAULT.FNT, 2 embedded recovery
CPC_FONT_ATTEMPT equ #1851
CPC_FONT_BYTES equ #1852
CPC_FONT_SOURCE equ #1854
CPC_FONT_DEST equ #1856
CPC_FONT_LEFT equ #1858
CPC_VISUAL_CALLS equ #185A
CPC_VISUAL_DIRTY equ #185C       ; font pixels or frame pen changed, not just RGB
CPC_VISUAL_STATE_END equ #185D
                assert CPC_NATIVE_MODULE_STATE_END<=CPC_FONT_STATUS,"visual/native state overlap"
                assert CPC_VISUAL_STATE_END<=CPC_NATIVE_STATE_END,"visual/hardware state overlap"
                assert CPC_FONT_BASE==CPC_APP_BASE,"font staging reader base mismatch"
                assert CPC_FONT_LIMIT<=#4400,"font/filesystem module overlap"
                assert CPC_FONT_LIMIT-CPC_FONT_BASE>=816,"embedded font exceeds allocation"
