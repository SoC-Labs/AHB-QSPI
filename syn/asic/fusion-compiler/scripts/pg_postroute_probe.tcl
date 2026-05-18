#-----------------------------------------------------------------------------
# pg_postroute_probe.tcl  —  NON-DESTRUCTIVE diagnostic for Blocker 1.
#
# Implements the "Concrete fix recipe for the owner" step 1 from
# syn/asic/fusion-compiler/INTEGRATION_CHANGES.md ("PG floating-cell
# deep-dive"): reproduce the post-route std-cell-rail + mesh-stitch
# compile_pg against the *final routed* layout and capture the EXACT
# failing command/object that earlier non-interactive attempts only
# saw as "errored mid-run" with the error swallowed by a catch.
#
# Differences vs. the reverted attempt #3:
#   * operates on a COPY of route.design (pg_probe.design) — never
#     touches route/signoff/drc blocks, so it is safe to run anytime;
#   * does NOT swallow the compile_pg error — captures $errorInfo,
#     $errorCode and the surrounding fc state, and dumps a full
#     before/after check_pg_connectivity so the abort point is visible
#     from a batch log (no GUI needed for the diagnosis itself);
#   * single clean attempt — the point is the diagnosis, not a fix.
#
# Run:  make fc_pg_probe         (wrapper target; ~6 min on the runner)
# Out:  reports/pg_postroute_probe.rep   + PGPROBE_* grep markers
#-----------------------------------------------------------------------------

set top_module       $::env(MODULE)
set design_lib_name  "${top_module}.dlib"
set fc_dir           $::env(FC_DIR)
set fc_logs          $::env(FC_LOGS)
set fc_reports       $::env(FC_REPORTS)

file mkdir $fc_reports
set rpt ${fc_reports}/pg_postroute_probe.rep

#-----------------------------------------------------------------------------
# Open a scratch COPY of the post-route checkpoint. copy_block keeps
# route.design pristine; all PG work below lands only on pg_probe.design.
#-----------------------------------------------------------------------------
open_lib $design_lib_name

if {[catch {
        copy_block -from ${design_lib_name}:${top_module}/route.design \
                   -to   ${design_lib_name}:${top_module}/pg_probe.design
} cp_err]} {
    # -to already exists from an earlier probe → just reopen and overwrite
    puts "INFO: \[pg_probe\] copy_block note: $cp_err (reusing scratch block)"
}
open_block ${design_lib_name}:${top_module}/pg_probe.design

source ${fc_dir}/scripts/setup.tcl
source ${fc_dir}/scripts/setup_design_options.tcl

#-----------------------------------------------------------------------------
# Baseline connectivity (what route.design hands to signoff today).
#-----------------------------------------------------------------------------
puts "PGPROBE: baseline check_pg_connectivity"
redirect -tee -file ${fc_reports}/pg_probe_00_baseline.rep {
    catch {check_pg_connectivity} _b
}

#-----------------------------------------------------------------------------
# Recreate ONLY the std-cell rail pattern + rail strategy. The
# INTEGRATION_CHANGES diagnosis established that init-stage patterns/
# strategies do NOT persist across save_block/open_block, so they must
# be rebuilt here against the routed block. Mirrors pg_mesh.tcl steps
# 3 + 6 (rail only — the M5/M6 mesh + macro straps are already in the
# block from the init-stage compile_pg and are NOT rebuilt).
#-----------------------------------------------------------------------------
puts "PGPROBE: recreating std_cell_rail pattern + rail_strategy"
catch {remove_pg_patterns   -all} _rp
catch {remove_pg_strategies -all} _rs

create_pg_std_cell_conn_pattern std_cell_rail \
    -layers {M1} \
    -rail_width 0.18

set_pg_strategy rail_strategy \
    -pattern {{name: std_cell_rail} {nets: {VDD VSS}}} \
    -core

# ── Optional experimental arm: channel-confined fine-pitch M3 vertical
#    stitch (INTEGRATION_CHANGES.md deep-dive "Alternative"). The pure
#    rail arm above was proven INEFFECTIVE by the 2026-05-18 probe run
#    (814/487 unchanged, floating wires worse) — so the rail is bound,
#    the missing thing is a via path from the orphaned M1 segments up
#    to the M5/M6 mesh. This arm adds a fine-pitch M3 vertical strap so
#    every M1 segment in the macro-fragmented channel gets a frequent
#    via path up. Off by default (PG_PROBE_M3=1 enables); pitch tunable
#    via PG_M3_PITCH (µm). M3 chosen over M2 because the original author
#    abandoned M2 for std-cell pin-access contention (see deep-dive).
set use_m3 0
if {[info exists ::env(PG_PROBE_M3)] && $::env(PG_PROBE_M3) eq "1"} {
    set use_m3 1
}
set m3_pitch 6.0
if {[info exists ::env(PG_M3_PITCH)]} { set m3_pitch $::env(PG_M3_PITCH) }

