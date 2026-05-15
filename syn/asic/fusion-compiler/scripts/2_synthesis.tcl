#-----------------------------------------------------------------------------
# Phase 2: synthesis — compile_fusion through logic_opto + initial_place
#                      + final_place. Pre-CTS save_block.
#
# Run with: fc_shell -f 2_synthesis.tcl   (after 1_init_design.tcl)
#-----------------------------------------------------------------------------

set top_module       $::env(MODULE)
set design_lib_name  "${top_module}.dlib"
set fc_dir           $::env(FC_DIR)
set fc_logs          $::env(FC_LOGS)
set fc_reports       $::env(FC_REPORTS)
set fc_outputs       $::env(FC_OUTPUTS)

# SVF for this stage — synthesis transforms (the ones LEC most cares about).
file mkdir ${fc_outputs}/svf
set_svf ${fc_outputs}/svf/${top_module}.synth.svf

#-----------------------------------------------------------------------------
# Open from init.design checkpoint
#-----------------------------------------------------------------------------
open_lib   $design_lib_name
open_block ${design_lib_name}:${top_module}/init.design

source ${fc_dir}/scripts/setup.tcl
source ${fc_dir}/scripts/setup_design_options.tcl

#-----------------------------------------------------------------------------
# Logic synthesis + initial placement + final placement
#  - logic_opto:    pre-place gate-level optimisation
#  - initial_opto:  post initial placement opto
#  - final_place:   final placement (closes Phase 2)
#-----------------------------------------------------------------------------
set_qor_strategy -stage synthesis -metric timing -high_effort_timing

puts "INFO: \[fc_synth\] compile_fusion -to logic_opto"
compile_fusion -to logic_opto

redirect -tee -file ${fc_reports}/02a_logic_opto.qor.rep {
    report_qor -summary
    report_timing -nets -capacitance -transition_time
    report_area -hierarchy
}
save_block

puts "INFO: \[fc_synth\] compile_fusion -from initial_place -to initial_opto"
compile_fusion -from initial_place -to initial_opto

redirect -tee -file ${fc_reports}/02b_initial_opto.qor.rep {
    report_qor -summary
    report_timing -nets -capacitance
}
save_block

puts "INFO: \[fc_synth\] compile_fusion -from final_place"
compile_fusion -from final_place

redirect -tee -file ${fc_reports}/02c_final_place.qor.rep {
    report_qor -summary
    report_timing -nets -capacitance
    report_area -hierarchy
    report_congestion
}

#-----------------------------------------------------------------------------
# Post-placement PG repair.
#
# pg_mesh.tcl is sourced from 1_init_design.tcl — BEFORE compile_fusion
# creates + places the ~6900 std cells — so its connect_pg_net and
# compile_pg only ever saw the 10 macros. Nothing re-asserted PG once
# the std cells existed, which is why check_pg_connectivity in the live
# fc_all run still reported ~771 (VDD) / ~517 (VSS) floating std cells
# (~11 %, the congested PATH_31_* band between the macro columns) — the
# pattern definition alone can't connect cells that didn't exist when it
# compiled.
#
# Re-assert here, now that placement is final and every cell exists:
#   1. connect_pg_net -automatic  — re-bind each placed cell's PG pins
#      to VDD/VSS by Liberty footprint. Idempotent: moves no cell,
#      changes no timing, rebuilds no mesh.
#   2. realize the M1 follow-pin rails over the now-placed rows via a
#      dedicated post strategy (distinct name avoids redefining the
#      init-stage pattern), then connect_pg_net once more so the
#      newly-railed cells are logically bound too.
#
# Entirely best-effort / guarded — PG repair must never stop Phase 2
# reaching FC_STAGE_OK. The next live fc_all's
# 07_check_pg_connectivity.rep (and the 02d snapshot below) is the
# confirmation that the floating count actually drops; this change is
# structurally sound but not yet silicon-validated.
#-----------------------------------------------------------------------------
puts "INFO: \[fc_synth\] post-placement PG repair (connect_pg_net + M1 rails)"
catch {connect_pg_net -automatic}
if {[catch {
    create_pg_std_cell_conn_pattern std_cell_rail_post -layers {M1} -rail_width 0.18
    set_pg_strategy rail_strategy_post \
        -pattern {{name: std_cell_rail_post} {nets: {VDD VSS}}} -core
    compile_pg -strategies {rail_strategy_post}
    connect_pg_net -automatic
} pg_err]} {
    puts "WARN: \[fc_synth\] post-placement PG rail repair returned: $pg_err"
    puts "WARN: \[fc_synth\]   (logical connect_pg_net above still applied;"
    puts "WARN: \[fc_synth\]    stage proceeds — see 02d_pg_repair.rep)"
}
redirect -file ${fc_reports}/02d_pg_repair.rep {
    catch {check_pg_connectivity}
}

#-----------------------------------------------------------------------------
# Save block: ${design_lib}/${top}/compile.design
#-----------------------------------------------------------------------------
save_block
save_lib $design_lib_name
save_block -as ${design_lib_name}:${top_module}/compile.design

puts "FC_STAGE_OK: synth"
exit
