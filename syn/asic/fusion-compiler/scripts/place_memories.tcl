#-----------------------------------------------------------------------------
# Memory macro placement — pin the cache SRAMs along the bottom edge so
# the std-cell region is one cohesive area instead of fragmenting around
# free-floating macros.
#
# Macro inventory (cache_subsystem.v: u_way0_cache_ram + u_way1_cache_ram,
# each cache_ram drops in 4× flash_cache_data + 1× flash_cache_tag):
#   8× flash_cache_data  (256 × 32, ~190 × 285 μm each)
#   2× flash_cache_tag   (256 × 11)
#
# Layout strategy:
#   Bottom row — flash_cache_data macros arrayed along the bottom edge,
#                left-to-right; flash_cache_tag macros tucked in at the
#                far right of the same row. Std cells fill the rest of
#                the die above.
#
# Sourced by 1_init_design.tcl AFTER initialize_floorplan and BEFORE
# the pre-compile sanity check.
#-----------------------------------------------------------------------------

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

#-----------------------------------------------------------------------------
# Helper: look up a cell collection by exact full_name, side-stepping the
# regex/glob interpretation get_cells applies to plain pattern arguments.
#-----------------------------------------------------------------------------
proc cell_by_full_name {full_name} {
    return [get_cells -hier -filter "full_name == \"$full_name\""]
}

#-----------------------------------------------------------------------------
# 1) flash_cache_data — array along the bottom edge, left-to-right.
#    rf_sp_hdf macros at this depth/width are ~190 × 285 μm; pitch 0.10 of
#    die width gives ~150 μm spacing on a ~1500 μm die.
#-----------------------------------------------------------------------------
set fcd_pitch_x 0.10
set x_offset    0.02
foreach inst $fcd_insts {
    set cell [cell_by_full_name $inst]
    if {[sizeof_collection $cell] == 0} {
        puts "WARN: \[place_memories\] $inst not found — skipping"
        continue
    }
    set_macro_relative_location \
        -target_object   $cell \
        -target_orientation R0 \
        -target_corner   bl \
        -anchor_corner   bl \
        -offset          [list $x_offset 0.02] \
        -offset_type     scalable
    set x_offset [expr $x_offset + $fcd_pitch_x]
}

#-----------------------------------------------------------------------------
# 2) flash_cache_tag — to the right of the data row.
#-----------------------------------------------------------------------------
set fct_pitch_x 0.08
foreach inst $fct_insts {
    set cell [cell_by_full_name $inst]
    if {[sizeof_collection $cell] == 0} {
        puts "WARN: \[place_memories\] $inst not found — skipping"
        continue
    }
    set_macro_relative_location \
        -target_object   $cell \
        -target_orientation R0 \
        -target_corner   bl \
        -anchor_corner   bl \
        -offset          [list $x_offset 0.02] \
        -offset_type     scalable
    set x_offset [expr $x_offset + $fct_pitch_x]
}

#-----------------------------------------------------------------------------
# Apply the placement and lock the macros so subsequent placement passes
# don't move them.
#-----------------------------------------------------------------------------
create_macro_relative_location_placement

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

puts "INFO: \[place_memories\] [llength $fixed_macros] macros pinned + locked"