if {$use_m3} {
    puts "PGPROBE: adding experimental M3 vertical stitch pitch=${m3_pitch}um"
    # NOTE: the layer spec MUST be built with "" (not {}) so $m3_pitch
    # interpolates — fc_shell's create_pg_mesh_pattern then receives a
    # numeric pitch. -layers takes a list whose single element is the
    # brace-group spec string (mirrors pg_mesh.tcl's mesh_m5_m6 shape).
    set m3_spec "{vertical_layer: M3} {width: 0.4} {pitch: $m3_pitch} {spacing: interleaving} {offset: 5.0} {trim: true}"
    set m3_rc [catch {
        create_pg_mesh_pattern m3_stitch -layers [list $m3_spec]
        set_pg_strategy m3_stitch_strategy \
            -pattern {{name: m3_stitch} {nets: {VDD VSS}}} \
            -core
    } m3_err]
    if {$m3_rc != 0} {
        puts "PGPROBE_M3_SETUP_FAIL: $m3_err"
        puts "PGPROBE: falling back to rail-only so the probe still reports"
        set _pg_strats {rail_strategy}
        set use_m3 0
    } else {
        set _pg_strats {rail_strategy m3_stitch_strategy}
    }
} else {
    set _pg_strats {rail_strategy}
}

puts "PGPROBE: connect_pg_net -automatic (re-tie leaf PG pins)"
catch {connect_pg_net -automatic} _cn

#-----------------------------------------------------------------------------
# THE diagnostic: post-route PG compile_pg, error captured in full.
# Default arm = rail only (the 2026-05-18 baseline). PG_PROBE_M3=1 adds
# the M3 channel stitch. Print errorInfo/errorCode so the exact failing
# command/object lands in the batch log.
#-----------------------------------------------------------------------------
puts "PGPROBE: compile_pg -strategies {$_pg_strats}  (full error capture)"
set pg_rc [catch {compile_pg -strategies $_pg_strats} pg_err]

if {$pg_rc != 0} {
    puts "PGPROBE_FAIL: compile_pg returned non-zero"
    puts "PGPROBE_ERR_MSG : $pg_err"
    puts "PGPROBE_ERR_CODE: $::errorCode"
    puts "PGPROBE_ERR_INFO_BEGIN"
    puts $::errorInfo
    puts "PGPROBE_ERR_INFO_END"
} else {
    puts "PGPROBE_OK: compile_pg -strategies {rail_strategy} completed"
}

#-----------------------------------------------------------------------------
# Post-attempt state — connectivity + strategy/pattern dump regardless
# of whether compile_pg aborted, so the abort point is characterised.
#-----------------------------------------------------------------------------
puts "PGPROBE: post check_pg_connectivity + strategy dump"
redirect -tee -file ${fc_reports}/pg_probe_01_post.rep {
    catch {check_pg_connectivity} _p
    catch {report_pg_strategies}  _ps
    catch {report_pg_patterns}    _pp
}

#-----------------------------------------------------------------------------
# Consolidated, grep-able summary.
#-----------------------------------------------------------------------------
# check_pg_connectivity prints a VDD block then a VSS block, each with
# one "Number of floating std cells: N" line (same parse 7_drc.tcl
# uses). Collect them in order: index 0 = VDD, index 1 = VSS. The
# earlier "Verify net .*? floating std cells" regex misparsed (returned
# a stray single digit) — match the canonical line directly instead.
proc _float {f idx} {
    if {![file exists $f]} { return "?" }
    set fh [open $f r]; set txt [read $fh]; close $fh
    set hits [regexp -all -inline {Number of floating std cells:\s*(\d+)} $txt]
    # regexp -all -inline returns {match cap match cap ...}; caps are odd
    set caps [list]
    foreach {m c} $hits { lappend caps $c }
    if {[llength $caps] > $idx} { return [lindex $caps $idx] }
    return "?"
}
set b_vdd [_float ${fc_reports}/pg_probe_00_baseline.rep 0]
set b_vss [_float ${fc_reports}/pg_probe_00_baseline.rep 1]
set p_vdd [_float ${fc_reports}/pg_probe_01_post.rep     0]
set p_vss [_float ${fc_reports}/pg_probe_01_post.rep     1]

set fh [open $rpt w]
puts $fh "================================================================"
puts $fh " Post-route PG rail-stitch probe — top_ahb_qspi"
puts $fh " (non-destructive: operated on pg_probe.design, route.design"
puts $fh "  / signoff.design / drc.design untouched)"
puts $fh "================================================================"
puts $fh ""
puts $fh " floating std cells   VDD     VSS"
puts $fh " -----------------   -----   -----"
puts $fh " baseline (route)    [format %5s $b_vdd]   [format %5s $b_vss]"
puts $fh " after rail compile  [format %5s $p_vdd]   [format %5s $p_vss]"
puts $fh ""
if {$pg_rc != 0} {
    puts $fh " compile_pg: ABORTED — see PGPROBE_ERR_* in the stage log"
    puts $fh "   $pg_err"
} else {
    puts $fh " compile_pg: completed"
}
puts $fh ""
puts $fh " Detail: reports/pg_probe_00_baseline.rep (pre)"
puts $fh "         reports/pg_probe_01_post.rep     (post + strategy dump)"
puts $fh " Stage log carries the full errorInfo for the failing command."
puts $fh "================================================================"
close $fh

puts "PGPROBE_BASELINE_FLOAT: VDD=$b_vdd VSS=$b_vss"
puts "PGPROBE_POST_FLOAT:     VDD=$p_vdd VSS=$p_vss"
puts "PGPROBE_RESULT:         compile_pg_rc=$pg_rc"
puts ""
puts "FC_STAGE_OK: pg_probe"
exit
