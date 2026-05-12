#-----------------------------------------------------------------------------
# Phase 1: init_design — create design library, analyze RTL, elaborate,
#                        MCMM, parasitic, clocks, floorplan, pre-compile check.
#
# Run with: fc_shell -f 1_init_design.tcl
#
# Environment variables (exported by Makefile + common.mk):
#   MODULE, TOP, FLIST                — design ID + filelist
#   SOCLABS_AHB_QSPI_DIR              — repo root
#   FC_DIR, SHARED_SCRIPTS,
#   FC_LIBS, FC_LOGS, FC_REPORTS      — flow paths
#   TF_FILE                           — Milkyway technology file
#   FUSION_LIB                        — NDM ref-lib (sc12_lib)
#   CLK_NAME, CLK_PERIOD, …           — top-level clock constraints
#   FC_ASPECT_RATIO,                  — partition floorplan target
#   FC_CORE_UTILIZATION,
#   FC_CORE_OFFSET
#-----------------------------------------------------------------------------

set top_module       $::env(MODULE)
set design_lib_name  "${top_module}.dlib"
set fusion_lib       $::env(FUSION_LIB)
set tf_file          $::env(TF_FILE)
set shared_scripts   $::env(SHARED_SCRIPTS)
set fc_dir           $::env(FC_DIR)
set fc_logs          $::env(FC_LOGS)
set fc_reports       $::env(FC_REPORTS)
set fc_outputs       $::env(FC_OUTPUTS)
set die_width        $::env(FC_DIE_WIDTH)
set die_height       $::env(FC_DIE_HEIGHT)
set core_offset      $::env(FC_CORE_OFFSET)

# Named SVF — Formality reads outputs/<top>.<stage>.svf in stage order.
# Without this fc_shell drops a "default-DATE_HOST_PID.svf" in CWD per
# invocation, scattering guidance across dozens of files.
file mkdir ${fc_outputs}/svf
set_svf ${fc_outputs}/svf/${top_module}.init.svf

#-----------------------------------------------------------------------------
# Bind Liberty .db files via link_library BEFORE create_lib. fc_shell's
# auto-CLIB process inspects link_library at create_lib time to decide
# whether to embed Liberty in the assembled CLIB. If link_library has no
# .db's at create_lib time, fc_shell falls back to a physical-only CLIB
# (LIB-081 warning) and synthesis can't find AND/OR/INV cells (DWS-0103).
#-----------------------------------------------------------------------------
# MEM_DBS_FF may be empty when no FF macro libraries are available
# (see common.mk note for the precompiled flash_cache_* macros).
set link_libs [list $::env(DB_SS) $::env(DB_FF) {*}$::env(MEM_DBS_SS)]
if {[info exists ::env(MEM_DBS_FF)] && [string trim $::env(MEM_DBS_FF)] ne ""} {
    set link_libs [concat $link_libs $::env(MEM_DBS_FF)]
}
set_app_var link_library $link_libs
puts "INFO: \[fc_init\] link_library = [get_app_var link_library]"

#-----------------------------------------------------------------------------
# Create the design library backed by per-library NDMs:
#   sc12_lib       (std cells, LEF + Liberty bundled — full lib)
#   mem_frame_lib  (flash_cache_data + flash_cache_tag LEFs — frames only;
#                   Liberty via link_library set above)
#-----------------------------------------------------------------------------
set lib_dir [file dirname $fusion_lib]
set ref_libs [list]
foreach lib {sc12_lib mem_frame_lib} {
    set p ${lib_dir}/${lib}
    if {[file isdirectory $p]} { lappend ref_libs $p }
}
puts "INFO: \[fc_init\] creating $design_lib_name -technology $tf_file"
puts "INFO: \[fc_init\]   ref_libs: $ref_libs"
# create_lib refuses to overwrite an existing dlib (LIB-009). Make may
# trigger a re-run of fc_init when the upstream FUSION_LIB directory is
# touched; nuke the old dlib first so the rebuild works idempotently.
file delete -force $design_lib_name
create_lib $design_lib_name -technology $tf_file -ref_libs $ref_libs

#-----------------------------------------------------------------------------
# Common host options, PG_NETS — needs ref_libs already loaded
#-----------------------------------------------------------------------------
source ${fc_dir}/scripts/setup.tcl

#-----------------------------------------------------------------------------
# Read RTL via the shared filelist parser:
#   - parse_flist on $FLIST
#   - analyze + elaborate $top_module
#   - MCMM (scen_slow / scen_fast)
#   - read_parasitic_tech (TLU+)
#   - create_clock + I/O delays for $CLK_NAME (HCLK)
#   - set_scenario_status -setup true *
# After elaborate a current block exists; design-scoped app_options can be
# applied next.
#-----------------------------------------------------------------------------
puts "INFO: \[fc_init\] sourcing shared FC.read_design.tcl"
source ${shared_scripts}/${top_module}.FC.read_design.tcl

source ${fc_dir}/scripts/setup_design_options.tcl

#-----------------------------------------------------------------------------
# Overlay partition-specific constraints (PCLK + generated QSPI_SCLK +
# clock groups + QSPI port I/O delays).
#-----------------------------------------------------------------------------
set extra_sdc ${fc_dir}/inputs/constraints.sdc
if {[file exists $extra_sdc]} {
    puts "INFO: \[fc_init\] overlaying $extra_sdc"
    foreach scen_name {scen_slow scen_fast} {
        if {[sizeof_collection [get_scenarios -quiet $scen_name]] > 0} {
            current_scenario $scen_name
            read_sdc $extra_sdc
        }
    }
}

#-----------------------------------------------------------------------------
# Initialise floorplan with absolute die dimensions. Util-driven sizing
# would ignore the macro footprint and produce a die too small for the
# pinned cache SRAMs (right column overflows the boundary). The
# defaults from common.mk size the die to fit the 2×4 data grid + tag
# row from place_memories.tcl with ~80 μm of std-cell + power-strap
# headroom above.
#-----------------------------------------------------------------------------
puts "INFO: \[fc_init\] initialize_floorplan die=${die_width}x${die_height} offset=$core_offset"
initialize_floorplan \
    -control_type die \
    -shape R \
    -side_length [list $die_width $die_height] \
    -core_offset $core_offset

#-----------------------------------------------------------------------------
# Macro placement — pin flash_cache_data + flash_cache_tag in the
# split-column arrangement defined by place_memories.tcl (data macros
# stacked on the left + right edges, tag pair centred between them).
#-----------------------------------------------------------------------------
source ${fc_dir}/scripts/place_memories.tcl

#-----------------------------------------------------------------------------
# Port-to-edge assignment — external QSPI on TOP, internal busses on
# the other edges.
#-----------------------------------------------------------------------------
source ${fc_dir}/scripts/place_pins.tcl

#-----------------------------------------------------------------------------
# Pre-compile sanity checks
#-----------------------------------------------------------------------------
file mkdir $fc_reports
redirect -tee -file ${fc_logs}/init_check_lib.log {
    report_design
    report_clocks
    report_scenarios
}

redirect -tee -file ${fc_logs}/precompile_checks.log {
    compile_fusion -check_only
}

#-----------------------------------------------------------------------------
# Save block: ${design_lib}/${top}/init.design
#-----------------------------------------------------------------------------
save_block
save_lib $design_lib_name
save_block -as ${design_lib_name}:${top_module}/init.design

puts "FC_STAGE_OK: init"
exit
