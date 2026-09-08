; Frozen native shell service bindings. The shared policy is root-serialized;
; ordinary APP callbacks (including Calculator) run there, not on workers.
WM_SHELL_MASK equ #E0
WM_FR_ARG equ 14
WM_DRAGNAME equ #1423
SHELL_BUSY equ #133E
GB_MSG_SHELL equ 11
                assert SHELL_BUSY+1<=SCHED_LOCK,"shell/scheduler state overlap"
                assert WM_Z+CPC_WINDOW_MAX<=WM_DRAGNAME,"shell argument/z-order overlap"
                assert WM_DRAGNAME+11<=CORE_LEGACY_BUSY,"shell argument/legacy banks overlap"
cpc_shell
                push af
                ld a,(SCHED_CURRENT)
                or a
                jr nz,cpc_shell_worker
                pop af
                jp k_shell
cpc_shell_worker
                pop af
                ld a,GB_SHELL_BUSY_RES
                ret
