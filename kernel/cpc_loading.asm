; Private #77 link of the production launch/admission policy. No public jump
; table is advertised until its full service/sysinfo contract is implemented.
APP_BASE equ CPC_APP_BASE
APP_LOAD_MAX equ CPC_APP_LIMIT-CPC_APP_BASE
ADMISSION_SYSINFO_SIZE equ 48
GB_PAGE_APPLICATION equ 1
                ifndef bank_set
bank_set equ foundation_bank_set
                endif
WM_OPEN_STRICT equ #123D
wm_open_page equ #12FA
wm_open_back equ #12FB
fs_ent_name equ #14DC
fs_ent_size equ #14E8
fs_req_name equ #14EC
fs_load_dst equ #14F7
fs_load_max equ #14F9
APP_ADMISSION_GATE equ cpc_loaded_admission
                macro ADMISSION_STORAGE
gb4_file_size equ #28A0
gb4_manifest_offset equ #28A2
gb4_resource_offset equ #28A4
gb4_icon_count equ #28A6
gb4_expected_crc equ #28A7
gb4_crc_value equ #28AB
                mend
cpc_loading_begin
                include "core/app_launch.asm"
                include "core/app_admission.asm"
cpc_loaded_admission
                call gbap4_validate_loaded
                ifdef CPC_RUNTIME
                ret nc
                jp cpc_runtime_admission
                endif
                ifdef CPC_FAULT_LOAD_ADMISSION
                scf                         ; negative test: execute rejected data
                endif
                ret
                include "../lib/cpc/app_load.asm"
cpc_loading_end
                assert gb4_crc_value+4<=CPC_ARCH_STATE_END,"admission state overflow"
