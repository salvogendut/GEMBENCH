; ---------------------------------------------------------------------------
; lib/config.asm - GEOBENCH configuration file.
;
; Reads GEOBENCH.CFG (KEY=VALUE, one per line, '#' comments, CR/LF endings) off
; the active storage via fs_load_file, and parses known keys into cfg_* vars.
; Missing file or missing key -> the built-in default is kept.
;
; Settings:
;   cfg_icons   icon-set name (default "DEFAULT")   <- key ICONS
;
; Requires lib/fs.asm (fs_load_file, fs_req_name, fs_load_dst, fs_ent_size).
; ---------------------------------------------------------------------------

CFG_BUF_SZ      equ   512

; cfg_load: apply defaults, then load + parse GEOBENCH.CFG if it exists.
cfg_load
                ld    hl,cfg_def_icons       ; default ICONS = "DEFAULT"
                ld    de,cfg_icons
                ld    bc,9
                ldir

                ld    hl,cfg_fname           ; fs_req_name = "GEOBENCH.CFG"
                ld    de,fs_req_name
                ld    bc,11
                ldir
                ld    hl,cfg_buf
                ld    (fs_load_dst),hl
                call  fs_load_file
                ret   nc                      ; no config file -> keep defaults

                ld    hl,cfg_buf             ; parse fs_ent_size bytes
                ld    bc,(fs_ent_size)
                ; fall through

; cfg_parse: HL = text, BC = byte count. Walk lines; apply known KEY=VALUE.
cfg_parse
cfgp_line
                ld    a,b
                or    c
                ret   z                       ; consumed everything
                ld    a,(hl)
                cp    13
                jr    z,cfgp_eateol
                cp    10
                jr    z,cfgp_eateol
                cp    '#'
                jr    z,cfgp_skipline         ; comment

                push  hl                       ; try the known keys at this line
                push  bc
                ld    de,key_icons
                call  cfg_keymatch
                jr    nc,cfgp_nomatch
                ld    de,cfg_icons            ; ICONS= matched
                ld    a,8                      ; filename stem, max 8 chars
                call  cfg_copyval
cfgp_nomatch
                pop   bc
                pop   hl
cfgp_skipline                                  ; advance to the line's CR/LF
                ld    a,b
                or    c
                ret   z
                ld    a,(hl)
                cp    13
                jr    z,cfgp_eateol
                cp    10
                jr    z,cfgp_eateol
                inc   hl
                dec   bc
                jr    cfgp_skipline
cfgp_eateol                                    ; eat one or more CR/LF
                ld    a,b
                or    c
                ret   z
                ld    a,(hl)
                cp    13
                jr    z,cfgp_eat1
                cp    10
                jr    z,cfgp_eat1
                jr    cfgp_line
cfgp_eat1
                inc   hl
                dec   bc
                jr    cfgp_eateol

; cfg_keymatch: HL = line, DE = key template (e.g. "ICONS=",0). If the line
; starts with the template, CF set and HL points at the value; else NC.
cfg_keymatch
                ld    a,(de)
                or    a
                jr    z,ckm_yes               ; template exhausted -> match
                ld    a,(de)
                cp    (hl)
                jr    nz,ckm_no
                inc   hl
                inc   de
                jr    cfg_keymatch
ckm_yes
                scf
                ret
ckm_no
                or    a
                ret

; cfg_copyval: copy the value at (HL) to (DE), up to A chars, stopping at
; CR/LF/NUL; NUL-terminates the destination.
cfg_copyval
                ld    b,a
ccv_loop
                ld    a,b
                or    a
                jr    z,ccv_end
                ld    a,(hl)
                or    a
                jr    z,ccv_end
                cp    13
                jr    z,ccv_end
                cp    10
                jr    z,ccv_end
                ld    (de),a
                inc   hl
                inc   de
                dec   b
                jr    ccv_loop
ccv_end
                xor   a
                ld    (de),a
                ret

; --- data ----------------------------------------------------------------
cfg_fname       db    "GEOBENCHCFG"      ; "GEOBENCH.CFG" (8.3)
key_icons       db    "ICONS=",0
cfg_def_icons   db    "DEFAULT",0,0      ; 9 bytes
cfg_icons       defs  9                  ; parsed icon-set name (NUL-terminated)
cfg_buf         defs  CFG_BUF_SZ
