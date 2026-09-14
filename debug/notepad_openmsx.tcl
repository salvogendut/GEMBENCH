# Actual editor via real Desk and keyboard input; debugger observations only.
source debug/portable_fs_openmsx.tcl
set np_view $::env(GEOBENCH_NOTEPAD_VIEW)
set np_registered 0
set np_picker $::env(GEOBENCH_NOTEPAD_PICKER)
proc np_low_ready {} {expr {[peek 0x403]==71 && [peek 0x404]==66}}
# DOS calls temporarily map ROM over the low-RAM observations. Never steer the
# pointer from ROM bytes, and hold keyboard-pointer fire until a real poll sees
# it (a fixed short pulse can be wholly hidden by an in-progress paint).
rename fs_move_tick np_move_tick
proc fs_move_tick {} {
    if {![np_low_ready]} {after time 0.002 fs_move_tick;return}
    keymatrixdown 6 2
    np_move_tick
}
proc fs_click {callback} {
    set ::np_click_deadline [expr {[machine_info time]+3}]
    keymatrixdown 8 1
    after time 0.02 [list np_click_polled $callback]
}
proc np_click_polled {callback} {
    if {[np_low_ready] && ([peek 0x1308]&4)} {
        keymatrixup 8 1
        keymatrixup 6 2
        after time 0.9 $callback
    } elseif {[machine_info time]>$::np_click_deadline} {
        keymatrixup 8 1
        keymatrixup 6 2
        fs_finish "FAIL Notepad click was not polled"
    } else {after time 0.02 [list np_click_polled $callback]}
}
proc np_check {condition message} {
    if {!$condition} {
        puts stderr "NOTEPAD mode=[peek $::fs_state] picker=[peek [expr {$::np_picker+8}]] windows=[peek 0x1350] focus=[peek 0x1351] pointer=[peek 0x1306],[peek 0x1307]"
        catch {screenshot -raw [file rootname $::fs_output].png}
        fs_finish "FAIL Notepad $message"
    }
}
proc np_word {at} {expr {[peek $at]+256*[peek [expr {$at+1}]]}}
proc np_mapped {} {expr {[peek 0x1350]==2 && [peek 0x1351]==1 &&
    [peek 0x403]==71 && [peek 0x404]==66 &&
    [peek 0x4003]==71 && [peek 0x4007]==4}}
