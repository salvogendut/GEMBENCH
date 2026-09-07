; CPC-bound payload of the SAME native title tile renderer. Loaded from M4
; via F6 staging, admitted at exactly 384 bytes, then published to reserved F7.
; No code executes from the staging page or from an unvalidated short file.
                include "title_symbols.inc"
DATA_TITLE_SIZE equ 106
DATA_TITLE_RUN equ DATA_TITLE+DATA_TITLE_SIZE
FBW_X equ rect_x
FBW_Y equ rect_y
FBW_W equ rect_w
FBW_H equ rect_h
FB_ROWS equ draw_rows
FB_CY equ draw_y
tb_off equ CPC_TITLE_OFF
TITLE_SCREEN_ADDR equ scr_addr
                macro TITLE_CLIP
                ; Resident entry has already clipped and excluded the pointer.
                mend
                org DATA_TITLE
                incbin "ORIGINAL.TBR"
                incbin "ORIGINAL.GDT"
                include "core/title_pattern.asm"
cpc_title_module_used_end
                assert $<=DATA_TITLE+CPC_TITLE_MODULE_SIZE,"CPC title module overflow"
                defs DATA_TITLE+CPC_TITLE_MODULE_SIZE-$,0
                save "GBTITLE.MOD",DATA_TITLE,$-DATA_TITLE
