;; gbtask.s - opt-in preemptive worker registration (#477).
;; Kept separate so ordinary applications pay no bytes for the experimental API.
        .module gbtask
        .globl  _gb_task_enable

        .area   _CODE
_gb_task_enable::
        xor     a               ; operation 0: register the focused worker
        jp      0x804B          ; GB_TASKENABLE (legacy GB_ONEVENT slot)
