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
# Save block: ${design_lib}/${top}/compile.design
#-----------------------------------------------------------------------------
save_block
save_lib $design_lib_name
save_block -as ${design_lib_name}:${top_module}/compile.design

puts "FC_STAGE_OK: synth"
exit
