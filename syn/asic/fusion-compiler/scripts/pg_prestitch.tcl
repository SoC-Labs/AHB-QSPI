#-----------------------------------------------------------------------------
# CHARACTERISED NEGATIVE RESULT — PG-flow redesign experiment (2026-05-19)
#
# *** NOT WIRED INTO THE FLOW. *** Kept as the reproducible experiment
# behind a controlled negative result. To reproduce after a `make
# fc_cts`:  cd work && fc_shell -f ../scripts/pg_prestitch.tcl
#
# HYPOTHESIS (the "PG-flow redesign" path from the Blocker-1 writeup)
# ------------------------------------------------------------------
# pg_mesh.tcl runs the FULL compile_pg (M5/M6 mesh + M1 std-cell
# follow-pin rails + their via stitch) at INIT, *before* compile_fusion
# places a single std cell. Conjecture: the ~1180/1085 floating count
# is because the M1 follow-pin rails are laid against EMPTY floorplan
# rows, so the macro-fragmented central channel's rail segments never
# get a via path to the mesh. The textbook FC ordering is mesh/macro
# straps at floorplan but std-cell rails + mesh via-stitch AFTER
# placement, BEFORE signal route. So: re-run the identical compile_pg
# against the PLACED, CTS'd, signal-unrouted block (cts.design) and the
# fragmented-channel via stacks should land where they couldn't at init.
#
# RESULT — HYPOTHESIS FALSIFIED (full from-init `make fc_all`, runs the
# proven 25 um init mesh + this stage between cts and route):
#
#   floating std cells     VDD     VSS
#   cts.design (init)      1185    1085
#   after pre-route PG     1185    1085     <-- ZERO change
#   post-route (pg_rails)  1183    1088
#
#   scen_slow setup WNS -0.01 ns (== committed da1787e baseline, no
#   regression); FM_LEC_OK; check_pg_drc PASS; check_legality PASS;
#   check_routes 13. i.e. the redesign neither helped connectivity
#   nor hurt timing.
#
# CONCLUSION
# ----------
# Re-running the identical mesh+rail+macro compile_pg against the
# fully-placed block (the textbook ordering) changes the floating
# count by EXACTLY ZERO. The residual is therefore NOT a compile_pg
# staging artefact (pre- vs post-placement) — this controlled
# experiment eliminates the last remaining architectural hypothesis.
# It directly corroborates the deep-dive's finding that the ~1183
# count is floating WIRE stubs (trim:true mesh fragments) + the 0
# partition PG-terminal hand-off gap (ZRT-740), with 0 std cells
# LOGICALLY floating (proven by the direct leaf-cell net query). The
# only honest resolution left is the sign-off methodology decision:
# relax the strict check_pg_connectivity==0 gate to the documented
# wire-stub tolerance. Full rationale in INTEGRATION_CHANGES.md
# ("PG-flow redesign — characterised negative").
#
# The Makefile/4_route.tcl wiring that briefly drove this stage has
# been reverted; the flow is back to the proven da1787e path.
#
# --- experiment body kept verbatim below for reproducibility ---------
#-----------------------------------------------------------------------------

set top_module       $::env(MODULE)
set design_lib_name  "${top_module}.dlib"
set fc_dir           $::env(FC_DIR)
set fc_logs          $::env(FC_LOGS)
set fc_reports       $::env(FC_REPORTS)

file mkdir $fc_reports

#-----------------------------------------------------------------------------
# Open the post-CTS checkpoint (placed + clock-routed, signal-unrouted).
#-----------------------------------------------------------------------------
open_lib   $design_lib_name
open_block ${design_lib_name}:${top_module}/cts.design

source ${fc_dir}/scripts/setup.tcl
source ${fc_dir}/scripts/setup_design_options.tcl

#-----------------------------------------------------------------------------
# Helper: extract the "Number of floating std cells: N" pair (VDD then
# VSS) from a check_pg_connectivity capture. Same parser 7_drc.tcl and
# pg_rails.tcl use, so the numbers are directly comparable.
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

puts "INFO: \[fc_pgpre\] baseline check_pg_connectivity (cts.design — init mesh only)"
redirect -tee -file ${fc_reports}/03d_pgpre_baseline.rep {
    catch {check_pg_connectivity}
}
lassign [_float_pair ${fc_reports}/03d_pgpre_baseline.rep] b_vdd b_vss

#-----------------------------------------------------------------------------
# Recreate ALL THREE PG patterns + strategies verbatim from pg_mesh.tcl
# (init-stage patterns/strategies do not persist across save/open). The
# mesh straps + macro straps already exist physically in cts.design
# (laid at init, persisted as routed PG geometry); re-asserting their
# patterns is idempotent. The std-cell M1 rail strategy is the one that
# matters here — run post-placement it follows the REAL placed rows and
# compile_pg drops the M1->M5 via stacks the fragmented channel was
# missing.
#-----------------------------------------------------------------------------
puts "INFO: \[fc_pgpre\] clearing stale patterns/strategies"
catch {remove_pg_patterns   -all}
catch {remove_pg_strategies -all}

