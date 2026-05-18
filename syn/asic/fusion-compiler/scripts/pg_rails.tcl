#-----------------------------------------------------------------------------
# Phase 4a: post-route PG rail stitch  (Blocker-1 fix)
#
# Run with: fc_shell -f pg_rails.tcl   (after 4_route.tcl, before 5_signoff)
#
# WHY THIS STAGE EXISTS
# ---------------------
# pg_mesh.tcl builds the VDD/VSS supply, the M5/M6 mesh and the macro
# straps at INIT, before placement/route. The M1 std-cell follow-pin
# rails it also creates there cannot be via-stitched to the mesh against
# the final layout, because at init there is no final placement/route.
# In the macro-fragmented central std-cell channel ~36 VDD / 22 VSS M1
# rail segments end up with no via path up to the 50 µm-pitch M5/M6
# mesh, so check_pg_connectivity reports 814 VDD / 487 VSS floating
# std cells on route.design (see INTEGRATION_CHANGES.md "PG floating-
# cell deep-dive").
#
# ARCHITECTURE (2026-05-18, supersedes the M3-stitch approach):
# pg_mesh.tcl now lays a 25 µm M5/M6 init mesh (was 50 µm). The
# post-route fine-pitch M3 stitch this stage used to add was REMOVED:
# it forced check_pg_connectivity to 0 but was TIMING-FATAL (scen_slow
# setup TNS −5.75 to −16.06 ns — M3 competes with signal routing in
# the congested channel). The 25 µm mesh instead closes TIMING
# genuinely (scen_slow setup WNS 0.00); it does NOT zero the
# check_pg_connectivity count — but that count is a reporting
# artifact, not a power-disconnect (see the NOTE below). Full
# rationale + dead-end characterisation in INTEGRATION_CHANGES.md.
#
# This stage rebinds the std-cell M1 rail pattern, re-ties leaf PG
# pins, runs a light co-management reroute (insurance) and verifies,
# before saving pg.design. NOTE: the 7_drc.tcl check_pg_connectivity
# FAIL (~1183/1087) is a REPORTING ARTIFACT, not a power-disconnect:
# the deep-dive (and a 2026-05-18 direct leaf-cell net query) proved
# all 7070 cells ARE tied to VDD/VSS; the count tracks ~54/30 floating
# WIRE stubs (trim:true mesh fragments) + the 0 PG-terminal hand-off
# gap (ZRT-740). Timing is genuinely closed (25 µm init mesh,
# scen_slow setup WNS 0.00). Closing the *check* needs the partition
# PG-pin/terminal flow + dangling-stub cleanup — real interactive
# hand-off work, tracked in INTEGRATION_CHANGES.md.
#-----------------------------------------------------------------------------

set top_module       $::env(MODULE)
set design_lib_name  "${top_module}.dlib"
set fc_dir           $::env(FC_DIR)
set fc_logs          $::env(FC_LOGS)
set fc_reports       $::env(FC_REPORTS)

file mkdir $fc_reports

#-----------------------------------------------------------------------------
# Open the post-route checkpoint.
#-----------------------------------------------------------------------------
open_lib   $design_lib_name
open_block ${design_lib_name}:${top_module}/route.design

source ${fc_dir}/scripts/setup.tcl
source ${fc_dir}/scripts/setup_design_options.tcl

#-----------------------------------------------------------------------------
# Helper: extract "Number of floating std cells: N" pair (VDD then VSS)
# from a check_pg_connectivity capture. Same parse 7_drc.tcl uses.
#-----------------------------------------------------------------------------
proc _float_pair {f} {
    if {![file exists $f]} { return {? ?} }
    set fh [open $f r]; set txt [read $fh]; close $fh
    set caps [list]
    foreach {m c} [regexp -all -inline {Number of floating std cells:\s*(\d+)} $txt] {
        lappend caps $c
    }
    set vdd [expr {[llength $caps] > 0 ? [lindex $caps 0] : "?"}]
    set vss [expr {[llength $caps] > 1 ? [lindex $caps 1] : "?"}]
    return [list $vdd $vss]
}

puts "INFO: \[fc_pg\] baseline check_pg_connectivity (route.design)"
redirect -tee -file ${fc_reports}/04f_pg_baseline.rep {
    catch {check_pg_connectivity}
}
lassign [_float_pair ${fc_reports}/04f_pg_baseline.rep] b_vdd b_vss

#-----------------------------------------------------------------------------
# Recreate the std-cell M1 rail pattern + bind to VDD/VSS. Init-stage
# patterns/strategies do NOT persist across save_block/open_block
# (established by the deep-dive), so the rail pattern is rebuilt here
# against the routed block before re-tying leaf PG pins.
#-----------------------------------------------------------------------------
puts "INFO: \[fc_pg\] (re)creating std_cell_rail pattern"
catch {remove_pg_patterns   -all}
catch {remove_pg_strategies -all}

create_pg_std_cell_conn_pattern std_cell_rail \
    -layers {M1} \
    -rail_width 0.18

set_pg_strategy rail_strategy \
    -pattern {{name: std_cell_rail} {nets: {VDD VSS}}} \
    -core

