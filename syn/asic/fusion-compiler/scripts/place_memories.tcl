#-----------------------------------------------------------------------------
# Memory macro placement — split-column layout matching the reference
# floorplan diagram:
#
#   +--------+ ←──────────────────────────────→ +--------+
#   |  DATA  |                                  |  DATA  |   row 0 (top)
#   +--------+                                  +--------+
#   |  DATA  |          +-----+ +-----+         |  DATA  |
#   +--------+          | TAG | | TAG |         +--------+   row 1
#   |  DATA  |          +-----+ +-----+         |  DATA  |   row 2
#   +--------+                                  +--------+
#   |  DATA  |                                  |  DATA  |   row 3 (bottom)
#   +--------+                                  +--------+
#    ←312 μm→          ←135+4+135→               ←312 μm→
#       way 0           way0  way1                 way 1
#
# Macro inventory (cache_subsystem.v: u_way0_cache_ram + u_way1_cache_ram,
# each cache_ram drops in 4× flash_cache_data + 1× flash_cache_tag):
#   8× flash_cache_data  (311.8 × 36.36 μm — very wide, very flat)
#   2× flash_cache_tag   (135.4 × 40.51 μm)
#
# Way 0's 4 data macros stack on the LEFT (sorted instance names put
# u_way0_*/data_ram_0_word_{0..3}_i first); way 1's 4 on the RIGHT.
# The 2 tag cells sit side-by-side in the middle, vertically centred
# against the data stack so the std-cell region wraps cleanly above,
# below, and either side of the tag pair.
#
# Sourced by 1_init_design.tcl AFTER initialize_floorplan and BEFORE
# the pre-compile sanity check.
#-----------------------------------------------------------------------------

# ── Geometry constants (μm) ────────────────────────────────────────────────
set FCD_W      311.8
set FCD_H      36.36
set FCT_W      135.4
set FCT_H      40.51

set MARGIN     5.0    ;# core-edge to macro-block clearance
set V_CHANNEL  5.0    ;# vertical gap between stacked data macros
set TAG_GAP    4.0    ;# horizontal gap between the two tag macros

# Die dims from the Makefile (used to anchor the right-column + tag
# centering off the right boundary). Falls back to a sensible default
# when this script is sourced from a context that doesn't set them.
set die_w 1020
set die_h 220
if {[info exists ::env(FC_DIE_WIDTH)]}  { set die_w $::env(FC_DIE_WIDTH) }
if {[info exists ::env(FC_DIE_HEIGHT)]} { set die_h $::env(FC_DIE_HEIGHT) }

# ── Cell discovery ─────────────────────────────────────────────────────────
set fcd_insts [list]
foreach_in_collection c [get_cells -hier -filter {ref_name == flash_cache_data}] {
    lappend fcd_insts [get_attribute $c full_name]
}
set fcd_insts [lsort $fcd_insts]

set fct_insts [list]
foreach_in_collection c [get_cells -hier -filter {ref_name == flash_cache_tag}] {
    lappend fct_insts [get_attribute $c full_name]
}
set fct_insts [lsort $fct_insts]

proc cell_by_full_name {full_name} {
    return [get_cells -hier -filter "full_name == \"$full_name\""]
}

#-----------------------------------------------------------------------------
# Common Y coordinates — data macros all share the same vertical stack
# positions on both sides; tags vertically centred against the stack.
#-----------------------------------------------------------------------------
set stack_h [expr {4 * $FCD_H + 3 * $V_CHANNEL}]
set left_x  $MARGIN
set right_x [expr {$die_w - $MARGIN - $FCD_W}]

#-----------------------------------------------------------------------------
# 1) flash_cache_data — first 4 macros (way 0) on the LEFT column,
#    next 4 (way 1) on the RIGHT column. Same y positions both sides.
#-----------------------------------------------------------------------------
set i 0
foreach inst $fcd_insts {
    set cell [cell_by_full_name $inst]
    if {[sizeof_collection $cell] == 0} {
        puts "WARN: \[place_memories\] $inst not found — skipping"
        incr i
        continue
    }
    set row [expr {$i % 4}]
    set x   [expr {$i < 4 ? $left_x : $right_x}]
    set y   [expr {$MARGIN + $row * ($FCD_H + $V_CHANNEL)}]
    set_attribute $cell origin [list $x $y]
    set_attribute $cell orientation R0
    incr i
}

#-----------------------------------------------------------------------------
# 2) flash_cache_tag — 2 cells side-by-side, vertically centred against
#    the data stack, horizontally centred between the two data columns.
#-----------------------------------------------------------------------------
set tag_pair_w [expr {2 * $FCT_W + $TAG_GAP}]
set tag_x0     [expr {($die_w - $tag_pair_w) / 2.0}]
set tag_y      [expr {$MARGIN + ($stack_h - $FCT_H) / 2.0}]

set i 0
foreach inst $fct_insts {
    set cell [cell_by_full_name $inst]
    if {[sizeof_collection $cell] == 0} {
        puts "WARN: \[place_memories\] $inst not found — skipping"
        incr i
        continue
    }
    set x [expr {$tag_x0 + $i * ($FCT_W + $TAG_GAP)}]
    set_attribute $cell origin [list $x $tag_y]
    set_attribute $cell orientation R0
    incr i
}

#-----------------------------------------------------------------------------
# Lock the macros and add keepouts so subsequent placement passes
# don't disturb them and the router has decent channels around each.
#-----------------------------------------------------------------------------
set fixed_macros [list]
foreach inst [concat $fcd_insts $fct_insts] {
    set c [cell_by_full_name $inst]
    if {[sizeof_collection $c] > 0} { lappend fixed_macros $inst }
}
foreach inst $fixed_macros {
    set_attribute -objects [cell_by_full_name $inst] -name physical_status -value fixed
}

# 5 μm hard / 8 μm soft keepout around each macro — gives router channels.
foreach inst $fixed_macros {
    set ref [get_attribute [cell_by_full_name $inst] ref_block]
    create_keepout_margin -type hard -outer {5 5 5 5} $ref
    create_keepout_margin -type soft -outer {8 8 8 8} $ref
}

puts "INFO: \[place_memories\] [llength $fixed_macros] macros pinned + locked\
 (die ${die_w}x${die_h}, stack_h=$stack_h, tag_x0=$tag_x0, tag_y=$tag_y)"
