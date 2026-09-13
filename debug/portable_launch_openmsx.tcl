# Ordinary Desktop input; all breakpoints/reads are observers, never guest calls.
source debug/portable_pages_openmsx.tcl
proc launch_bytes {path} {
    set f [open $path rb];set data [read $f];close $f;return $data
}
set launch_primary [launch_bytes $::env(GEOBENCH_LAUNCH_PRIMARY)]
set launch_secondary [launch_bytes $::env(GEOBENCH_LAUNCH_SECONDARY)]
set launch_case $::env(GEOBENCH_LAUNCH_CASE)
set launch_active 0
set launch_cycles 0
set launch_reports {}
proc launch_check {condition message} {if {!$condition} {fs_finish "FAIL launch $message"}}
proc launch_enter {} {
    set ::launch_active 1
    set ::launch_opens 0;set ::launch_reads 0;set ::launch_closes 0;set ::launch_banks 0
    set ::launch_tick [expr {[peek 0xFC9E]+256*[peek 0xFC9F]}]
    set ::launch_pointer [peek 0x1306]
    set ::launch_updates 0;set ::launch_moved 0;set ::launch_gap 0
    set ::launch_progress_tick $::launch_tick
    after time 0.5 {keymatrixdown 8 0x80}
    after time 2 {keymatrixup 8 0x80}
    set ::pause off
}
proc launch_progress {} {
    if {$::launch_active} {
        set now [expr {[peek 0xFC9E]+256*[peek 0xFC9F]}]
        set gap [expr {($now-$::launch_progress_tick)&65535}]
        if {$gap>$::launch_gap} {
            set ::launch_gap $gap
            puts stderr "PROGRESS_GAP ticks=$gap updates=$::launch_updates remaining=[peek 0xD0F7],[peek 0xD0F8]"
        }
        set ::launch_progress_tick $now
        incr ::launch_updates
        if {[peek 0x1306]!=$::launch_pointer} {set ::launch_moved 1}
        launch_check [expr {[peek 0x1340]!=0 && [peek 0x1342]==0}] root_serialization
    }
    set ::pause off
}
proc launch_dos {} {
    if {$::launch_active} {
        switch [reg C] {67 {incr ::launch_opens} 72 {incr ::launch_reads} 69 {incr ::launch_closes}}
    }
    set ::pause off
}
proc launch_bank {} {
    if {$::launch_active && [peek 0xD0E7]==1} {
        launch_check [expr {[debug read_block memory 0x4000 16128] eq $::launch_secondary}] secondary_bytes
        launch_check [expr {[debug read_block memory 0x7F00 256] eq [string repeat \x00 256]}] secondary_tail
        incr ::launch_banks
    }
    set ::pause off
}
proc launch_return {} {
    if {!$::launch_active} {set ::pause off;return}
    set ::launch_active 0
    set ok [expr {$::launch_case eq "good"}]
    set wanted [expr {$ok ? 0 : $::launch_case eq "short" ? 2 : 1}]
    launch_check [expr {[peek 0xD0E4]==2 && [peek 0xD0E5]==$wanted && ([reg F]&1)==$ok}] status
    launch_check [expr {$::launch_opens==1 && $::launch_closes==1}] single_open_close
    set reads [expr {1+([string length $::launch_primary]-256+511)/512+32+($::launch_case ne "short")}]
    launch_check [expr {$::launch_reads==$reads && $::launch_banks==$ok}] stream_reads
    launch_check [expr {[peek 0xD0E7]==0 && [peek 0xD0FD]==0 && [peek 0xD0FF]==0}] stream_cleanup
    if {$ok} {
        launch_check [expr {[debug read_block memory 0x4000 [string length $::launch_primary]] eq $::launch_primary}] primary_bytes
    }
    launch_check [expr {$::launch_moved && $::launch_updates>50 && $::launch_gap<=6}] "pointer_progress moved=$::launch_moved updates=$::launch_updates gap=$::launch_gap"
    set ticks [expr {([peek 0xFC9E]+256*[peek 0xFC9F]-$::launch_tick)&65535}]
    lappend ::launch_reports [list $::launch_opens $::launch_reads $::launch_closes $ticks $::launch_updates $::launch_gap]
    incr ::launch_cycles
    puts stderr "LAUNCH $::launch_case cycle=$::launch_cycles opens=$::launch_opens reads=$::launch_reads closes=$::launch_closes ticks=$ticks"
    if {!$ok} {after time 2 launch_rejected}
    set ::pause off
}
proc launch_rejected {} {
    if {[peek 0x403]!=71 || [peek 0x404]!=66} {after time 0.02 launch_rejected;return}
    launch_check [expr {[peek 0x1350]==1 && [peek 0xC2E5]==$::page_free_baseline &&
        [debug read_block memory 0xC220 32] eq $::page_baseline}] owner_rollback
    launch_check [expr {[peek 0xD0E4]==0 && [peek 0xD0E3]==0 && [peek 0x1347]==0}] return_state
    if {$::launch_cycles==3} {fs_finish PASS;return}
    fs_move 11 4 {fs_click {fs_move 12 14 {fs_click {}}}}
}
rename fs_finish fs_finish_launch_parent
proc fs_finish {status} {
    if {$status eq "PASS" && $::launch_cycles!=3} {set status "FAIL incomplete launch cycles"}
    puts stderr "LAUNCH_REPORTS=$::launch_reports"
    fs_finish_launch_parent $status
}
# Guard low addresses against BIOS ROM aliases. The high fixed module flag is
# not enough on its own to establish which code is executing in page zero.
set launch_guard {[peek 0x403]==71 && [peek 0x404]==66 && [peek 0x405]==86 && [peek 0x406]==52}
debug set_bp $::env(GEOBENCH_LAUNCH_MSX_APP_LOAD) $launch_guard launch_enter
debug set_bp $::env(GEOBENCH_LAUNCH_MSX_APP_RETURN) $launch_guard launch_return
debug set_bp $::env(GEOBENCH_LAUNCH_PKG_SECONDARY_ENTRY) $launch_guard launch_bank
debug set_bp $::env(GEOBENCH_LAUNCH_MSX_APP_PROGRESS_UPDATED) $launch_guard launch_progress
debug set_bp 5 $launch_guard launch_dos
