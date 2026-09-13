; Standalone private Nextor diagnostic, NOT a production kernel layout/launch.
; Real shared loader, MSX stream leaves and mapper segments; no APP executes.
                include "../lib/msx/bios.inc"
                include "../lib/msx/glue.inc"
PREEMPTIVE equ 1
PLATFORM_MSX equ 1
                include "../kernel/lowram.inc"
GB_OWNER_MAX equ 8
GB_PAGE_RESOURCE equ 2
GB_PAGE_ERR_STALE equ 2
GB_PAGE_ERR_OWNER equ 3
GB_PAGE_ERR_FREE equ 4
                include "../kernel/msx_owner_page.inc"
owner_current equ diag_unused
defer_purge_owner equ diag_unused
fsctx_owner_cleanup equ diag_unused
APP_BASE equ #4000
PKG_STATE equ #2000
PKG_BUFFER equ #1800
MSX_PKG_STATE equ #2020
PKG_CURRENT equ SCHED_CURRENT
PKG_LOCK equ SCHED_LOCK
PKG_MAPPED equ BANK_CUR
PKG_CAPS_LOW equ MSX_SYS_CAPS
PKG_CAPS_HIGH equ MSX_SYS_CAPS_HIGH
PKG_MAP equ bank_set
PKG_READ equ msx_pkg_read
PKG_CLOSE equ msx_pkg_close
PKG_ALLOW_IRQ equ 1
ADMISSION_STREAMED equ 1
ADMISSION_TYPED_CLIPBOARD equ 1
ADMISSION_SYSINFO_SIZE equ 48
                include "../kernel/core/package_stream_contract.inc"
; Result: status(55 pass/EE fail), case, load result, completed cases,
; last load ticks(word), case pointer(word), start ticks(word).
DIAG_RESULT equ #2030
                macro ADMISSION_STORAGE
gb4_file_size ds 2
gb4_manifest_offset ds 2
gb4_resource_offset ds 2
gb4_icon_count ds 1
gb4_expected_crc ds 4
gb4_crc_value ds 4
                mend
                org #8000