# NOTE: a post-route re-apply of the M5/M6 mesh strategy was tried
# (run 6) and proven INEFFECTIVE for connectivity (1183/1087
# unchanged vs run 5's rail-only) — consistent with the deep-dive's
# finding that the residual is floating WIRE stubs + missing PG
# terminals, not a logical rail-binding problem. Removed; this stage
# is rail-rebind + connect + co-manage + verify only.

puts "INFO: \[fc_pg\] connect_pg_net -automatic"
catch {connect_pg_net -automatic}

#-----------------------------------------------------------------------------
# Rebind the post-route std-cell rail PG. Guarded: a compile_pg
# failure must NOT silently hand a still-floating block to signoff —
# fail the stage loudly (no FC_STAGE_OK marker) so make stops here.
#-----------------------------------------------------------------------------
puts "INFO: \[fc_pg\] compile_pg -strategies {rail_strategy}"
if {[catch {compile_pg -strategies {rail_strategy}} pg_err]} {
    puts "ERROR: \[fc_pg\] compile_pg failed: $pg_err"
    puts "ERROR: \[fc_pg\] $::errorInfo"
    puts "ERROR: \[fc_pg\] not touching FC_STAGE_OK — route.design left intact."
    exit 1
}

#-----------------------------------------------------------------------------
# Light co-management reroute (insurance). The rail rebind above only
# re-binds the std-cell M1 rails (no aggressive new metal — the M3
# stitch was removed; connectivity comes from the 25 µm init mesh), so
# the route delta here is small. Still run the same convergence
# 4_route.tcl uses (ECO route_opt + incremental route_detail) so any
# minor PG-vs-signal spacing from the rebind is legalised and we
# verify check_routes did not regress vs the routed baseline. PG
# special-route nets are untouched by signal detail-route, so
# connectivity (verified below) is preserved.
redirect -tee -file ${fc_reports}/04g0_pg_routes_pre.rep {
    catch {check_routes -open_net true -drc true}
}
puts "INFO: \[fc_pg\] post-stitch route_opt (PG-vs-signal ECO relief)"
if {[catch {route_opt -from final_route -to final_route} pg_ro_err]} {
    puts "WARN: \[fc_pg\] post-stitch route_opt returned: $pg_ro_err"
}
puts "INFO: \[fc_pg\] post-stitch incremental route_detail (legalise vs PG)"
if {[catch {route_detail -incremental true \
                         -initial_drc_from_input true \
                         -max_number_iterations 10} pg_rd_err]} {
    puts "WARN: \[fc_pg\] post-stitch route_detail returned: $pg_rd_err"
}

#-----------------------------------------------------------------------------
# Post-stitch connectivity + route-DRC convergence + a concise report.
#-----------------------------------------------------------------------------
puts "INFO: \[fc_pg\] post-reroute check_pg_connectivity"
redirect -tee -file ${fc_reports}/04g_pg_post.rep {
    catch {check_pg_connectivity}
}
lassign [_float_pair ${fc_reports}/04g_pg_post.rep] p_vdd p_vss
redirect -tee -file ${fc_reports}/04g1_pg_routes_post.rep {
    catch {check_routes -open_net true -drc true}
}
proc _drc_count {f} {
    if {![file exists $f]} { return "?" }
    set fh [open $f r]; set t [read $fh]; close $fh
    if {[regexp {Total number of DRC[s]? *[:=] *([0-9]+)} $t -> n]} { return $n }
    if {[regexp {([0-9]+) +total +DRC} $t -> n]} { return $n }
    return "see-report"
}
set r_pre  [_drc_count ${fc_reports}/04g0_pg_routes_pre.rep]
set r_post [_drc_count ${fc_reports}/04g1_pg_routes_post.rep]
puts "INFO: \[fc_pg\] check_routes DRCs: post-stitch=$r_pre -> post-reroute=$r_post"

set fh [open ${fc_reports}/04h_pg_stitch.rep w]
puts $fh "================================================================"
puts $fh " Post-route PG rail rebind — top_ahb_qspi"
puts $fh " (connectivity root-fixed by the 25 um M5/M6 init mesh)"
puts $fh "================================================================"
puts $fh ""
puts $fh " floating std cells   VDD     VSS"
puts $fh " -----------------   -----   -----"
puts $fh " baseline (route)    [format %5s $b_vdd]   [format %5s $b_vss]"
puts $fh " after PG + reroute  [format %5s $p_vdd]   [format %5s $p_vss]"
puts $fh ""
puts $fh " check_routes DRCs:  post-stitch $r_pre  ->  post-reroute $r_post"
puts $fh ""
puts $fh " Detail: 04f_pg_baseline / 04g_pg_post (PG conn);"
puts $fh "         04g0_pg_routes_pre / 04g1_pg_routes_post (route DRC)"
puts $fh " Hard gates (7_drc.tcl): check_pg_connectivity=0 AND"
puts $fh " check_routes converged."
puts $fh "================================================================"
close $fh
puts "INFO: \[fc_pg\] floating std cells: route VDD=$b_vdd VSS=$b_vss -> post VDD=$p_vdd VSS=$p_vss"

#-----------------------------------------------------------------------------
# Save block: ${design_lib}/${top}/pg.design  (consumed by 5_signoff.tcl)
#-----------------------------------------------------------------------------
save_block
save_lib   $design_lib_name
save_block -as ${design_lib_name}:${top_module}/pg.design

puts "FC_STAGE_OK: pg"
exit
