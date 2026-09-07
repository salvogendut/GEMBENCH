; Native service allocations for the unified runtime, not universal ABI state.
; Text is fixed and survives module banking. Outputs do not borrow filesystem,
; graphics, context, or M4 transport state. UI_MODAL is the router's own cell.
CPC_CFG_TEXT equ #1000
CPC_CFG_TEXT_END equ #1200
CPC_UI_REQUEST equ #1700
CPC_UI_TEXT equ CPC_UI_REQUEST+24
CPC_UI_REQUEST_END equ #1800
CPC_CFG_OUTPUT equ #1800
CPC_CFG_OUTPUT_END equ #1840
CPC_CFG_STATUS equ #1840
CPC_UI_STATUS equ #1841
CPC_UI_CALLS equ #1842
CPC_CFG_CALLS equ #1844
CPC_CFG_OFFSET equ #1846
CPC_NATIVE_MODULE_STATE_END equ #1850
CPC_SYSTEM_PAGE equ #F6
CPC_MODULE_BASE equ #4000
                ifndef CPC_MODULE_CODE_END
CPC_MODULE_CODE_END equ #5800
                endif
CPC_MODULE_DATA equ #5800
CPC_MODULE_DATA_END equ #5B00  ; includes the shared picker's label/name arrays
CPC_UI_UNDER equ #5B00
CPC_UI_UNDER_END equ #6C00
CPC_UI_POPUP equ #6C00
CPC_UI_POPUP_END equ CPC_APP_LIMIT
CPC_PICK_PATH equ #1E00        ; private native selection handoff, 48-byte path
CPC_PICK_OWNER equ #1E30
CPC_UI_OWNER equ #1E32          ; captured BEFORE system-module banking
CPC_PICK_STATUS equ #1E34
CPC_PICK_PROBE_BYTES equ #1E36
CPC_PICK_PROBE_DATA equ #1E38   ; 16-byte diagnostic readback, not an app buffer
CPC_PICK_STATE_END equ #1E48
CPC_EDIT_OP equ 26              ; private native service, not a universal UI op
CPC_EDIT_STATUS equ #1E48       ; 0 OK; 1 module; 2 request; 3 read; 4 bounds;
                               ; 5 write; 6 verify; 7 context; 8 reload
CPC_EDIT_CHANGED equ #1E49      ; 1 only after a verified disk write
CPC_EDIT_ERROR equ #1E4A        ; FSCTX status, or 16 + native transport status
CPC_EDIT_CALLS equ #1E4C
CPC_EDIT_STATE_END equ #1E4E
                assert CPC_EDIT_STATUS>=CPC_PICK_STATE_END,"edit/picker overlap"
                assert CPC_EDIT_STATE_END<=CPC_ADAPTER_STATE_END,"edit state overflow"
                assert CPC_PICK_STATE_END<=CPC_ADAPTER_STATE_END,"picker state overflow"
                assert CPC_CFG_TEXT>=CPC_NATIVE_STATE_BASE,"config/support overlap"
                assert CPC_CFG_TEXT_END<=#1200,"config/native state overlap"
                assert CPC_UI_REQUEST>=CPC_FS_XFER+512,"UI/filesystem transfer overlap"
                assert CPC_UI_REQUEST_END<=CPC_CFG_OUTPUT,"UI/config overlap"
                assert CPC_NATIVE_MODULE_STATE_END<=#1A00,"native service/hardware overlap"
                assert CPC_MODULE_CODE_END<=CPC_MODULE_DATA,"module code/data overlap"
                assert CPC_MODULE_DATA_END<=CPC_UI_UNDER,"module/save-under overlap"
                assert CPC_UI_UNDER_END<=CPC_UI_POPUP,"nested dialog save-under overlap"
                assert CPC_UI_POPUP_END<=CPC_APP_LIMIT,"dialog/snapshot overlap"
                assert 60*62<=CPC_UI_UNDER_END-CPC_UI_UNDER,"About save-under too small"
                assert CPC_SYSTEM_PAGE!=CPC_DATA_PAGE,"UI/filesystem page collision"
