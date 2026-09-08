; Boot-only sysinfo construction, resident in GBAPV4.MOD. A = video mode.
module_sysinfo_init
                ld    (MSX_SYS_VIDEO_MODE),a
                ld    a,MSX_SYSINFO_SIZE
                ld    (MSX_SYS_SIZE),a
                ld    a,GB_SYSINFO_V6
                ld    (MSX_SYS_VERSION),a
                ld    a,1                     ; frozen GEMBENCH-1 ABI
                ld    (MSX_SYS_ABI_MAJOR),a
                xor   a
                ld    (MSX_SYS_ABI_MINOR),a
                ld    a,GB_PLATFORM_MSX2
                ld    (MSX_SYS_PLATFORM),a
                ld    a,(MSX_SYS_VIDEO_MODE)
                cp    7
                ld    a,GB_PACKING_4BPP
                ld    b,16
                jr    z,msi_packing
                ld    a,GB_PACKING_2BPP
                ld    b,4
msi_packing     ld    (MSX_SYS_PACKING),a
                ld    a,b
                ld    (MSX_SYS_COLOURS),a
                ld    hl,512
                ld    (MSX_SYS_WIDTH),hl
                ld    hl,212
                ld    (MSX_SYS_HEIGHT),hl
                ld    a,(MSX_TOTSEG)
                ld    (MSX_SYS_MEM_PAGES),a
                ld    a,(MSX_PAGE_TOTAL)
                ld    (MSX_SYS_POOL_TOTAL),a
                ld    a,(MSX_PAGE_FREE)
                ld    (MSX_SYS_POOL_FREE),a
                ld    a,WM_MAXWIN
                ld    (MSX_SYS_MAX_WINDOWS),a
                ld    hl,GB_CAPS_MSX_M4
                ld    (MSX_SYS_CAPS),hl
                ld    hl,0
                ld    (MSX_SYS_RESERVED),hl
                ld    a,GB_APP_MAX
                ld    (MSX_SYS_MAX_APPS),a
                ld    a,1
                ld    (MSX_SYS_APP_VERSION),a
                ld    a,WM_MAXWIN
                ld    (MSX_SYS_MAX_APP_WINDOWS),a
                xor   a
                ld    (MSX_SYS_RESERVED2),a
                ld    a,GB_DEFER_MAX
                ld    (MSX_SYS_MSG_QUEUE),a
                ld    a,4
                ld    (MSX_SYS_MSG_INLINE),a
                ld    a,1
                ld    (MSX_SYS_MSG_VERSION),a
                xor   a
                ld    (MSX_SYS_RESERVED3),a
                ld    hl,MSX_FSCTX_MAX         ; max contexts, transfer low byte (0)
                ld    (MSX_SYS_FS_CONTEXTS),hl
                ld    hl,#0102                 ; transfer high byte (512), API v1
                ld    (MSX_SYS_FS_TRANSFER+1),hl
                ld    hl,GB_CAPS_HIGH_MSX_V6
                ld    (MSX_SYS_CAPS_HIGH),hl
                ld    a,128
                ld    (MSX_SYS_COLUMNS),a
                ld    a,212
                ld    (MSX_SYS_LINES),a
                ld    a,4
                ld    (MSX_SYS_PIXELS_COLUMN),a
                ld    (MSX_SYS_SEMANTIC_PENS),a
                ld    hl,APP_BASE
                ld    (MSX_SYS_APP_BASE),hl
                ld    hl,#7F00
                ld    (MSX_SYS_APP_LIMIT),hl
                ld    hl,GB_KERNEL
                ld    (MSX_SYS_KERNEL_BASE),hl
                ld    a,2
                ld    (MSX_SYS_UNIVERSAL_MAJOR),a
                ld    a,1
                ld    (MSX_SYS_UNIVERSAL_MINOR),a
                ld    a,3
                ld    (MSX_SYS_UNIVERSAL_PROFILE),a
                xor   a
                ld    (MSX_SYS_RESERVED4),a
                ld    hl,MSX_SYSINFO
                ld    de,MSX_SYSINFO_LEGACY
                ld    bc,MSX_SYSINFO_SIZE
                ldir
                xor   a
                ld    (MSX_SYSINFO_LEGACY+45),a
                ld    a,GB_CAPS_HIGH_MSX_V6 & #7F
                ld    (MSX_SYSINFO_LEGACY+32),a

                ; Preserve the old page-3 map as an unpublished v5 shadow.
                ld    hl,MSX_SYSINFO
                ld    de,MSX_SYSINFO_V5_SHADOW
                ld    bc,MSX_SYSINFO_V5_SIZE
                ldir
                ld    a,MSX_SYSINFO_V5_SIZE
                ld    (MSX_SYSINFO_V5_SHADOW),a
                ld    a,GB_SYSINFO_V5
                ld    (MSX_SYSINFO_V5_SHADOW+1),a
                xor   a                     ; root context before scheduler install;
                ld    (SCHED_CURRENT),a       ; also defined in cooperative builds
                ret

; Original ABI 2.0 CRTs test universal minor==0, not >=required. Keep their
; immutable compatibility view separate, so querying from an old application
; never changes what new applications observe. Native v1-v3 callers retain
; the canonical v6 record and its unchanged legacy prefix.
module_sysinfo_query
                ld    a,(MSX_PAGE_FREE)
                ld    (MSX_SYS_POOL_FREE),a
                ld    (MSX_SYSINFO_LEGACY+14),a
                ld    de,MSX_SYSINFO
                ld    a,(APP_BASE)
                cp    #C3
                ret   nz
                ld    hl,(APP_BASE+3)
                ld    bc,#4247
                or    a
                sbc   hl,bc
                ret   nz
                ld    hl,(APP_BASE+5)
                ld    bc,#5041
                or    a
                sbc   hl,bc
                ret   nz
                ld    a,(APP_BASE+7)
                cp    4
                ret   nz
                ld    hl,(APP_BASE+14)
                ld    a,h
                or    a
                ret   nz
                ld    a,l
                cp    24
                jr    z,msq_manifest
                cp    32
                ret   nz
msq_manifest    ld    bc,APP_BASE+8
                add   hl,bc
                ld    a,(hl)
                cp    2
                ret   nz
                inc   hl
                ld    a,(hl)
                or    a
                ret   nz
                ld    de,MSX_SYSINFO_LEGACY
                ret
