; kernel/config_module.asm - boot-time GEOBENCH.CFG parser module runner.

; --- config (C kernel module) --------------------------------------------
; cfg_boot: seed defaults, load GEOBENCH.CFG into the transfer area, then run the
; GBCFG C module (paged into a bank) to parse it into KCFG_ICONS / KCFG_FONT.
; Absent file -> length 0 -> the parser is a no-op and the defaults stand.
cfg_boot
                ld    hl,0                    ; default: no config text (module then
                ld    (KCFG_LEN),hl           ; emits the DEFAULT names itself)
                ld    a,2                     ; default frame uses Edge; GBCFG may choose
                ld    (KCFG_FRAMEPEN),a       ; Text/Accent when Edge matches Paper
                ld    hl,cfg_fname           ; fs_req_name = "GEOBENCH.CFG"
                ld    de,fs_req_name
                call  copy11
                ld    hl,#0200               ; cfg text buffer is 512 bytes
                ld    (fs_load_max),hl
                ld    hl,KCFG_TEXT
                ld    (fs_load_dst),hl
                call  fs_load_file
                jr    nc,cfgb_run            ; no file -> KCFG_LEN stays 0
                ld    hl,(fs_ent_size)        ; file <512 so the low word is the size
                ld    (KCFG_LEN),hl
cfgb_run
                jp    run_cfgmod
cfg_fname       db    "GEOBENCHCFG"          ; "GEOBENCH.CFG" (8.3)

; run_cfgmod: load GBCFG.BIN into PAGE_APP0 and CALL it (it parses the transfer
; area). Runs under DI (the module needs no interrupts) with no top-bar/ESC
; handling - this is boot time.
; load_app0: HL = 11-byte 8.3 name -> map PAGE_APP0 and load /GEOBENCH/<name> into
; APP_BASE (max APP_LOAD_MAX). Returns with CF from fs_load_sys (set = loaded). The CALLER
; saves/restores its page and handles DI/EI. Shared by run_cfgmod + boot_splash (#196).
load_app0
                ld    de,fs_req_name
                call  copy11
                ifdef PLATFORM_MSX
                ld    a,(MSX_TPASEG)          ; #287: APP_PAGES[0] = the TPA page-1 segment
                else
                ld    a,PAGE_APP0
                endif
                call  bank_set
                ld    hl,APP_LOAD_MAX
                ld    (fs_load_max),hl
                ld    hl,APP_BASE
                ld    (fs_load_dst),hl
                jp    fs_load_sys           ; #134: system files live in the /GEOBENCH dir

run_cfgmod
                ld    a,(bank_cur)           ; save the current page
                push  af
                di
                ld    hl,cfgmod_name
                call  load_app0
                jr    nc,rcm_done            ; module missing -> keep defaults
                call  APP_BASE               ; crt0 _start -> main -> gb_cfg_parse
rcm_done
                pop   af                       ; restore the caller's page
                call  bank_set
                ei
                ret
cfgmod_name     db    "GBCFG   MOD"          ; 8.3, space-padded
