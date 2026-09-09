; CPC restart #77: fixed production allocations, exclusive ends.
; This is NOT the old native bulk-buffer map. No framebuffer/raster-gap state.
; Reservations for not-yet-linked services are budgets, not measured code.
CPC_LOADER_BASE equ #0100
CPC_LOADER_END equ #0400
CPC_SUPPORT_BASE equ #0400
CPC_SUPPORT_END equ #1000
CPC_NATIVE_STATE_BASE equ #1000
CPC_NATIVE_STATE_END equ #1A00
CPC_ADAPTER_STATE_BASE equ #1A00
CPC_ADAPTER_STATE_END equ #2000
CPC_ARCH_STATE_BASE equ #2000
CPC_ARCH_STATE_END equ #2900
                ifndef CPC_SCHED_BASE
CPC_SCHED_BASE equ #2900
                endif
CPC_SCHED_END equ #2F00
CPC_SYSINFO_BASE equ #2F00
CPC_SYSINFO_END equ #3000
CPC_FUTURE_STATE_BASE equ #3000
CPC_FUTURE_STATE_END equ #3400
CPC_DRAW_STAGING_BASE equ #3400
CPC_DRAW_STAGING_END equ #3500
CPC_STACK_GUARD equ 16
                ifndef CPC_MAIN_STACK
CPC_MAIN_STACK equ #3510
                endif
CPC_MAIN_TOP equ CPC_MAIN_STACK+256
                ifndef CPC_IRQ_STACK
CPC_IRQ_STACK equ #3630
                endif
CPC_IRQ_TOP equ CPC_IRQ_STACK+256
CPC_TMP_STACK equ #3750
CPC_TMP_TOP equ #37D0
CPC_STACKS_END equ #3800
CPC_HARDWARE_BASE equ #3800
CPC_HARDWARE_END equ #3E00
CPC_CLIPBOARD_BASE equ #3E00
CPC_CLIPBOARD_END equ #4000
CPC_SCRAP_TYPE equ #133D          ; private; same shared policy, not an app mailbox
CPC_APP_BASE equ #4000
CPC_APP_LIMIT equ #7F00
CPC_APP_END equ #8000
CPC_KERNEL_BASE equ #8000
                ifndef CPC_KERNEL_END
CPC_KERNEL_END equ #C000
                endif
CPC_SCREEN_BASE equ #C000
CPC_SCREEN_END equ #10000
CPC_COLUMNS equ 80
CPC_LINES equ 200
CPC_WIDTH equ 320
CPC_WINDOW_MAX equ 8
CPC_OWNER_MAX equ 8
CPC_PAGE_MAX equ 32
; 512 KiB: three fixed base pages, 29 aperture pages. Reserve F7 for data/
; modules, leaving C0 plus 27 expansion pages for the shared owner allocator.
CPC_DATA_PAGE equ #F7
                ifdef CPC_RUNTIME
CPC_POOL_PAGES equ 27                 ; F6 is the native config/UI module bank
                else
CPC_POOL_PAGES equ 28
                endif

                assert CPC_ARCH_STATE_END<=CPC_SCHED_BASE,"architecture/scheduler overlap"
                assert CPC_SCHED_BASE<CPC_SCHED_END,"invalid scheduler allocation"
                assert CPC_SCHED_END<=CPC_SYSINFO_BASE,"scheduler/sysinfo overlap"
                assert CPC_DRAW_STAGING_END<=CPC_MAIN_STACK-16,"staging/main stack overlap"
                assert CPC_MAIN_TOP+16<=CPC_IRQ_STACK-16,"main/IRQ stack overlap"
                assert CPC_IRQ_TOP+16<=CPC_TMP_STACK-16,"IRQ/temporary stack overlap"
                assert CPC_TMP_TOP+16<=CPC_STACKS_END,"temporary stack/hardware overlap"
                assert (CPC_KERNEL_END>CPC_KERNEL_BASE)&(CPC_KERNEL_END<=CPC_SCREEN_BASE),"kernel/framebuffer overlap"

; Native record geometry retained for linking the SAME shared mechanisms.
WM_TABLE equ #1352
WM_ESZ equ 25
WM_FR_FLAGS equ 13
WM_FR_FRAME equ 5
WM_NWIN equ #1350
WM_FOCUS equ #1351
WM_Z equ #141A
WM_CLIP_X equ #1338
WM_CLIP_Y equ #1339
WM_CLIP_W equ #133A
WM_CLIP_H equ #133B
SCHED_LOCK equ #1340
SCHED_RESERVED equ #1341
SCHED_CURRENT equ #1342
SCHED_QUANTUM equ #1343
SCHED_RUNNABLE equ #1344
SCHED_FLAGS equ #1345
SCHED_STACK_MAX equ #1346
SCHED_FAULT equ #1347
BANK_CUR equ #134F
BOOT_SP equ #1244

                assert WM_TABLE+CPC_WINDOW_MAX*WM_ESZ<=WM_Z,"window table/z-order overlap"
                assert WM_Z+CPC_WINDOW_MAX<=CPC_NATIVE_STATE_END,"native window state overflow"

; Explicit hardware state, common to loader and runtime (no firmware calls).
bank_shadow equ BANK_CUR
ga_shadow equ #1A00
rom_shadow equ #1A01
io_busy equ #1A02
io_offline equ #1A03
io_status equ #1A04
io_fd equ #1A05
io_actual equ #1A06
command_count equ #1A08
request_packet equ #1A20
path_buffer equ #1A40
transfer_buffer equ #1A80
response_buffer equ #1B00
command_buffer equ #1BA0
CPC_HW_TICKS equ #1C30
CPC_HW_SECONDS equ #1C32
CPC_HW_DIVIDER equ #1C34
CPC_IRQ_OLD_SP equ #1C36
CPC_IRQ_COUNT equ #1C38
CPC_KEYS equ #1C40
CPC_INPUT_PORTC equ #1C4A
; Boot/private diagnostic results, not a public ABI or shared WM implementation.
CPC_RESULT equ #1D00
CPC_PHASE equ CPC_RESULT+6
CPC_FAILURE equ CPC_RESULT+7
CPC_ROOT_TURNS equ CPC_RESULT+8
CPC_WORKER_COUNTER equ CPC_RESULT+10
CPC_FINAL_SP equ CPC_RESULT+12
CPC_IO_CHECKS equ CPC_RESULT+14
CPC_KEY_OBSERVED equ CPC_RESULT+16
CPC_LOAD_REMAIN equ #1D40
CPC_LOAD_DEST equ #1D42
CPC_LOAD_OFFSET equ #1D44
CPC_LOAD_COUNT equ #1D46

                assert command_buffer+132<=CPC_HW_TICKS,"M4 packet/hardware state overlap"
                assert response_buffer+136<=command_buffer,"M4 response/packet overlap"
                assert transfer_buffer+128<=response_buffer,"M4 staging/response overlap"
                assert path_buffer+64<=transfer_buffer,"M4 path/staging overlap"
                assert request_packet+16<=path_buffer,"M4 request/path overlap"
                assert CPC_LOAD_COUNT+2<=CPC_ADAPTER_STATE_END,"adapter state overflow"
