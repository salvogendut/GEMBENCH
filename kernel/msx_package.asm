; Private fixed stream-module composition. Boot validates the versioned module set.
PLATFORM_MSX equ 1
                include "../lib/gbapp.inc"
                include "../lib/msx/bios.inc"
                include "../lib/msx/glue.inc"
PREEMPTIVE equ 1
                include "lowram.inc"
GB_OWNER_MAX equ 8
CORE_OWNER_ACTIVE equ MSX_OWNER_ACTIVE
CORE_OWNER_GEN equ MSX_OWNER_GEN
CORE_PENDING_OWNER equ MSX_PENDING_OWNER
CORE_APP_FLAGS equ MSX_APP_FLAGS
CORE_APP_CODE_NATIVE equ MSX_APP_CODE_NATIVE
PKG_STATE equ MSX_PACKAGE_STATE
PKG_BUFFER equ MSX_PACKAGE_BUFFER
PKG_CURRENT equ SCHED_CURRENT
PKG_LOCK equ SCHED_LOCK
PKG_MAPPED equ BANK_CUR
PKG_CAPS_LOW equ MSX_SYS_CAPS
PKG_CAPS_HIGH equ MSX_SYS_CAPS_HIGH
PKG_ALLOW_IRQ equ 1
PKG_CLEAR_SECONDARY equ MSX_PACKAGE_CLEAR
PKG_MAP equ MSX_PACKAGE_MAP
PKG_READ equ MSX_PACKAGE_IO_READ
PKG_CLOSE equ MSX_PACKAGE_IO_CLOSE
                include "core/package_stream_contract.inc"
                org MSX_PACKAGE_IO_BASE
                jp msx_pkg_open
                db "GBIO",3
                jp msx_pkg_read_prefix
                jp msx_pkg_close
                jp owner_validate
                jp msx_package_map_impl
                jp page_alloc_owned
                jp page_free_owned
MSX_PKG_STATE equ MSX_PACKAGE_IO_STATE
                include "msx_package_stream.asm"
                include "core/owner_validate.asm"
page_alloc_owned
                xor a
                jp GB_PAGE                    ; existing pending-owner allocator
page_free_owned
                ld a,1
                jp GB_PAGE
msx_package_map_impl
                ld (BANK_CUR),a
                push ix
                push iy
                push hl
                push de
                ld hl,(MSX_PUTP1)
                call msx_package_jp
                pop de
                pop hl
                pop iy
                pop ix
                ret
msx_package_jp jp (hl)
msx_package_io_end
                assert msx_package_io_end<=MSX_PACKAGE_PREFIX,"package helpers overlap launch state"
                ds #D100-$,0                  ; gap + transaction/stream state cold zero
                save "GBPKIO.RAW",MSX_PACKAGE_IO_BASE,#D100-MSX_PACKAGE_IO_BASE

gbap4_validate_streamed_primary equ MSX_PACKAGE_VALIDATE
gb4_crc32_loaded equ MSX_PACKAGE_CRC_SEED
gb4_crc_byte equ MSX_PACKAGE_CRC_UPDATE
gb4_crc_finish equ MSX_PACKAGE_CRC_FINISH
gb4_expected_crc equ MSX_PACKAGE_ADMISSION_STATE+7
gb4_crc_value equ MSX_PACKAGE_ADMISSION_STATE+11
                org MSX_PACKAGE_ENTRY
                jp package_load
                db "GBPK",2
                include "core/package_stream.asm"
                assert package_load_end-MSX_PACKAGE_ENTRY==MSX_PACKAGE_CODE_SIZE,"update package module size"
                save "GBPKLOAD.RAW",MSX_PACKAGE_ENTRY,MSX_PACKAGE_CODE_SIZE

                org MSX_PACKAGE_EXTRA_BASE
; The normal file resolver has already opened and read the first 256 bytes.
; Serve that prefix once, then continue the SAME descriptor via the real leaf.
msx_pkg_read_prefix
                ld a,(MSX_PACKAGE_PREFIX)
                or a
                jr nz,msx_pkg_cached_prefix
                call msx_pkg_read
                push af
                call MSX_PACKAGE_PROGRESS
                pop af
                ret
msx_pkg_cached_prefix
                call msx_pkg_require_open
                ret nz
                push de
                ld de,PKG_BUFFER
                or a
                sbc hl,de
                pop de
                ld a,h
                or l
                jp nz,msx_pkg_bad
                ld a,b
                dec a
                or c
                jp nz,msx_pkg_bad               ; exactly the internal first 256-byte read
                xor a
                ld (MSX_PACKAGE_PREFIX),a
                ret
msx_package_extra_end
                assert msx_package_extra_end<=MSX_PACKAGE_ADMISSION_STATE,"package extras overlap admission state"
                save "GBPKEX.RAW",MSX_PACKAGE_EXTRA_BASE,msx_package_extra_end-MSX_PACKAGE_EXTRA_BASE
