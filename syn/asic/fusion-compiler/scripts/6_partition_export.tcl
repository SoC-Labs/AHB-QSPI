#-----------------------------------------------------------------------------
# Phase 4c: partition export — write hand-off products for top-level chip
#                              integration.
#
# Run with: fc_shell -f 6_partition_export.tcl   (after 5_signoff.tcl)
#-----------------------------------------------------------------------------

set top_module       $::env(MODULE)
set design_lib_name  "${top_module}.dlib"
set fc_dir           $::env(FC_DIR)
set fc_outputs       $::env(FC_OUTPUTS)
set fc_reports       $::env(FC_REPORTS)

file mkdir $fc_outputs

#-----------------------------------------------------------------------------
# Open the post-signoff checkpoint
#-----------------------------------------------------------------------------
open_lib   $design_lib_name
open_block ${design_lib_name}:${top_module}/signoff.design

source ${fc_dir}/scripts/setup.tcl
source ${fc_dir}/scripts/setup_design_options.tcl

#-----------------------------------------------------------------------------
# Hand-off products for top-level chip flow
#-----------------------------------------------------------------------------

# Gate-level Verilog netlist (logic) + power-aware variant (with PG pins)
puts "INFO: \[fc_abstract\] write_verilog (gate netlist + PG variant)"
write_verilog ${fc_outputs}/${top_module}.v
write_verilog -include {pg_objects} ${fc_outputs}/${top_module}.pg.v

# Boundary SDC for top-level constraint propagation
puts "INFO: \[fc_abstract\] write_sdc"
write_sdc -output ${fc_outputs}/${top_module}.sdc

# SDF for back-annotated gate-level simulation. Pick the slow corner —
# matches the timing-signoff scenario most users want for hold/setup
# regressions. write_sdf operates on the current scenario.
puts "INFO: \[fc_abstract\] write_sdf (scen_slow)"
if {[sizeof_collection [get_scenarios -quiet scen_slow]] > 0} {
    current_scenario scen_slow
    write_sdf ${fc_outputs}/${top_module}.sdf
} else {
    puts "WARNING: scen_slow not found — skipping SDF write"
}

# Floorplan DEF (top can place the partition by reading this)
puts "INFO: \[fc_abstract\] write_def"
write_def ${fc_outputs}/${top_module}.def

# LEF abstract (physical interface for top-level placement)
puts "INFO: \[fc_abstract\] write_lef"
write_lef ${fc_outputs}/${top_module}.lef

# NOTE: ETM (Extracted Timing Model) generation is not provided directly
# in fc_shell U-2022.12 — the relevant `write_lib_model -format etm`
# command is unavailable here. Top-level STA can either read the
# committed signoff.design block from the .dlib (NDM-based hierarchical
# STA) or generate ETM via PrimeTime as a follow-on. The .dlib block
# IS the partition abstract for FC's hierarchical PnR flow.

# GDSII for chip-finish / DRC / LVS — partition geometry plus the
# referenced std-cell + macro GDS streams merged in so the output is
# self-contained.
puts "INFO: \[fc_abstract\] write_gds (merging std-cell + cache-RAM streams)"
set gds_layer_map [expr {[info exists ::env(GDS_LAYER_MAP)] ? $::env(GDS_LAYER_MAP) : ""}]
set gds_merge_files [list]
foreach v {GDS_STDCELL GDS_MEM_FCD GDS_MEM_FCT} {
    if {[info exists ::env($v)] && [file exists $::env($v)]} {
        lappend gds_merge_files $::env($v)
    } else {
        puts "WARNING: \[fc_abstract\] $v missing or path not found — skipping merge"
    }
}
if {$gds_layer_map ne "" && [file exists $gds_layer_map]} {
    write_gds \
        -hierarchy all \
        -layer_map $gds_layer_map \
        -layer_map_format icc2 \
        -merge_files $gds_merge_files \
        -compress \
        ${fc_outputs}/${top_module}.gds
    puts "INFO: \[fc_abstract\] GDS at ${fc_outputs}/${top_module}.gds"
} else {
    puts "WARNING: \[fc_abstract\] GDS_LAYER_MAP not found at '$gds_layer_map' — skipping GDS write"
}

#-----------------------------------------------------------------------------
# Manifest of delivered products
#-----------------------------------------------------------------------------
redirect -tee -file ${fc_reports}/06_abstract_manifest.txt {
    puts "Partition deliverables for $top_module"
    puts "----------------------------------------"
    foreach f [lsort [glob -nocomplain ${fc_outputs}/*]] {
        puts "  [file size $f] bytes  [file tail $f]"
    }
}

puts "FC_STAGE_OK: abstract"
exit
