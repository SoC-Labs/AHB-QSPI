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
set fc_outputs       $::env(FC_OUTPUTS)

# SVF for signoff — closes the per-stage SVF chain that
# formality/scripts/run_lec.tcl walks (init→synth→cts→route→signoff).
# run_lec.tcl globs ${top}.signoff.svf; if this stage never names one,
# the signoff slot is silently dropped and any signoff-stage ECO / cell
# substitution becomes an unguided LEC mismatch. Signoff does no
# remapping today so the file is usually empty, but it MUST exist and be
# named before the block is opened so future signoff ECO fixes are
# captured in the LEC guidance.
file mkdir ${fc_outputs}/svf
set_svf ${fc_outputs}/svf/${top_module}.signoff.svf

#-----------------------------------------------------------------------------
# Open the post-route-PG checkpoint. pg.design = route.design after the
# Phase-4a rail + M3-stitch (pg_rails.tcl) that closes the 814/487
# floating-std-cell PG gap. Signoff QoR / SPEF must be on the stitched
# PG, not the pre-stitch route.design.
#-----------------------------------------------------------------------------
open_lib   $design_lib_name
open_block ${design_lib_name}:${top_module}/pg.design

source ${fc_dir}/scripts/setup.tcl
source ${fc_dir}/scripts/setup_design_options.tcl

#-----------------------------------------------------------------------------
# Signoff-quality parasitic extraction. Two reasons this must run here:
#   1. The per-scenario QoR below is only trustworthy on real extracted
#      RC — without this, report_timing uses the estimated/virtual-route
#      parasitics carried over from route.design.
#   2. 6_partition_export.tcl's write_parasitics (per-scenario SPEF) has
#      nothing to emit unless the signoff block carries extracted
#      parasitics; the SPEF guard there would otherwise downgrade to a
#      warning and the integrator would have to re-flat-extract through
#      the block.
# TLU+ models + per-corner early/late specs were already bound in the
# shared FC.read_design.tcl (read_parasitic_tech / set_parasitic_
# parameters). fc_shell U-2022.12 has no standalone `extract_parasitics`
# command (CMD-005) — RC extraction is driven implicitly by a full
# timing update against the bound TLU+ tech. `update_timing -full`
# forces that recompute across every active scenario so the QoR below
# and the SPEF written in 6_partition_export.tcl are on real extracted
# RC, not the route-estimate carried over from route.design.
# Guarded: a missing TLU+ / extraction failure must not silently produce
# a signoff block with stale RC — fail the stage loudly instead.
puts "INFO: \[fc_signoff\] update_timing -full (signoff RC for QoR + SPEF)"
if {[catch {update_timing -full} ep_err]} {
    puts "ERROR: \[fc_signoff\] update_timing -full failed: $ep_err"
    puts "ERROR: \[fc_signoff\] signoff QoR + exported SPEF would be on stale"
    puts "ERROR: \[fc_signoff\] route-estimate RC — not touching FC_STAGE_OK."
    exit 1
}

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
