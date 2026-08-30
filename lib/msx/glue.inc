; ---------------------------------------------------------------------------
; lib/msx/glue.inc - the page-3 resident glue cells for the MSX2 target (#287).
;
; #C000-#F37F is ordinary TPA RAM under MSX-DOS (the screen lives in VRAM), and
; unlike pages 0-2 it is NEVER remapped: not by our own segment switching, and -
; crucially - not by the BIOS interrupt, which runs the H.TIMI hook with the
; BIOS ROM in page 0 (the M0 spike found handlers in page 0/1 are invisible at
; interrupt time). Everything the ISR or the mapper path touches lives here.
;
; The bootstrap stub (kernel/msx_stub.asm) fills these before jumping to
; GB_INIT; the kernel treats them as read-mostly platform facts.
; ---------------------------------------------------------------------------

MSX_TICK        equ   #C000        ; word: H.TIMI frame counter (the 50/60Hz pace base)
MSX_HOOKCODE    equ   #C004        ; the relocated H.TIMI handler lives here (<=12 bytes)
MSX_ALLSEG      equ   #C010        ; word: ALL_SEG entry (DOS 2 mapper support routine)
MSX_FRESEG      equ   #C012        ; word: FRE_SEG entry
MSX_PUTP1       equ   #C014        ; word: PUT_P1 entry (switch page 1 + DOS shadow)
MSX_GETP1       equ   #C016        ; word: GET_P1 entry
MSX_TPASEG      equ   #C018        ; byte: the TPA's own page-1 segment (= "bank_normal")
MSX_TOTSEG      equ   #C019        ; byte: primary-mapper total segments
MSX_FREESEG     equ   #C01A        ; byte: primary-mapper free segments at entry
MSX_HOOKSAVE    equ   #C01B        ; 5 bytes: original H.TIMI content (restored on exit)
MSX_PAGE_DATA   equ   #C020        ; byte: the allocated PAGE_DATA mapper segment
MSX_MOUSE       equ   #C021        ; byte: 1 = poll GTPAD (MSXMOUSE=TRUE or GBMSX /M)
                                   ; known empty-port samples are ignored by input.asm
MSX_DRIVE_MAP   equ   #C022        ; 3 bytes: GEOBENCH slot -> DOS drive number (A:=0)
MSX_DRIVE_TYPE  equ   #C025        ; 3 bytes: floppy/SD/IDE/generic media classification
MSX_DRIVE_COUNT equ   #C028        ; number of populated slots (maximum 3)
MSX_BOOT_DOS    equ   #C029        ; DOS drive number from which GBMSX was launched
; Diagnostic-only GEMBENCH baseline telemetry. Release builds leave this gap
; untouched. Page 3 remains visible when the BIOS maps ROM over page 0, so 1983
; can read these cells at an arbitrary frame boundary.
MSX_BASELINE_PHASE        equ #C02A
MSX_BASELINE_STACK_MAX    equ #C02B
MSX_BASELINE_STACK_FAULT  equ #C02C
MSX_BASELINE_COOKIE       equ #C02D
MSX_BASELINE_INPUT_FLAGS  equ #C02E  ; bit0 armed, bit1 pointer drawn, bit2 key drawn
MSX_BASELINE_INPUT_KEY    equ #C02F  ; character acknowledged by the desktop
MSX_BASELINE_FULL_START   equ #C040  ; RTC test-clock BCD: seconds, minutes, hours
MSX_BASELINE_FULL_END     equ #C043
MSX_BASELINE_DAMAGE_START equ #C046
MSX_BASELINE_DAMAGE_END   equ #C049
MSX_BASELINE_POINTER_ARM  equ #C04E  ; H.TIMI frame ticks at arm / completed draw
MSX_BASELINE_POINTER_ACK  equ #C050
MSX_BASELINE_KEY_ARM      equ #C052  ; H.TIMI frame ticks at arm / visible key response
MSX_BASELINE_KEY_ACK      equ #C054
MSX_BASELINE_RUNNABLE     equ #C056  ; scheduler runnable count when input is armed
GLINE_X0        equ   #C030        ; GB_LINE marshal block (#287): x0,y0,x1,y1 words
GLINE_Y0        equ   #C032        ; (screen pixels, top-left origin) + pen byte.
GLINE_X1        equ   #C034        ; Page-3 cells so the clock's inline asm can fill
GLINE_Y1        equ   #C036        ; them whatever segment its window has mapped.
GLINE_PEN       equ   #C038
MSX_ROWBUF      equ   #C080        ; 256-byte Screen-7 row buffer (#C080..#C17F)
; Milestone-7 GBR resource-segment request. Apps marshal only fixed-size values
; here; the resident service maps the resource, copies at most 32 bytes, and
; restores the app before returning. Page 3 remains visible throughout.
MSX_GBR_NAME    equ   #C180        ; 11-byte raw 8.3 name in /GBENCH
MSX_GBR_PAGE    equ   #C18B        ; allocated mapper segment / read handle
MSX_GBR_SIZE    equ   #C18C        ; loaded file size (word)
MSX_GBR_OFF     equ   #C18E        ; read offset (word)
MSX_GBR_DST     equ   #C190        ; caller destination after app restore (word)
MSX_GBR_LEN     equ   #C192        ; requested byte count, 1..32
MSX_GBR_BUF     equ   #C1A0        ; 32-byte resident transfer buffer
MSX_GBR_MAXREAD equ   32
; Architecture milestone 1 (#31): mapper pages and application owners are
; separate from the eight-entry window table.  Handles are 16-bit values whose
; low byte is slot+1 and whose high byte is a nonzero generation.  The native
; mapper segment stays private to the kernel.
MSX_PAGE_MAX       equ #20          ; at most 32 complete 16 KiB pages
MSX_PAGE_NATIVE    equ #C200        ; 32 native mapper segment numbers
MSX_PAGE_STATE     equ #C220        ; 0 free / 1 allocated
MSX_PAGE_OWNER     equ #C240        ; owning identity low byte (slot+1)
MSX_PAGE_OWNER_GEN equ #C260        ; owning identity generation
MSX_PAGE_GEN       equ #C280        ; page-handle generation
MSX_PAGE_PURPOSE   equ #C2A0        ; GB_PAGE_* purpose
MSX_OWNER_ACTIVE   equ #C2C0        ; 8 owner slots, independent of windows
MSX_OWNER_GEN      equ #C2C8        ; owner-handle generations
MSX_WIN_OWNER      equ #C2D0        ; owner low byte for each WM slot
MSX_WIN_OWNER_GEN  equ #C2D8        ; owner generation for each WM slot
MSX_PENDING_OWNER  equ #C2E0        ; owner being loaded before WM registration
MSX_CLOSE_OWNER    equ #C2E2        ; close-path owner scratch
MSX_PAGE_TOTAL     equ #C2E4        ; pages retained from DOS, including TPA P1
MSX_PAGE_FREE      equ #C2E5        ; currently unallocated retained pages
MSX_ALLOC_OWNER    equ #C2E6        ; allocator scratch: owner handle
MSX_ALLOC_PURPOSE  equ #C2E8        ; allocator scratch: requested purpose
MSX_ALLOC_HANDLE   equ #C2E9        ; allocator/free scratch: page handle
MSX_ALLOC_NATIVE   equ #C2EB        ; legacy-claim scratch: native segment
MSX_ALLOC_INDEX    equ #C2EC        ; legacy-claim scratch: pool index

; Read-only, versioned GB_SYSINFO record returned by GB_SYSINFO. The free
; page byte follows allocator changes and is also refreshed on every query;
; all other fields are fixed at boot.
MSX_SYSINFO        equ #C2F0
MSX_SYSINFO_V1_SIZE equ 20
MSX_SYSINFO_SIZE   equ 32
MSX_SYS_SIZE       equ MSX_SYSINFO+0
MSX_SYS_VERSION    equ MSX_SYSINFO+1
MSX_SYS_ABI_MAJOR  equ MSX_SYSINFO+2
MSX_SYS_ABI_MINOR  equ MSX_SYSINFO+3
MSX_SYS_PLATFORM   equ MSX_SYSINFO+4
MSX_SYS_VIDEO_MODE equ MSX_SYSINFO+5
MSX_SYS_WIDTH      equ MSX_SYSINFO+6
MSX_SYS_HEIGHT     equ MSX_SYSINFO+8
MSX_SYS_PACKING    equ MSX_SYSINFO+10
MSX_SYS_COLOURS    equ MSX_SYSINFO+11
MSX_SYS_MEM_PAGES  equ MSX_SYSINFO+12
MSX_SYS_POOL_TOTAL equ MSX_SYSINFO+13
MSX_SYS_POOL_FREE  equ MSX_SYSINFO+14
MSX_SYS_MAX_WINDOWS equ MSX_SYSINFO+15
MSX_SYS_CAPS       equ MSX_SYSINFO+16
MSX_SYS_RESERVED   equ MSX_SYSINFO+18
MSX_SYS_MAX_APPS   equ MSX_SYSINFO+20
MSX_SYS_APP_VERSION equ MSX_SYSINFO+21
MSX_SYS_MAX_APP_WINDOWS equ MSX_SYSINFO+22
MSX_SYS_RESERVED2  equ MSX_SYSINFO+23
MSX_SYS_MSG_QUEUE  equ MSX_SYSINFO+24
MSX_SYS_MSG_INLINE equ MSX_SYSINFO+25
MSX_SYS_MSG_VERSION equ MSX_SYSINFO+26
MSX_SYS_RESERVED3  equ MSX_SYSINFO+27
MSX_SYS_FS_CONTEXTS equ MSX_SYSINFO+28
MSX_SYS_FS_TRANSFER equ MSX_SYSINFO+29 ; word: bounded bytes advanced per call
MSX_SYS_FS_VERSION  equ MSX_SYSINFO+31

; Architecture milestone 2 (#32): the M1 owner identity is now the public
; handle of a real fixed-capacity application record. Window records retain
; compositor state and point back to one of these applications; several window
; slots may therefore share one code page and lifecycle.
MSX_APP_CODE_NATIVE equ #C310       ; primary code mapper segment
MSX_APP_CODE_PAGE   equ #C318       ; primary gb_page_t low byte
MSX_APP_CODE_GEN    equ #C320       ; primary gb_page_t generation
MSX_APP_WINDOW_COUNT equ #C328      ; live window slots owned by the app
MSX_APP_PRIMARY_WIN equ #C330       ; primary window slot, #FF when windowless
MSX_APP_FLAGS       equ #C338       ; published/root/terminating lifecycle flags
MSX_APP_SERVICE     equ #C340       ; app-owned shell service class
MSX_APP_ACCESSORY   equ #C348       ; app-owned exact Desk accessory ID
MSX_APP_WORKER_WIN  equ #C350       ; optional worker window slot, #FF if none
MSX_WIN_GEN         equ #C358       ; generation for each reused WM slot
MSX_APP_SLOT        equ #C360       ; lifecycle scratch: app/remaining count
MSX_WINDOW_HANDLE   equ #C361       ; lifecycle scratch: generation-tagged window
MSX_WINDOW_SLOT     equ #C363       ; lifecycle scratch: WM slot
MSX_CALLER_BANK     equ #C364       ; lifecycle scratch: caller mapper segment
MSX_APP_REMAIN      equ #C365       ; lifecycle scratch: remaining windows
MSX_APP_TABLE_END   equ #C366

; Architecture milestone 3 (#35): application-level deferred endpoints and a
; bounded FIFO. Queue records are sender owner, receiver owner, type, p0, p1,
; p2. The current record remains stable only while its handler is running.
MSX_DEFER_HANDLER_LO equ #C366       ; eight application handler low bytes
MSX_DEFER_HANDLER_HI equ #C36E       ; eight application handler high bytes
MSX_DEFER_COUNT      equ #C376       ; occupied FIFO records (0..8)
MSX_DEFER_BUSY       equ #C377       ; nonzero only during root-task delivery
MSX_DEFER_CURRENT    equ #C378       ; eight-byte record visible to the handler
MSX_DEFER_QUEUE      equ #C380       ; eight records x eight bytes
MSX_DEFER_SEND       equ #C3C0       ; six-byte sender/receiver/input scratch
MSX_DEFER_PURGE_OWNER equ #C3C6      ; owner matched by queue compaction
MSX_DEFER_INDEX      equ #C3C8       ; queue compaction cursor
MSX_DEFER_ACTIVATE   equ #C3C9       ; deferred focus request, #FF means none

; Architecture milestone 4 (#37): fixed marshalling, four owner-safe filesystem
; contexts and a private snapshot of the MSX-DOS directory FIB. GBFSCTX.MOD is
; paged at #6000, so all state that must survive its reloads remains here.
MSX_FSCTX_REQ          equ #C3D0       ; 32-byte request/result header
MSX_FSCTX_OP           equ MSX_FSCTX_REQ+0
MSX_FSCTX_STATUS       equ MSX_FSCTX_REQ+1
MSX_FSCTX_HANDLE       equ MSX_FSCTX_REQ+2
MSX_FSCTX_OWNER        equ MSX_FSCTX_REQ+4
MSX_FSCTX_DRIVE        equ MSX_FSCTX_REQ+6
MSX_FSCTX_FLAGS        equ MSX_FSCTX_REQ+7
MSX_FSCTX_LENGTH       equ MSX_FSCTX_REQ+8
MSX_FSCTX_ACTUAL       equ MSX_FSCTX_REQ+10
MSX_FSCTX_OFFSET       equ MSX_FSCTX_REQ+12 ; 32-bit little-endian
MSX_FSCTX_SIZE         equ MSX_FSCTX_REQ+16 ; 32-bit little-endian
MSX_FSCTX_ATTR         equ MSX_FSCTX_REQ+20
MSX_FSCTX_AUX          equ MSX_FSCTX_REQ+21
MSX_FSCTX_TRANSFER     equ #C400       ; one bounded 512-byte data/string transfer
MSX_FSCTX_TRANSFER_MAX equ 512
MSX_FSCTX_TABLE        equ #C600       ; four 144-byte private context records
MSX_FSCTX_RECORD_SIZE  equ 144
MSX_FSCTX_MAX          equ 4
MSX_FSCTX_PENDING      equ #C840       ; 64-byte pending launch-context transfer
MSX_FSCTX_DIAG         equ #C880       ; module/cleanup diagnostic counters
MSX_FSCTX_FIB          equ #C8A0       ; active MSX-DOS 2 64-byte directory FIB
MSX_ARCH_TABLE_END     equ #C8E0
; NOTE (#287 M1 debugging): DOS 2 / Nextor's kernel data occupies page 3 well
; below #F380 (the mapper jump table itself sits around #F200, jumping into
; code near #EC00) - the DOS 1 "system area starts at #F380" rule does NOT
; hold. The real TPA ceiling is the BDOS entry pointer at #0006/7: the stub
; sets SP from it, and everything fixed here stays at #C000..#C8FF, which the
; stub verifies is below that ceiling.
MSX_GLUE_TOP    equ   #C900        ; end of the fixed glue area (stub-verified < TPA top)
MSX_APP_FIXED_BOTTOM equ #CB00     ; first app-usable fixed RAM after 512B scheduler slot
