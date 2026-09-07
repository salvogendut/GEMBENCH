; Native registration/chrome provider. The 25-byte record and 12/13-byte
; descriptor are the existing native WM contract, not a new public GBABI.
; Fixed, serialized root/kernel calls only; trusted native geometry/pointers.
wm_entry equ sched_wm_entry
wm_slot equ CORE_FOCUS_TARGET
WM_MAXWIN equ CPC_OWNER_MAX
WM_FR_EVENT equ 9
GB_MSG equ #1302
GB_MSG_DRAW equ 3
GB_WK_LEGACY equ 7
GB_WK_STANDARD equ 31
GB_WK_EXTENDED equ 128
GB_WK_ABI_V1 equ #B6
                ifdef CPC_RUNTIME
TITLEBAR_TILE equ 1
THEMED_GADGETS equ 1
                else
TITLEBAR_TILE equ 0             ; preserve the isolated plain-chrome proof
THEMED_GADGETS equ 0
                endif
KWB_LIGHT equ #F0              ; Mode-1 solid logical pen 1
KWB_DARK equ #0F               ; Mode-1 solid logical pen 2
CHROME_STRING_COPY_LOOP equ cpc_title_copy
CPC_REG_GUARD equ #3290
wm_desc equ #32A0
mw_desc equ #32A2
mw_kind equ #32A4
                ifdef CPC_RUNTIME
MW_RECT equ #1448              ; frozen SDK observation, not diagnostic scratch
                else
MW_RECT equ #32A5
                endif
kw_x equ #32A9
kw_y equ #32AA
kw_w equ #32AB
kw_h equ #32AC
kf_sy equ #32AD
kfm_gx equ #32AE
kw_title equ #32B0             ; reserved 49 bytes; native title capped at 23+NUL
gf_x equ #32E1
gf_y equ #32E2
gf_w equ #32E3
gf_h equ #32E4
gf_pen equ #32E5
fb_x equ #32E6
fb_y equ #32E7
fb_w equ #32E8
fb_h equ #32E9
fb_val equ #32EA
dp_save equ #32EB
KCFG_FRAMEPEN equ #32EC
launch_arg equ #32F0
CPC_REG_END equ #33F0
                assert kw_title+49<=gf_x,"title/frame scratch overlap"
                assert launch_arg+11<=#3300,"registration scratch overflow"
                assert CPC_REG_END+16<=CPC_FUTURE_STATE_END,"registration state overflow"
                macro CHROME_GADGET_STORAGE
                mend
                macro CHROME_KIND_STORAGE
                mend
                macro CHROME_ENTRY_FLAGS
                ifdef CPC_FAULT_REG_KIND
                ld a,(WM_FOCUS)              ; reproduce the pre-extraction bug
                call wm_entry
                endif
                ld de,WM_FR_FLAGS
                add hl,de
                mend
md_call equ cpc_window_call
