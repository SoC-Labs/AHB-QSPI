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
# Final timing / area / power QoR — per-scenario, both setup and hold.
# Without an explicit current_scenario / -delay_type loop, report_qor
# only emits the current-scenario setup view; we'd lose visibility on
# the FF/min hold corner that scen_fast covers. Iterate across all
# active scenarios and dump both setup and hold worst-paths.
#-----------------------------------------------------------------------------
set active_scenarios [list]
foreach_in_collection s [get_scenarios -quiet -filter active==true] {
    lappend active_scenarios [get_attribute $s name]
}
puts "INFO: \[fc_signoff\] active scenarios: $active_scenarios"

redirect -tee -file ${fc_reports}/05_signoff.qor.rep {
    report_qor -summary
}

foreach scen $active_scenarios {
    current_scenario $scen
    redirect -tee -file ${fc_reports}/05_signoff.${scen}.setup.rep {
        puts "=== Scenario $scen — setup ==="
        report_timing -delay_type max -nets -capacitance -max_paths 5
    }
    redirect -tee -file ${fc_reports}/05_signoff.${scen}.hold.rep {
        puts "=== Scenario $scen — hold ==="
        report_timing -delay_type min -nets -capacitance -max_paths 5
    }
}

redirect -tee -file ${fc_reports}/05_signoff.area.rep   { report_area -hierarchy }
redirect -tee -file ${fc_reports}/05_signoff.power.rep  { report_power }

#-----------------------------------------------------------------------------
# Save block: ${design_lib}/${top}/signoff.design
#-----------------------------------------------------------------------------
save_block
save_lib $design_lib_name
save_block -as ${design_lib_name}:${top_module}/signoff.design

puts "FC_STAGE_OK: signoff"
exit
