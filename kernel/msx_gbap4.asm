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
; PORTABLE_PACKAGE_STREAM adds a separate structure-only streamed entry and
; relocates CRC/state into the boot-checked high module. The ordinary entry
; still verifies complete primary CRCs and rejects two-segment packages. This
; opt-in receiver also installs the mode-specific normal-launch/progress module.

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
                ifdef PORTABLE_PACKAGE_STREAM
                ifdef PORTABLE_FS_HANDOFF
                db    "GBV4",6
                else
                db    "GBV4",5
                endif
                else
                db    "GBV4",2
                endif
                jp    universal_parameters
                jp    module_sysinfo_init
                jp    module_sysinfo_query
                jp    button_init_impl
                jp    button_filter_impl
                ifdef PORTABLE_PACKAGE_STREAM
                jp    gbap4_validate_streamed_primary
                jp    gb4_crc32_loaded
                jp    gb4_crc_byte
                jp    gb4_crc_finish
ADMISSION_DUAL equ 1
PKG_CRC_PROGRESS equ MSX_PACKAGE_PROGRESS
ADMISSION_CRC_BASE equ MSX_PACKAGE_CRC_BASE
ADMISSION_CRC_LIMIT equ MSX_PACKAGE_ADMISSION_STATE
PKG_PRIMARY_SIZE equ MSX_PACKAGE_STATE+10
PKG_SECONDARY_SIZE equ MSX_PACKAGE_STATE+12
PKG_TOTAL_SIZE equ MSX_PACKAGE_STATE+8
PKG_CAPS_LOW equ MSX_SYS_CAPS
PKG_CAPS_HIGH equ MSX_SYS_CAPS_HIGH
                endif

ADMISSION_SYSINFO_SIZE equ MSX_SYSINFO_SIZE
ADMISSION_TYPED_CLIPBOARD equ 1
CORE_PAGE_FREE equ MSX_PAGE_FREE
                macro ADMISSION_STORAGE
                ifdef PORTABLE_PACKAGE_STREAM
gb4_file_size equ MSX_PACKAGE_ADMISSION_STATE
gb4_manifest_offset equ MSX_PACKAGE_ADMISSION_STATE+2
gb4_resource_offset equ MSX_PACKAGE_ADMISSION_STATE+4
gb4_icon_count equ MSX_PACKAGE_ADMISSION_STATE+6
gb4_expected_crc equ MSX_PACKAGE_ADMISSION_STATE+7
gb4_crc_value equ MSX_PACKAGE_ADMISSION_STATE+11
gb4_streamed equ MSX_PACKAGE_ADMISSION_STATE+15
                else
gb4_file_size       dw 0
gb4_manifest_offset dw 0
gb4_resource_offset dw 0
gb4_icon_count      db 0
gb4_expected_crc    ds 4,0
gb4_crc_value       ds 4,0
                endif
                mend
                include "core/app_admission.asm"
                include "msx_universal_parameters.asm"
                include "msx_sysinfo_init.asm"
                include "msx_button_capture.asm"
gb4_gate_end
                print "GBAPV4 module bytes: ", {int}gb4_gate_end-MSX_GBAP4_GATE

                assert gb4_gate_end<=MSX_SYSINFO_LEGACY,"GBAPV4.MOD overlaps legacy sysinfo view"
                assert MSX_SYSINFO_LEGACY+MSX_SYSINFO_SIZE<=MSX_GBAP4_GATE_LIMIT,"legacy sysinfo exceeds gate region"
                assert gb4_gate_end-MSX_GBAP4_GATE==MSX_GBAP4_GATE_SIZE,"update module byte count"
                save  "GBAPV4.RAW",MSX_GBAP4_GATE,MSX_GBAP4_GATE_SIZE
