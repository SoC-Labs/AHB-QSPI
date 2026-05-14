#-----------------------------------------------------------------------------
# Phase 4: route — route_auto + route_opt + std-cell fillers.
#
# Run with: fc_shell -f 4_route.tcl   (after 3_clock.tcl)
#-----------------------------------------------------------------------------

set top_module       $::env(MODULE)
set design_lib_name  "${top_module}.dlib"
set fc_dir           $::env(FC_DIR)
set fc_logs          $::env(FC_LOGS)
set fc_reports       $::env(FC_REPORTS)
set fc_outputs       $::env(FC_OUTPUTS)

# SVF for route — route_opt can substitute cells (sizing/buffer insertion).
file mkdir ${fc_outputs}/svf
set_svf ${fc_outputs}/svf/${top_module}.route.svf

#-----------------------------------------------------------------------------
# Open the post-CTS checkpoint
#-----------------------------------------------------------------------------
open_lib   $design_lib_name
open_block ${design_lib_name}:${top_module}/cts.design

source ${fc_dir}/scripts/setup.tcl
source ${fc_dir}/scripts/setup_design_options.tcl

#-----------------------------------------------------------------------------
# route_auto — initial detail+global route
#-----------------------------------------------------------------------------
puts "INFO: \[fc_route\] route_auto"
route_auto

redirect -tee -file ${fc_reports}/04a_route_auto.qor.rep {
    report_qor -summary
    report_design -nosplit
}
save_block

#-----------------------------------------------------------------------------
# route_opt — post-route timing + DRC opto
#-----------------------------------------------------------------------------
puts "INFO: \[fc_route\] route_opt"
route_opt

redirect -tee -file ${fc_reports}/04b_route_opt.qor.rep {
    report_qor -summary
    report_timing -nets -capacitance
}

#-----------------------------------------------------------------------------
# Dedicated hold-fix pass — the default route_opt prioritises setup;
# small fast-corner hold violations are common after route on
# clock-gated paths. -from_stage final_route -to_stage hold_fix targets
# those races without disturbing setup. Skip if no scen_fast corner is
# active (no hold corner to fix).
#-----------------------------------------------------------------------------
if {[sizeof_collection [get_scenarios -quiet scen_fast]] > 0} {
    puts "INFO: \[fc_route\] route_opt -from final_route -to hold_fix (hold close on scen_fast)"
    if {[catch {route_opt -from final_route -to hold_fix} err]} {
        puts "WARN: \[fc_route\] hold_fix pass returned: $err"
    }
    redirect -tee -file ${fc_reports}/04c_route_opt_hold.qor.rep {
        report_qor -summary
    }
}

#-----------------------------------------------------------------------------
# Save block: ${design_lib}/${top}/route.design
#-----------------------------------------------------------------------------
save_block
save_lib $design_lib_name
save_block -as ${design_lib_name}:${top_module}/route.design

puts "FC_STAGE_OK: route"
exit
