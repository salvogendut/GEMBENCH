; Optional filesystem-v3 launch transaction. Fixed resident code, no I/O.
; Pending states: 0 empty, 1 prepared (producer owner), 2 selected by launcher,
; 3 bound (recipient owner). The owner includes its generation. No raw context
; or native directory-entry pointer crosses into the receiving application.
;
; Bindings: DOC_PENDING (64-byte record), DOC_CURRENT_OWNER, DOC_LAUNCH_BODY,
; DOC_LAUNCH_ARG, DOC_COPY_NAME, DOC_RELEASING_OWNER, DOC_WORKER.
document_launch
                call document_prepared_here
                jp nc,DOC_LAUNCH_BODY
                ld a,2
                ld (DOC_PENDING),a
                ld hl,DOC_PENDING+4
                ld de,DOC_LAUNCH_ARG
                call DOC_COPY_NAME
                call DOC_LAUNCH_BODY
                ; A successful adopter may already have prepared another
                ; request. Only the selected/bound transaction expires here.
                ld a,(DOC_PENDING)
                cp 2
                ret c
document_clear
                xor a
                ld (DOC_PENDING),a
                ret

; Called immediately after allocating the launch owner, before page allocation.
; Preserve DE for the application's page allocator.
document_bind
                ld a,(DOC_PENDING)
                cp 2
                ret nz
                ld (DOC_PENDING+1),de
                ld a,3
                ld (DOC_PENDING),a
                ret

; Early public-launch rejection must not strand the producer's preparation.
; Worker calls must not cancel a root transaction belonging to the same app.
document_reject
                push hl
                call document_prepared_here
                call c,document_clear
                pop hl
                or a
                ret

document_prepared_here
                ld a,(DOC_WORKER)
                or a
                ret nz
                ld a,(DOC_PENDING)
                cp 1
                jr nz,document_not_here
                push hl
                call DOC_CURRENT_OWNER
                ld hl,(DOC_PENDING+1)
                or a
                sbc hl,de
                pop hl
                jr nz,document_not_here
                scf
                ret
document_not_here
                or a
                ret

; Tail of resident context cleanup; does not depend on loading GBFSCTX.MOD.
document_owner_cleanup
                ld hl,(DOC_RELEASING_OWNER)
                ld de,(DOC_PENDING+1)
                or a
                sbc hl,de
                ret nz
                jp document_clear
