#-----------------------------------------------------------------------------
# Memory macro placement — pack the cache SRAMs into a tight 2-column
# block at the bottom-left so the std-cell region above is one cohesive
# rectangle instead of fragmenting around stacked macros.
#
# Macro inventory (cache_subsystem.v: u_way0_cache_ram + u_way1_cache_ram,
# each cache_ram drops in 4× flash_cache_data + 1× flash_cache_tag):
#   8× flash_cache_data  (311.8 × 36.36 μm — very wide, very flat)
#   2× flash_cache_tag   (135.4 × 40.51 μm)
#
# Why an explicit grid: the macros are wider than they are tall by ~9×, so
# the previous `scalable` (fractional) offsets at 10 % of die width
# (~40 μm) collided with the 312 μm-wide cells and FC fell back to
# stacking them in a single 1×10 column. Using absolute (μm) origins
# pins them deterministically.
#
# Layout — bottom-left corner, growing up + right:
#
#   +-----------------+
#   |   std cells     |   ← one cohesive rectangle for std-cell rows
#   +-----+-----+-----+
#   | TAG | TAG       |   ← 2 tag macros, left-justified
#   +-----+-----+-----+
#   | DATA  | DATA    |   ┐
#   | DATA  | DATA    |   │ 8× flash_cache_data
#   | DATA  | DATA    |   │ in a 2-column / 4-row grid
#   | DATA  | DATA    |   ┘
#   +-------+---------+
#
# Total macro footprint ≈ 634 × 230 μm = 146 k μm². Combined with the
# std-cell area (~36 k μm² @ util 0.78) the die settles around
# 640 × 285 μm — vs the original 413 × 411 (1×10 stack with dead space
# in the left strip).
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
set H_CHANNEL  4.0    ;# horizontal gap between macros in the same row
set V_CHANNEL  4.0    ;# vertical gap between macro rows
set TAG_GAP    8.0    ;# extra clearance between top data row and tag row

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
# 1) flash_cache_data — 2 columns × 4 rows starting at (MARGIN, MARGIN).
#    Iterate row-major through the sorted list so the way0/way1 RAMs
#    naturally interleave column-by-column.
#-----------------------------------------------------------------------------
set fcd_pitch_x [expr {$FCD_W + $H_CHANNEL}]
set fcd_pitch_y [expr {$FCD_H + $V_CHANNEL}]

set i 0
foreach inst $fcd_insts {
    set cell [cell_by_full_name $inst]
    if {[sizeof_collection $cell] == 0} {
        puts "WARN: \[place_memories\] $inst not found — skipping"
        incr i
        continue
    }
    set col [expr {$i % 2}]
    set row [expr {$i / 2}]
    set x [expr {$MARGIN + $col * $fcd_pitch_x}]
    set y [expr {$MARGIN + $row * $fcd_pitch_y}]
    set_attribute $cell origin [list $x $y]
    set_attribute $cell orientation R0
    incr i
}

# Top of the data block (μm above die origin)
set data_top_y [expr {$MARGIN + 4 * $fcd_pitch_y - $V_CHANNEL}]

#-----------------------------------------------------------------------------
# 2) flash_cache_tag — 2-wide row sitting above the data block.
#-----------------------------------------------------------------------------
set tag_y [expr {$data_top_y + $TAG_GAP}]
set fct_pitch_x [expr {$FCT_W + $H_CHANNEL}]

set i 0
foreach inst $fct_insts {
    set cell [cell_by_full_name $inst]
    if {[sizeof_collection $cell] == 0} {
        puts "WARN: \[place_memories\] $inst not found — skipping"
        incr i
        continue
    }
    set x [expr {$MARGIN + $i * $fct_pitch_x}]
    set_attribute $cell origin [list $x $tag_y]
    set_attribute $cell orientation R0
    incr i
}

#-----------------------------------------------------------------------------
# Lock the macros and add keepouts so subsequent placement passes don't
# disturb them and the router has decent channels around each cell.
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
 (data block top y=$data_top_y, tag row y=$tag_y)"