proc fs_window {} {
    if {$::fs_entered && !$::np_registered} {
        set ::np_registered 1
        after time 3 np_opened
    }
    set ::pause off
}
proc np_opened {} {
    if {![np_mapped]} {after time 0.002 np_opened;return}
    np_check [expr {[peek 0x1350]==2 && [peek 0x1351]==1 && [peek $::fs_state]==0}] opened
    np_check [expr {[np_word $::np_view]==0}] empty
    set ::np_damage_watch [debug set_bp 0x80B4 {
        [np_mapped] && [reg DE]>255
    } {
        set height [expr {[reg DE]>>8}]
        if {$height>14} {fs_finish "FAIL typing requested full-client damage"}
        set ::pause off
    }]
    np_type {{2 64} {2 128} {3 1} {7 128}} np_edited
}
proc np_type {keys callback} {
    if {![llength $keys]} {after time 1 $callback;return}
    lassign [lindex $keys 0] row mask
    keymatrixdown $row $mask
    after time 0.12 [list keymatrixup $row $mask]
    after time 0.3 [list np_type [lrange $keys 1 end] $callback]
}
proc np_edited {} {
    if {![np_mapped]} {after time 0.002 np_edited;return}
    np_check [expr {[np_word $::np_view]==4 && [peek [expr {$::np_view+13}]]==1}] edited
    puts stderr "NOTEPAD edited through real keyboard"
    debug remove_bp $::np_damage_watch
    set ::np_pointer [list [peek 0x1306] [peek 0x1307]]
    np_type {{8 32} {8 128} {8 64} {8 16} {8 128} {8 1} {7 32}} np_navigated
}
proc np_navigated {} {
    if {![np_mapped]} {after time 0.002 np_navigated;return}
    np_check [expr {[np_word $::np_view]==4 && [np_word [expr {$::np_view+2}]]==4}] arrows_and_space
    np_check [expr {$::np_pointer eq [list [peek 0x1306] [peek 0x1307]]}] keyboard_did_not_move_pointer
    puts stderr "NOTEPAD arrows/Space/backspace passed without moving pointer"
    catch {screenshot -raw [file rootname $::fs_output]-editing.png}
    # File -> Save As, then the real chooser's name editor.
    fs_move 11 4 {fs_click {fs_move 12 44 {fs_click np_save_picker}}}
}
proc np_save_picker {} {
    if {![np_mapped]} {after time 0.002 np_save_picker;return}
    if {[peek $::fs_state]==1 && [peek [expr {$::np_picker+8}]]<5} {after time 0.2 np_save_picker;return}
    np_check [expr {[peek $::fs_state]==1 && [peek [expr {$::np_picker+8}]]==5}] save_picker
    np_type {{5 1} {2 64} {5 8} {3 4} {3 2} {2 8} {5 2} {5 32} {5 2} {7 128}} np_overwrite
}
proc np_overwrite {} {
    if {![np_mapped]} {after time 0.002 np_overwrite;return}
    if {[peek $::fs_state]==1} {after time 0.2 np_overwrite;return}
    np_check [expr {[peek $::fs_state]==9}] overwrite_confirmation
    np_type {{5 1}} np_saved
}
proc np_saved {} {
    if {![np_mapped]} {after time 0.002 np_saved;return}
    if {[peek $::fs_state] in {4 5 6}} {after time 0.2 np_saved;return}
    np_check [expr {[peek $::fs_state]==0 && [peek [expr {$::np_view+13}]]==0}] saved_clean
    puts stderr "NOTEPAD saved through chooser"
    # Clean File > Quit must release the document and secondary owner.
    fs_move 11 4 {fs_click {fs_move 12 54 {fs_click np_relaunch}}}
}
proc np_relaunch {} {
    if {![np_low_ready]} {after time 0.002 np_relaunch;return}
    if {[peek 0x1350]==2} {after time 0.2 np_relaunch;return}
    np_check [expr {[peek 0x1350]==1}] saved_closed
    fs_move 11 4 {fs_click {fs_move 12 14 {fs_click {after time 8 np_load_menu}}}}
}
proc np_load_menu {} {
    if {![np_mapped]} {after time 0.002 np_load_menu;return}
    # Registration happens before the first paint/input pass. Match the initial
    # launch settle interval before sending another keyboard-pointer click.
    after time 3 np_load_menu_ready
}
proc np_load_menu_ready {} {
    if {![np_mapped]} {after time 0.002 np_load_menu_ready;return}
    np_check [expr {[peek $::fs_state]==0 && [np_word $::np_view]==0}] fresh_owner
    fs_move 11 4 {fs_click {fs_move 12 24 {fs_click np_load_picker}}}
}
proc np_load_picker {} {
    if {![np_mapped]} {after time 0.002 np_load_picker;return}
    if {[peek $::fs_state]==1 && [peek [expr {$::np_picker+8}]]<5} {after time 0.2 np_load_picker;return}
    np_check [expr {[peek $::fs_state]==1 && [peek [expr {$::np_picker+8}]]==5}] load_picker
    for {set i 0} {$i<[peek [expr {$::np_picker+10}]]} {incr i} {
        if {[debug read_block memory [expr {$::np_picker+89+12*$i}] 11] eq "SAVED   TXT"} {
            fs_move 10 [expr {48+10*$i}] {fs_click np_loaded};return
        }
    }
    np_check [expr {[peek [expr {$::np_picker+11}]]!=0}] saved_file_present
    fs_move 22 112 {fs_click np_load_picker}
}
proc np_loaded {} {
    if {![np_mapped]} {after time 0.002 np_loaded;return}
    if {[peek $::fs_state] in {1 3}} {after time 0.2 np_loaded;return}
    np_check [expr {[peek $::fs_state]==0 && [np_word $::np_view]==4 && [peek [expr {$::np_view+13}]]==0}] reloaded_clean
    puts stderr "NOTEPAD reopened saved document in fresh owner"
    after time 2 {np_type {{3 2}} np_dirty_again}
}
proc np_dirty_again {} {
    if {![np_mapped]} {after time 0.002 np_dirty_again;return}
    np_check [expr {[peek [expr {$::np_view+13}]]==1}] modified_again
    fs_move 11 4 {fs_click {fs_move 12 54 {fs_click np_confirm}}}
}
proc np_confirm {} {
    if {![np_mapped]} {after time 0.002 np_confirm;return}
    np_check [expr {[peek $::fs_state]==2 && [peek 0x1350]==2}] dirty_confirmation
    # Cancel first: File > Quit must not discard dirty text implicitly.
    # Let popup release/debounce and the confirmation paint finish before
    # sending a short matrix pulse; observing mode alone precedes that work.
    after time 2 {np_type {{7 4}} np_quit_cancelled}
}
proc np_quit_cancelled {} {
    if {![np_mapped]} {after time 0.002 np_quit_cancelled;return}
    np_check [expr {[peek $::fs_state]==0 && [peek [expr {$::np_view+13}]]==1}] quit_cancel_retains_document
    fs_move 11 4 {fs_click {fs_move 12 54 {fs_click np_quit_discard}}}
}
proc np_quit_discard {} {
    if {![np_mapped]} {after time 0.002 np_quit_discard;return}
    np_check [expr {[peek $::fs_state]==2 && [peek 0x1350]==2}] quit_discard_confirmation
    # D: discard. Then normal owner teardown must remove the secondary seal.
    after time 2 {np_type {{3 2}} np_closed}
}
proc np_closed {} {
    if {[peek 0x403]!=71 || [peek 0x404]!=66} {after time 0.002 np_closed;return}
    np_check [expr {[peek 0x1350]==1 && [peek 0x1347]==0}] closed
    np_check [expr {[debug read_block memory 0x2180 64] eq [string repeat \x00 64]}] seals_reclaimed
    fs_finish PASS
}
