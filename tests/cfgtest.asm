; cfgtest - load and parse GEOBENCH.CFG via the real lib/config.asm + fs stack,
; then print the parsed ICONS value (should be "NEON" from the test config, not
; the built-in default "DEFAULT").

SCR_SET_MODE    equ   #BC0E
TXT_OUTPUT      equ   #BB5A

                org   #4000
start
                ld    a,1
                call  SCR_SET_MODE
                call  fs_init                 ; select storage backend (IDE present)
                call  cfg_load                ; load + parse GEOBENCH.CFG

                ld    hl,msg
                call  puts
                ld    hl,cfg_icons
                call  puts
done            jr    done

puts            ld    a,(hl)
                or    a
                ret   z
                push  hl
                call  TXT_OUTPUT
                pop   hl
                inc   hl
                jr    puts

msg             db    "ICONS=",0

                include "../lib/fs.asm"
                include "../lib/fs_ide_fat.asm"
                include "../lib/fs_amsdos.asm"
                include "../lib/config.asm"
prog_end
                save  "CFGTEST",start,prog_end-start,DSK,"build/cfgtest.dsk"
                save  "build/CFGTEST.RAW",start,prog_end-start
