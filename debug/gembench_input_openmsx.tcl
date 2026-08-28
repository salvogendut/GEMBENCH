# Drive the diagnostic input-response probe with real MSX matrix events.
# The guest sets bit 0 at C02E after the repaint probes and three-task stress
# setup are complete, bit 1 after a changed pointer position reaches the VDP
# sprite table, and bit 2 after the desktop draws the typed-key acknowledgement.

set throttle off
set pause_on_lost_focus false
set pause off

set input_output $::env(GEMBENCH_INPUT_OUTPUT)
set input_status "not started"
set input_deadline 60.0
set pointer_deadline 0
set keyboard_deadline 0
set pointer_inject_time 0
set pointer_ack_time 0
set keyboard_inject_time 0
set keyboard_ack_time 0
set pointer_before_x 0
set pointer_before_y 0
set pointer_after_x 0
set pointer_after_y 0

proc input_word {address} {
    return [expr {[peek $address] | ([peek [expr {$address + 1}]] << 8)}]
}

proc input_write_result {status} {
    set handle [open $::input_output w]
    puts $handle "STATUS=$status"
    puts $handle [format "POINTER_RESPONSE_MS=%.3f" \
        [expr {($::pointer_ack_time - $::pointer_inject_time) * 1000.0}]]
    puts $handle [format "KEYBOARD_RESPONSE_MS=%.3f" \
        [expr {($::keyboard_ack_time - $::keyboard_inject_time) * 1000.0}]]
    puts $handle "POINTER_BEFORE_X=$::pointer_before_x"
    puts $handle "POINTER_BEFORE_Y=$::pointer_before_y"
    puts $handle "POINTER_AFTER_X=$::pointer_after_x"
    puts $handle "POINTER_AFTER_Y=$::pointer_after_y"
    puts $handle [format "INPUT_FLAGS=%d" [peek 0xC02E]]
    puts $handle [format "INPUT_KEY=%d" [peek 0xC02F]]
    puts $handle [format "RUNNABLE_TASKS=%d" [peek 0xC056]]
    puts $handle [format "STACK_MAX=%d" [peek 0xC02B]]
    puts $handle [format "STACK_FAULT=%d" [peek 0xC02C]]
    puts $handle [format "PROBE_PHASE=%d" [peek 0xC02A]]
    puts $handle [format "POINTER_ARM_TICK=%d" [input_word 0xC04E]]
    puts $handle [format "POINTER_ACK_TICK=%d" [input_word 0xC050]]
    puts $handle [format "KEYBOARD_ARM_TICK=%d" [input_word 0xC052]]
    puts $handle [format "KEYBOARD_ACK_TICK=%d" [input_word 0xC054]]
    close $handle
}

proc input_finish {status} {
    catch {keymatrixup 8 0x10}
    catch {keymatrixup 2 0x80}
    input_write_result $status
    exit
}

proc input_wait_keyboard {} {
    if {[peek 0xC02D] == 0xB7 && ([peek 0xC02E] & 4)} {
        set ::keyboard_ack_time [machine_info time]
        keymatrixup 2 0x80
        if {[peek 0xC02F] != 98} {
            input_finish "FAIL keyboard value is not lowercase b"
        } elseif {[peek 0xC02C] != 0} {
            input_finish "FAIL scheduler stack fault"
        } else {
            input_finish PASS
        }
    } elseif {[machine_info time] >= $::keyboard_deadline} {
        input_finish "TIMEOUT waiting for keyboard acknowledgement"
    } else {
        after time 0.00025 input_wait_keyboard
    }
}

proc input_inject_keyboard {} {
    set ::keyboard_inject_time [machine_info time]
    set ::keyboard_deadline [expr {$::keyboard_inject_time + 2.0}]
    keymatrixdown 2 0x80
    after time 0.00025 input_wait_keyboard
}

proc input_confirm_pointer {} {
    set ::pointer_after_y [vpeek 0xFA00]
    set ::pointer_after_x [vpeek 0xFA01]
    if {$::pointer_before_x == $::pointer_after_x &&
        $::pointer_before_y == $::pointer_after_y} {
        input_finish "FAIL pointer acknowledgement had no visible sprite movement"
    } else {
        after time 0.04 input_inject_keyboard
    }
}

proc input_wait_pointer {} {
    if {[peek 0xC02D] == 0xB7 && ([peek 0xC02E] & 2)} {
        set ::pointer_ack_time [machine_info time]
        keymatrixup 8 0x10
        # The guest flag is written immediately after the VDP port writes. Give
        # openMSX a short observation interval before checking the VRAM table.
        after time 0.005 input_confirm_pointer
    } elseif {[machine_info time] >= $::pointer_deadline} {
        input_finish "TIMEOUT waiting for pointer acknowledgement"
    } else {
        after time 0.00025 input_wait_pointer
    }
}

proc input_inject_pointer {} {
    set ::pointer_before_y [vpeek 0xFA00]
    set ::pointer_before_x [vpeek 0xFA01]
    set ::pointer_inject_time [machine_info time]
    set ::pointer_deadline [expr {$::pointer_inject_time + 2.0}]
    keymatrixdown 8 0x10
    after time 0.00025 input_wait_pointer
}

proc input_wait_armed {} {
    if {[peek 0xC02D] == 0xB7 &&
        [peek 0xC02A] == 4 &&
        ([peek 0xC02E] & 7) == 1 &&
        [peek 0xC056] == 3 &&
        [peek 0xC02C] == 0} {
        input_inject_pointer
    } elseif {[machine_info time] >= $::input_deadline} {
        input_finish "TIMEOUT waiting for three-task input arm"
    } else {
        after time 0.01 input_wait_armed
    }
}

after time 5.0 input_wait_armed
