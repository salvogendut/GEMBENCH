# Read-only observation of a standalone DOS diagnostic, not Desktop acceptance.
set throttle off
set speed 9999
set ps_checks 0
set ps_opens {0 0 0 0 0 0}
set ps_reads {0 0 0 0 0 0}
set ps_closes {0 0 0 0 0 0}
proc ps_bytes {path} {
    set f [open $path rb]
    set data [read $f]
    close $f
    return $data
}
set ps_primary [ps_bytes $::env(GB_STREAM_PRIMARY)]
set ps_secondary [ps_bytes $::env(GB_STREAM_SECONDARY)]
proc ps_finish {status} {
    if {[info exists ::ps_finished]} {error "stream observer already finished"}
    set ::ps_finished 1
    set f [open $::env(GB_STREAM_RESULT) w]
    puts $f "STATUS=$status"
    puts $f "CHECKS=$::ps_checks"
    puts $f "OPENS=$::ps_opens"
    puts $f "READS=$::ps_reads"
    puts $f "CLOSES=$::ps_closes"
    puts $f "CASES=[peek 0x2033]"
    puts $f "LAST_LOAD_TICKS=[expr {[peek 0x2034]+256*[peek 0x2035]}]"
    close $f
    exit
    if {$status ne "PASS"} {error "stream observer stopped: $status"}
}
proc ps_check {condition message} {
    if {!$condition} {ps_finish "FAIL $message"}
    incr ::ps_checks
}
proc ps_dos {} {
    set ::ps_operation [reg C]
    set n [peek 0x2031]
    ps_check [expr {$n < 6}] "bad case index"
    switch -- [reg C] {
        67 {lset ::ps_opens $n [expr {[lindex $::ps_opens $n]+1}]}
        72 {lset ::ps_reads $n [expr {[lindex $::ps_reads $n]+1}]}
        69 {lset ::ps_closes $n [expr {[lindex $::ps_closes $n]+1}]}
        default {ps_finish "FAIL unexpected stream DOS operation"}
    }
    set ::pause off
}
proc ps_dos_return {} {
    if {[reg A]!=0} {puts stderr "STREAM_DOS case=[peek 0x2031] op=$::ps_operation error=[reg A] actual=[reg HL]"}
    set ::pause off
}
proc ps_secondary {} {
    ps_check [expr {[debug read_block memory 0x4000 16128] eq $::ps_secondary}] "secondary bytes"
    ps_check [expr {[debug read_block memory 0x7F00 256] eq [string repeat \x00 256]}] "secondary tail"
    set ::pause off
}
proc ps_cleanup {} {
    if {[peek 0x2031] in {0 5}} {
        ps_check [expr {[debug read_block memory 0x4000 16128] eq $::ps_primary}] "primary bytes"
    }
    set ::pause off
}
proc ps_done {} {
    ps_check [expr {[peek 0x2030]==85 && [peek 0x2033]==6}] "guest failed case=[peek 0x2031] load=[peek 0x2032] stage=[peek 0x203A]"
    ps_check [expr {$::ps_opens eq {1 1 1 1 1 1}}] "single-open identity"
    ps_check [expr {$::ps_reads eq {65 65 64 65 0 65}}] "stream read sequence"
    ps_check [expr {$::ps_closes eq {1 1 1 1 0 1}}] "stream closes"
    ps_finish PASS
}
debug set_bp $::env(GB_STREAM_DOS) {} ps_dos
debug set_bp $::env(GB_STREAM_DOS_RETURN) {} ps_dos_return
debug set_bp $::env(GB_STREAM_SECONDARY_ENTRY) {} ps_secondary
debug set_bp $::env(GB_STREAM_CLEANUP) {} ps_cleanup
debug set_bp $::env(GB_STREAM_DONE) {} ps_done
after time 180 {ps_finish "FAIL timeout"}
