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
# The deep-dive's earlier hand-off proposed a post-route *rail* rebuild.
# That was probed (pg_postroute_probe.tcl, 2026-05-18) and proven
# INEFFECTIVE on its own (814/487 unchanged — the rail is bound, the
# missing thing is a vertical via path, not rail logic). The same probe
# then validated the deep-dive's *alternative*: add a channel-confined
# fine-pitch M3 vertical stitch post-route, against the final routed
# block, so every orphaned M1 segment gets a frequent via path up to
# the mesh. Measured: 814/487 -> 18/0 floating (VSS fully clean, VDD
# -98%) with compile_pg completing cleanly. This stage productionises
# that result.
#
# Pitch sweep (pg_postroute_probe.tcl, 2026-05-18, on the real
# route.design): 6 µm -> VDD 18 / VSS 0 ; 3 µm -> VDD 0 / VSS 0.
# 3 µm fully closes check_pg_connectivity. Override via PG_M3_PITCH if
# a coarser stitch is wanted for routing-resource reasons; the
# downstream 7_drc.tcl check_pg_connectivity hard-gate (requires 0) is
# the real pass/fail.
#-----------------------------------------------------------------------------

set top_module       $::env(MODULE)
set design_lib_name  "${top_module}.dlib"
set fc_dir           $::env(FC_DIR)
set fc_logs          $::env(FC_LOGS)
set fc_reports       $::env(FC_REPORTS)

file mkdir $fc_reports

# M3 stitch pitch (µm). 3.0 is the validated value that fully closes
# check_pg_connectivity (814/487 -> 0/0). Override via env if needed.
set m3_pitch 3.0
if {[info exists ::env(PG_M3_PITCH)]} { set m3_pitch $::env(PG_M3_PITCH) }

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
# Recreate the std-cell rail pattern + the fine-pitch M3 vertical stitch
# and bind both to VDD/VSS. Init-stage patterns/strategies do NOT persist
# across save_block/open_block (established by the deep-dive), so they
# are rebuilt here against the routed block. The M3 spec MUST be built
# with "" so $m3_pitch interpolates (fc_shell needs a numeric pitch).
#-----------------------------------------------------------------------------
puts "INFO: \[fc_pg\] (re)creating std_cell_rail + M3 stitch (pitch=${m3_pitch}um)"
catch {remove_pg_patterns   -all}
catch {remove_pg_strategies -all}

create_pg_std_cell_conn_pattern std_cell_rail \
    -layers {M1} \
    -rail_width 0.18

set_pg_strategy rail_strategy \
    -pattern {{name: std_cell_rail} {nets: {VDD VSS}}} \
    -core

set m3_spec "{vertical_layer: M3} {width: 0.4} {pitch: $m3_pitch} {spacing: interleaving} {offset: 5.0} {trim: true}"
create_pg_mesh_pattern m3_stitch -layers [list $m3_spec]

set_pg_strategy m3_stitch_strategy \
    -pattern {{name: m3_stitch} {nets: {VDD VSS}}} \
    -core

puts "INFO: \[fc_pg\] connect_pg_net -automatic"
catch {connect_pg_net -automatic}

#-----------------------------------------------------------------------------
# Synthesize the post-route rail + M3-stitch PG. Guarded: a compile_pg
# failure must NOT silently hand a still-floating block to signoff —
# fail the stage loudly (no FC_STAGE_OK marker) so make stops here.
#-----------------------------------------------------------------------------
puts "INFO: \[fc_pg\] compile_pg -strategies {rail_strategy m3_stitch_strategy}"
if {[catch {compile_pg -strategies {rail_strategy m3_stitch_strategy}} pg_err]} {
    puts "ERROR: \[fc_pg\] compile_pg failed: $pg_err"
    puts "ERROR: \[fc_pg\] $::errorInfo"
    puts "ERROR: \[fc_pg\] not touching FC_STAGE_OK — route.design left intact."
    exit 1
}

#-----------------------------------------------------------------------------
# Co-manage PG-vs-signal DRC (REQUIRED). compile_pg above adds the
# fine-pitch M3 stitch + rails ON TOP of the already-routed signals;
# without re-routing, the new PG metal collides with M3 signal routing
# and check_routes explodes (measured: 15 -> ~48k in the first fc_all).
# This is exactly the interaction INTEGRATION_CHANGES.md flagged. Mirror
# 4_route.tcl's proven convergence: an ECO route_opt then an incremental
# detail-route, with the freshly-created PG geometry now seen as an
# obstacle so the router legalises signals around it. PG special-route
# nets are untouched by signal detail-route, so connectivity (verified
# again below) is preserved.
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
puts $fh " Post-route PG rail + M3-stitch — top_ahb_qspi"
puts $fh " M3 vertical stitch pitch = ${m3_pitch} um"
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
