# Portable GBRDEMO extension of the established real File Manager workflow.
# The base script supplies keyboard-matrix pointer motion and association launch;
# this layer checks app-owned state and exact cleanup for valid/invalid fixtures.
source debug/gbr_object_openmsx.tcl

set ug_case $::env(GEMBENCH_GBR_CASE)
set ug_ready [expr {$::env(GEMBENCH_GBR_READY)}]
set ug_states [expr {$::env(GEMBENCH_GBR_STATES)}]
set ug_close_deadline 0
set ug_capture_deadline 0

# The 13 KiB compile-once package performs a real CRC admission pass before its
# entry can run.  Select with the first click, launch with the second, then let
# that synchronous gate finish instead of queuing more pointer clicks into it.
rename gbr_resource_click ug_legacy_resource_click
proc gbr_resource_click {} {
    incr ::gbr_resource_clicks
    set delay [expr {$::gbr_resource_clicks == 2 ? 12.0 : 0.75}]
    gbr_single_click gbr_resource_click_check $delay
}

proc ug_transaction_clean {} {
    if {[peek 0xC840]} {return 0}
    for {set address 0x1485} {$address < 0x1490} {incr address} {
        if {[peek $address]} {return 0}
    }
    return 1
}

rename gbr_capture ug_base_capture
proc gbr_capture {} {
    if {!$::ug_capture_deadline} {
        set ::ug_capture_deadline [expr {[machine_info time] + 10.0}]
    }
    if {([peek 0x1350] > 8 || [peek 0x1351] > 7) &&
        [machine_info time] < $::ug_capture_deadline} {
        after time 0.02 gbr_capture
        return
    }
    set want [expr {$::ug_case eq "good"}]
    set ready [peek $::ug_ready]
    set state [expr {[peek [expr {$::ug_states+4}]]+256*[peek [expr {$::ug_states+5}]]}]
    if {$ready != $want} {gbr_finish "FAIL ready=$ready expected=$want";return}
    if {$state != ($want ? 10 : 0)} {gbr_finish "FAIL state=$state";return}
    if {![ug_transaction_clean]} {
        gbr_finish "FAIL launch transaction residue";return
    }
    # Renderer-none is intentional for the automated state/cleanup matrix;
    # rendered screenshots are optional manual evidence.
    catch {screenshot -raw $::gbr_screenshot}
    set ::ug_close_deadline [expr {[machine_info time] + 10.0}]
    keymatrixdown 7 0x04
    after time 0.08 ug_close_release
}

proc ug_close_release {} {
    keymatrixup 7 0x04
    after time 2 ug_close_check
}

proc ug_close_check {} {
    set windows [peek 0x1350]
    set focus [peek 0x1351]
    # BIOS calls briefly map ROM over the low-RAM WM cells.  Sample only a
    # plausible settled root state, as the established pointer driver does.
    if {($windows > 8 || $focus > 7) &&
        [machine_info time] < $::ug_close_deadline} {
        after time 0.02 ug_close_check
        return
    }
    if {$windows != 2 || ![ug_transaction_clean]} {
        gbr_finish "FAIL close/transaction cleanup";return
    }
    gbr_finish PASS
}

if {$ug_case ne "good"} {
    rename gbr_resource_click_check ug_good_resource_click_check
    proc gbr_resource_click_check {} {
        if {$::gbr_entry_seen} {
            after time 12.0 gbr_capture
        } elseif {$::gbr_resource_clicks >= 6} {
            gbr_finish "FAIL GBRDEMO entry was not reached"
        } else {
            gbr_resource_click
        }
    }
}
