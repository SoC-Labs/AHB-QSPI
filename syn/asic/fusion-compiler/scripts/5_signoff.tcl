#-----------------------------------------------------------------------------
# Phase 4b: signoff — final QoR + chip-finish (fillers).
#
# Run with: fc_shell -f 5_signoff.tcl   (after 4_route.tcl)
#-----------------------------------------------------------------------------

set top_module       $::env(MODULE)
set design_lib_name  "${top_module}.dlib"
set fc_dir           $::env(FC_DIR)
set fc_logs          $::env(FC_LOGS)
set fc_reports       $::env(FC_REPORTS)

#-----------------------------------------------------------------------------
# Open the post-route checkpoint
#-----------------------------------------------------------------------------
open_lib   $design_lib_name
open_block ${design_lib_name}:${top_module}/route.design

source ${fc_dir}/scripts/setup.tcl
source ${fc_dir}/scripts/setup_design_options.tcl

#-----------------------------------------------------------------------------
# Final timing/area/power QoR. ICV/redhawk in-design checks deferred
# until top-level integration (the partition-as-block delivery does
# not need DRC/LVS at this stage; chip-top will run the full deck).
#-----------------------------------------------------------------------------
redirect -tee -file ${fc_reports}/05_signoff.qor.rep {
    report_qor -summary
    report_timing -nets -capacitance -max_paths 5
    report_area -hierarchy
    report_power
}

#-----------------------------------------------------------------------------
# Save block: ${design_lib}/${top}/signoff.design
#-----------------------------------------------------------------------------
save_block
save_lib $design_lib_name
save_block -as ${design_lib_name}:${top_module}/signoff.design

puts "FC_STAGE_OK: signoff"
exit