diag_start
                ld hl,(#0006)
                ld sp,hl
                ld de,MSX_GLUE_TOP
                or a
                sbc hl,de
                jp c,diag_fail
                ld hl,#2000
                ld de,#2001
                ld bc,255
                ld (hl),0
                ldir
                ld hl,MSX_PAGE_STATE
                ld de,MSX_PAGE_STATE+1
                ld bc,MSX_ARCH_TABLE_END-MSX_PAGE_STATE-1
                ld (hl),0
                ldir
                ld hl,APP_BUSY
                ld de,APP_BUSY+1
                ld bc,7
                ld (hl),0
                ldir
                xor a
                ld (PKG_CURRENT),a
                inc a
                ld (PKG_LOCK),a
                ld (DIAG_RESULT),a
                ld hl,#7FFF
                ld (PKG_CAPS_LOW),hl
                ld hl,#01DF
                ld (PKG_CAPS_HIGH),hl
                xor a
                ld de,#0402
                ld hl,0
                call EXTBIO
                ld a,h
                or l
                jp z,diag_fail
                ld (MSX_ALLSEG),hl
                ld de,3
                add hl,de
                ld (MSX_FRESEG),hl
                ld de,27
                add hl,de
                ld (MSX_PUTP1),hl
                inc hl
                inc hl
                inc hl
                ld (MSX_GETP1),hl
                call jp_hl
                ld (MSX_TPASEG),a
                ld (bank_cur),a
                xor a
                ld b,a
                ld hl,(MSX_ALLSEG)
                call jp_hl
                jp c,diag_fail
                ld (CORE_PAGE_NATIVE),a
                xor a
                ld b,a
                ld hl,(MSX_ALLSEG)
                call jp_hl
                jp c,diag_fail
                ld (CORE_PAGE_NATIVE+1),a
                ld a,2
                ld (CORE_PAGE_TOTAL),a
                ld (CORE_PAGE_FREE),a
                ld hl,diag_cases
                ld (DIAG_RESULT+6),hl
diag_next
                call owner_alloc
                jp nc,diag_fail
                ld (CORE_PENDING_OWNER),de
                ld b,1
                call page_alloc_owned
                jp nc,diag_fail
                ld (CORE_APP_CODE_NATIVE),a
                ld a,e
                ld (CORE_APP_CODE_PAGE),a
                ld a,d
                ld (CORE_APP_CODE_GEN),a
                ld a,(CORE_APP_CODE_NATIVE)
                di
                call bank_set
                ei
                ld hl,(DIAG_RESULT+6)
                ld e,(hl)
                inc hl
                ld d,(hl)
                call msx_pkg_open
                or a
                jr z,diag_opened
                ld hl,(DIAG_RESULT+6)
                inc hl
                inc hl
                ld a,(hl)
                cp #FF
                jp nz,diag_fail
                jp diag_cleanup
diag_opened
                ld hl,(JIFFY)
                ld (DIAG_RESULT+8),hl
                ld de,(CORE_PENDING_OWNER)
                ld ix,#1234
                ld iy,#5678
                di
                call package_load
                ld (DIAG_RESULT+2),a
                ld a,1
                ld (DIAG_RESULT+10),a
                ld a,i
                jp pe,diag_fail               ; restore the caller's DI state
                ei
                ld a,2
                ld (DIAG_RESULT+10),a
                push ix
                pop hl
                ld de,#1234
                or a
                sbc hl,de
                jp nz,diag_fail
                ld a,3
                ld (DIAG_RESULT+10),a
                push iy
                pop hl
                ld de,#5678
                or a
                sbc hl,de
                jp nz,diag_fail
                ld a,4
                ld (DIAG_RESULT+10),a
                ld hl,(DIAG_RESULT+6)
                inc hl
                inc hl
                ld a,(DIAG_RESULT+2)
                cp (hl)
                jp nz,diag_fail
                ld a,5
                ld (DIAG_RESULT+10),a
                ld hl,(MSX_GETP1)
                call jp_hl
                ld hl,CORE_APP_CODE_NATIVE
                cp (hl)
                jp nz,diag_fail
                ld a,6
                ld (DIAG_RESULT+10),a
                ld hl,(JIFFY)
                ld de,(DIAG_RESULT+8)
                or a
                sbc hl,de
                ld (DIAG_RESULT+4),hl
                ld a,(DIAG_RESULT+2)
                or a
                jr nz,diag_cleanup
                ld de,100
                or a
                sbc hl,de
                jp c,diag_fail               ; real BIOS time advances through CRC
                ld hl,(PKG_ENTRY)
                ld de,#4008
                or a
                sbc hl,de
                jp nz,diag_fail
                ld hl,(PKG_SECONDARY_SIZE)
                ld de,#3F00
                or a
                sbc hl,de
                jp nz,diag_fail
diag_cleanup
                ld a,(MSX_PKG_ACTIVE)
                ld hl,MSX_PKG_POISON
                or (hl)
                ld hl,PKG_BUSY
                or (hl)
                jp nz,diag_fail
                ld de,(CORE_PENDING_OWNER)
                call owner_release
                ld a,(CORE_PAGE_FREE)
                cp 2
                jp nz,diag_fail
                ld a,(CORE_OWNER_ACTIVE)
                or a
                jp nz,diag_fail
                ld hl,DIAG_RESULT+3
                inc (hl)
                ld a,(hl)
                cp 6
                jr z,diag_pass
                ld (DIAG_RESULT+1),a
                ld hl,(DIAG_RESULT+6)
                ld de,3
                add hl,de
                ld (DIAG_RESULT+6),hl
                jp diag_next
diag_pass
                di
                call bank_normal
                ei
                ld a,(CORE_PAGE_NATIVE)
                ld b,0
                ld hl,(MSX_FRESEG)
                call jp_hl
                jp c,diag_fail
                ld a,(CORE_PAGE_NATIVE+1)
                ld b,0
                ld hl,(MSX_FRESEG)
                call jp_hl
                jp c,diag_fail
                ld a,#55
                ld (DIAG_RESULT),a
diag_done       halt
                jr diag_done
diag_fail       ld a,#EE
                ld (DIAG_RESULT),a
                ei
                jr diag_done
diag_unused     ret
diag_cases      dw diag_good
                db 0
                dw diag_crc
                db 1
                dw diag_short
                db 2
                dw diag_extra
                db 1
                dw diag_missing
                db #FF
                dw diag_good
                db 0
diag_good       db 92,"GBENCH",92,"GOOD.APP",0
diag_crc        db 92,"GBENCH",92,"BADCRC.APP",0
diag_short      db 92,"GBENCH",92,"SHORT.APP",0
diag_extra      db 92,"GBENCH",92,"EXTRA.APP",0
diag_missing    db 92,"GBENCH",92,"MISSING.APP",0
                include "../lib/msx/bank.asm"
                include "../kernel/msx_package_stream.asm"
                include "../kernel/core/page_count.asm"
                include "../kernel/core/owner_identity.asm"
                include "../kernel/core/page_pool.asm"
                include "../kernel/core/owner_reclaim.asm"
                include "../kernel/core/app_admission.asm"
                include "../kernel/core/package_stream.asm"
diag_end
                assert diag_end<=#C000,"standalone diagnostic exceeds fixed page 2"
                save "stream-diag.bin",#8000,$-#8000
