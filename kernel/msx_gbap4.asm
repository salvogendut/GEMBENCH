; msx_gbap4.asm - transactional GBAP v4 admission gate for the MSX2 loader.
;
; The ordinary WM launch path has already allocated a pending owner and its
; primary mapper page, mapped that page at #4000, and loaded the complete file.
; This gate runs before the outer JP. It accepts headerless/GBAP v1-v3 binaries
; unchanged, but a file claiming GBAP v4 must be a canonical, primary-only
; GEOBENCH-2 package produced by tools/build_uapp.sh. Any rejection returns NC;
; wmo_fail then restores the old bank and releases the pending owner plus every
; page it owns. Optional external segments remain deliberately unsupported and
; the corresponding package-resources capability is not advertised.

PLATFORM_MSX equ 1
                include "../lib/gbapp.inc"
                include "../lib/msx/glue.inc"
PREEMPTIVE equ 1
                include "lowram.inc"
                include "msx_capabilities.inc"
GB_PLATFORM_MSX2 equ 1
GB_APP_MAX equ 8
GB_DEFER_MAX equ 8

fs_ent_size             equ #14E8

                org   MSX_GBAP4_GATE
                jp    gbap4_validate_loaded
                db    "GBV4",2
                jp    universal_parameters
                jp    module_sysinfo_init
                jp    module_sysinfo_query

ADMISSION_SYSINFO_SIZE equ MSX_SYSINFO_SIZE
CORE_PAGE_FREE equ MSX_PAGE_FREE
                macro ADMISSION_STORAGE
gb4_file_size       dw 0
gb4_manifest_offset dw 0
gb4_resource_offset dw 0
gb4_icon_count      db 0
gb4_expected_crc    ds 4,0
gb4_crc_value       ds 4,0
                mend
                include "core/app_admission.asm"
                include "msx_universal_parameters.asm"
                include "msx_sysinfo_init.asm"
gb4_gate_end

                assert gb4_gate_end<=MSX_SYSINFO_LEGACY,"GBAPV4.MOD overlaps legacy sysinfo view"
                assert gb4_gate_end-MSX_GBAP4_GATE==MSX_GBAP4_GATE_SIZE,"update module byte count"
                save  "GBAPV4.RAW",MSX_GBAP4_GATE,MSX_GBAP4_GATE_SIZE
