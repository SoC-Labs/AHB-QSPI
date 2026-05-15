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
# Optional routing rules — non-default routing rules (NDRs), per-layer
# width/spacing, antenna rules, and clock-net NDR assignment. This is
# the alignment hook with the 28nm full-chip flow's routing_rules.tcl:
# sc12 cln65lp at this die size routes cleanly with the tool defaults,
# so there is NO checked-in rule file (and none is fabricated — the
# numbers are PDK/foundry data). Copy inputs/routing_rules.tcl.template
# to inputs/routing_rules.tcl and fill in the antenna ratios / NDR
# widths from the cln65lp routing-rule deck to enable it. Sourced here
# (after setup, before route_auto) so create_routing_rule +
# set_clock_routing_rule land before any nets are routed.
#-----------------------------------------------------------------------------
set routing_rules ${fc_dir}/inputs/routing_rules.tcl
if {[file exists $routing_rules]} {
    puts "INFO: \[fc_route\] sourcing routing rules: $routing_rules"
    if {[catch {source $routing_rules} rr_err]} {
        puts "WARN: \[fc_route\] routing_rules.tcl raised: $rr_err"
        puts "WARN: \[fc_route\]   continuing with tool-default routing rules"
    }
} else {
    puts "INFO: \[fc_route\] no inputs/routing_rules.tcl — tool-default rules"
    puts "INFO: \[fc_route\]   (see inputs/routing_rules.tcl.template to enable)"
}

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
# DRC-cleanup detail-route pass. route_opt + hold_fix leave ~50 DRCs in
# the congested std-cell band between the macro columns (the cache
# HRDATA/HWDATA buses + the PG mesh competing for tracks): mostly
# end-of-line spacing plus the occasional short at a macro-column
# boundary. An incremental detail route seeded from the DRC info
# already in the block reroutes only the violating regions, so it
# cleans the spacing/short without disturbing the bulk of the routing
# (and thus without re-opening setup/hold). Iterate a few times — EOL
# fixes can cascade.
#-----------------------------------------------------------------------------
puts "INFO: \[fc_route\] route_detail (incremental DRC cleanup)"
if {[catch {route_detail -incremental true \
                         -initial_drc_from_input true \
                         -max_number_iterations 10} rd_err]} {
    puts "WARN: \[fc_route\] route_detail cleanup returned: $rd_err"
}
redirect -tee -file ${fc_reports}/04d_route_detail_drc.rep {
    report_qor -summary
    check_routes -open_net true -drc true
}

# Pure detail-route took 52 -> ~22 DRCs but can't relieve the local
# congestion in the narrow std-cell band between the macro columns
# (it reroutes nets, it can't nudge cells). A final route_opt pass can
# make small ECO placement/sizing changes there, freeing M1/M2 tracks
# so the residual end-of-line spacings + the macro-boundary short can
# route legally. Then one more incremental detail route to lock it in.
puts "INFO: \[fc_route\] route_opt -from final_route (congestion-relief ECO)"
if {[catch {route_opt -from final_route -to final_route} ro_err]} {
    puts "WARN: \[fc_route\] route_opt final_route returned: $ro_err"
}
if {[catch {route_detail -incremental true \
                         -initial_drc_from_input true \
                         -max_number_iterations 10} rd2_err]} {
    puts "WARN: \[fc_route\] post-ECO route_detail returned: $rd2_err"
}
redirect -tee -file ${fc_reports}/04e_route_drc_final.rep {
    report_qor -summary
    check_routes -open_net true -drc true
}

#-----------------------------------------------------------------------------
# Save block: ${design_lib}/${top}/route.design
#-----------------------------------------------------------------------------
save_block
save_lib $design_lib_name
save_block -as ${design_lib_name}:${top_module}/route.design

puts "FC_STAGE_OK: route"
exit
