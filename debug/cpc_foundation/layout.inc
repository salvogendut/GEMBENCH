; Step 3A diagnostic map, NOT a new release ABI. All endpoints are exclusive.
; Mode 1 is set by firmware BEFORE takeover. Afterwards there are no firmware
; calls, no scheduling, no ROM-resident execution and no banked stack.
                ifndef FOUNDATION_ORG
FOUNDATION_ORG  equ #8000
                endif
                ifndef FOUNDATION_STATE
FOUNDATION_STATE equ #9800
                endif
                ifndef FOUNDATION_IRQ_STACK
FOUNDATION_IRQ_STACK equ #9A10
                endif
                ifndef FOUNDATION_MAIN_STACK
FOUNDATION_MAIN_STACK equ #9C10
                endif
FOUNDATION_STACK_SIZE equ #0100
FOUNDATION_SCREEN equ #C000
FOUNDATION_SCREEN_END equ #10000
FOUNDATION_WINDOW equ #4000
FOUNDATION_WINDOW_END equ #8000
FOUNDATION_ROUNDS equ 50

                assert FOUNDATION_ORG >= #8000, "code must be fixed RAM"
                assert FOUNDATION_ORG < FOUNDATION_STATE, "code/state overlap"
                assert FOUNDATION_STATE+#0100 <= FOUNDATION_IRQ_STACK-16, "state/IRQ stack overlap"
                assert FOUNDATION_IRQ_STACK+FOUNDATION_STACK_SIZE+16 <= FOUNDATION_MAIN_STACK-16, "stack overlap"
                assert FOUNDATION_MAIN_STACK+FOUNDATION_STACK_SIZE+16 <= #A000, "probe must not occupy firmware workspace"