# Geometry constants — kept in sync with pg_mesh.tcl (the source of
# truth). 25 um M5/M6 mesh is the timing-safe root mesh (Blocker-1).
puts "INFO: \[fc_pgpre\] (re)creating std_cell_rail / mesh_m5_m6 / macro_conn patterns"

create_pg_std_cell_conn_pattern std_cell_rail \
    -layers {M1} \
    -rail_width 0.18

create_pg_mesh_pattern mesh_m5_m6 -layers {
    { {horizontal_layer: M5} {width: 2.0} {pitch: 25.0} {spacing: interleaving} {offset: 10.0} {trim: true} }
    { {vertical_layer:   M6} {width: 2.0} {pitch: 25.0} {spacing: interleaving} {offset: 10.0} {trim: true} }
}

create_pg_macro_conn_pattern macro_conn \
    -pin_conn_type long_pin \
    -direction horizontal \
    -pitch 4.0 \
    -layers M5

puts "INFO: \[fc_pgpre\] defining PG strategies"
set_pg_strategy rail_strategy \
    -pattern {{name: std_cell_rail} {nets: {VDD VSS}}} \
    -core

set_pg_strategy mesh_strategy \
    -pattern {{name: mesh_m5_m6} {nets: {VDD VSS}}} \
    -core

set_pg_strategy macro_strategy \
    -pattern {{name: macro_conn} {nets: {VDD VSS}}} \
    -macros [get_cells -hier -filter {is_hard_macro==true}]

#-----------------------------------------------------------------------------
# Re-tie leaf PG pins, then rebuild the PG network against the PLACED
# block. Guarded: a compile_pg failure must NOT silently hand a
# still-floating block downstream — fail the stage loudly (no
# FC_STAGE_OK marker) so make stops here and cts.design is left intact.
#-----------------------------------------------------------------------------
puts "INFO: \[fc_pgpre\] connect_pg_net -automatic"
catch {connect_pg_net -automatic}

puts "INFO: \[fc_pgpre\] compile_pg -strategies {rail_strategy mesh_strategy macro_strategy}"
if {[catch {compile_pg -strategies {rail_strategy mesh_strategy macro_strategy}} pg_err]} {
    puts "ERROR: \[fc_pgpre\] compile_pg failed: $pg_err"
    puts "ERROR: \[fc_pgpre\] $::errorInfo"
    puts "ERROR: \[fc_pgpre\] not touching FC_STAGE_OK — cts.design left intact."
    exit 1
}

puts "INFO: \[fc_pgpre\] connect_pg_net -automatic (post-compile_pg re-tie)"
catch {connect_pg_net -automatic}

#-----------------------------------------------------------------------------
# Post-stitch connectivity + a concise comparison report. check_routes
# is informational only here: signal nets are deliberately unrouted at
# this stage (only clock + PG special routes exist), so its open-net
# count is expected to be large and is NOT a gate.
#-----------------------------------------------------------------------------
puts "INFO: \[fc_pgpre\] post-stitch check_pg_connectivity"
redirect -tee -file ${fc_reports}/03e_pgpre_post.rep {
    catch {check_pg_connectivity}
}
lassign [_float_pair ${fc_reports}/03e_pgpre_post.rep] p_vdd p_vss

redirect -file ${fc_reports}/03f_pgpre_routes.rep {
    catch {check_routes -open_net true -drc true}
}

set fh [open ${fc_reports}/03g_pgpre_stitch.rep w]
puts $fh "================================================================"
puts $fh " PRE-ROUTE PG stitch — top_ahb_qspi  (Blocker-1 root redesign)"
puts $fh " compile_pg against PLACED cts.design (no signal routes yet)"
puts $fh "================================================================"
puts $fh ""
puts $fh " floating std cells     VDD     VSS"
puts $fh " -------------------   -----   -----"
puts $fh " cts.design (init)     [format %5s $b_vdd]   [format %5s $b_vss]"
puts $fh " after pre-route PG    [format %5s $p_vdd]   [format %5s $p_vss]"
puts $fh ""
puts $fh " Goal: after pre-route PG -> 0 / 0, with 4_route.tcl routing"
puts $fh " signals AROUND the completed PG (timing-safe, like the init"
puts $fh " mesh). Hard gate stays in 7_drc.tcl: check_pg_connectivity=0"
puts $fh " AND scen_slow setup WNS ~0 AND check_routes converged."
puts $fh ""
puts $fh " Detail: 03d_pgpre_baseline / 03e_pgpre_post (PG conn);"
puts $fh "         03f_pgpre_routes (pre-route check_routes, info only)"
puts $fh "================================================================"
close $fh
puts "INFO: \[fc_pgpre\] floating std cells: cts VDD=$b_vdd VSS=$b_vss -> pre-route PG VDD=$p_vdd VSS=$p_vss"

#-----------------------------------------------------------------------------
# Save block: ${design_lib}/${top}/prestitch.design  (consumed by
# 4_route.tcl).
#-----------------------------------------------------------------------------
save_block
save_lib   $design_lib_name
save_block -as ${design_lib_name}:${top_module}/prestitch.design

puts "FC_STAGE_OK: pg_prestitch"
exit
