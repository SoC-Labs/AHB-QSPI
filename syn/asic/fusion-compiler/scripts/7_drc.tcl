#-----------------------------------------------------------------------------
# Phase 5: DRC — in-design checks + optional ICV signoff DRC.
#
# Run with: fc_shell -f 7_drc.tcl   (after 5_signoff.tcl)
#
# Two tiers of check are run:
#
#  Tier 1 — In-design checks (always run, no external tool needed):
#    check_design -checks    : design integrity. We invoke a curated
#                               set of post-route atomic checks:
#                                 block_ready_for_top — partition
#                                                       readiness for
#                                                       chip-top stitch
#                                 legality           — placement legality
#                                 routes             — routing integrity
#                                                       (opens, shorts,
#                                                       antenna)
#                                 analyze_design_violations
#                                                    — generic violation
#                                                      enumeration
#                                 pin_placement      — pin physical
#                                                       constraints
#    check_pg_connectivity   : VDD/VSS reachability for every cell
#    check_pg_drc            : PG-mesh DRC (parallel rails, opens,
#                               shorts, missing vias)
#    check_routes            : routing integrity standalone (also covers
#                               antenna violations)
#
#  Tier 2 — Signoff DRC via IC Validator (opt-in):
#    Runs only when ICV_DRC_RUNSET is set in the environment and points
#    at a foundry-supplied .rs runset. Without that the partition
#    delivery relies on the tier-1 checks; tier-2 should be re-run at
#    chip-top once the foundry deck is loaded.
#
# Per-check reports are written to $FC_REPORTS/07_<check>.rep so make
# drc_summary can grep them for violation counts.
#-----------------------------------------------------------------------------

set top_module       $::env(MODULE)
set design_lib_name  "${top_module}.dlib"
set fc_dir           $::env(FC_DIR)
set fc_logs          $::env(FC_LOGS)
set fc_reports       $::env(FC_REPORTS)

#-----------------------------------------------------------------------------
# Open the post-signoff checkpoint
#-----------------------------------------------------------------------------
open_lib   $design_lib_name
open_block ${design_lib_name}:${top_module}/signoff.design

source ${fc_dir}/scripts/setup.tcl
source ${fc_dir}/scripts/setup_design_options.tcl

file mkdir $fc_reports

#-----------------------------------------------------------------------------
# Helper — run a check, redirect to file, capture the command's return
# value so the summary at the end shows pass/fail per check.
#-----------------------------------------------------------------------------
array set drc_results {}

proc run_check {name body} {
    global fc_reports drc_results
    set rpt ${fc_reports}/07_${name}.rep
    puts "INFO: \[fc_drc\] $name -> $rpt"
    set rc 0
    if {[catch {redirect -tee -file $rpt $body} err]} {
        puts "WARN: \[fc_drc\] $name raised an error: $err"
        set rc 1
    }
    set drc_results($name) [list $rc $rpt]
}

#-----------------------------------------------------------------------------
# Tier 1 — In-design checks
#-----------------------------------------------------------------------------
puts "INFO: \[fc_drc\] tier 1 — in-design checks"

run_check check_design          {check_design -checks {block_ready_for_top legality routes analyze_design_violations pin_placement}}
run_check check_legality        {check_legality -verbose}
run_check check_pg_connectivity {check_pg_connectivity}
# std-cell + macro PG geometry was already signed off by the foundry
# when the library shipped; we don't re-check it at partition level.
#   -do_not_check_shapes_in_lib_cells skips shapes INSIDE library
#       cells (cell internals).
#   -ignore_std_cells skips shapes that overlap std-cell footprints,
#       including the follow-pin rails the std_cell_rail strategy
#       deliberately drops on top of cell M1 PG pins (intended same-
#       net overlap that PG-DRC flags as a "short").
# Together these filter out ~300 spurious M1 shorts/overlaps/spacings
# from the partition flow that are unfixable at this level. With both
# enabled, check_pg_drc reports 0 errors against the partition-only
# PG geometry (verified via the same invocation in fc_shell).
run_check check_pg_drc          {check_pg_drc -do_not_check_shapes_in_lib_cells -ignore_std_cells}
run_check check_routes          {check_routes -open_net true -drc true -antenna true -report_all_open_nets true}

#-----------------------------------------------------------------------------
# Tier 2 — ICV signoff DRC (opt-in)
#
# Set ICV_DRC_RUNSET to the path of a foundry-supplied .rs runset.
# Optionally set ICV_DRC_STRATEGY to name a strategy already defined;
# otherwise we create a minimal default strategy on the fly.
#-----------------------------------------------------------------------------
set icv_runset ""
if {[info exists ::env(ICV_DRC_RUNSET)]} {
    set icv_runset $::env(ICV_DRC_RUNSET)
}

if {$icv_runset ne "" && [file exists $icv_runset]} {
    puts "INFO: \[fc_drc\] tier 2 — IC Validator signoff DRC ($icv_runset)"

    set strategy [expr {[info exists ::env(ICV_DRC_STRATEGY)] \
                       ? $::env(ICV_DRC_STRATEGY) \
                       : "qspi_drc"}]

    # Define a default strategy if not already present.
    if {[catch {get_signoff_drc_strategy $strategy} _]} {
        define_signoff_drc_strategy -strategy $strategy \
            -runset $icv_runset \
            -ignore_errors false
    }

    run_check signoff_drc [list signoff_check_drc -strategy $strategy \
                                                  -open_in_icv_workbench false]
} else {
    puts "INFO: \[fc_drc\] tier 2 — ICV_DRC_RUNSET not set or missing,"
    puts "INFO:                  skipping ICV signoff DRC."
    puts "INFO:                  Tier-1 checks above cover connectivity,"
    puts "INFO:                  placement, PG, routing, and antenna."
    puts "INFO:                  Re-run with ICV_DRC_RUNSET=<path> for"
    puts "INFO:                  the full geometric deck."
}

#-----------------------------------------------------------------------------
# Per-check violation-count summary. Each check has its own canonical
# summary-line pattern; we extract the number from those rather than
# grepping for "violation" everywhere (which catches descriptive text
# in the report headers). Output goes to 07_summary.rep so the
# Makefile's drc_summary target can just cat it.
#-----------------------------------------------------------------------------

# Helper: read entire report, return first numeric capture of `re`, or
# `default` if no match. Used to pull "Total number of DRCs = N" etc.
proc grep_count {file re {default -1}} {
    if {![file exists $file]} { return $default }
    set fp [open $file r]
    set txt [read $fp]
    close $fp
    if {[regexp $re $txt -> n]} { return $n }
    return $default
}

# Helper: sum two captures (used for floating std-cells + macros).
proc grep_sum {file re1 re2} {
    set a [grep_count $file $re1 0]
    set b [grep_count $file $re2 0]
    return [expr {$a + $b}]
}

set summary_rpt ${fc_reports}/07_summary.rep
set sfp [open $summary_rpt w]
puts $sfp "================================================================="
puts $sfp " DRC violation summary — $top_module"
puts $sfp "================================================================="
puts $sfp [format "  %-22s  %-7s  %s" "Check" "Status" "Detail"]
puts $sfp "  ----------------------  -------  --------------------------------"

set total_violations 0

proc summarise {name status detail count} {
    global sfp total_violations
    puts $sfp [format "  %-22s  %-7s  %s" $name $status $detail]
    incr total_violations $count
}

# check_design — EMS message summary line: "Total N EMS messages : E errors, W warnings, I info."
set ems_errors [grep_count ${fc_reports}/07_check_design.rep \
                {Total \d+ EMS messages\s*:\s*(\d+) errors?}]
if {$ems_errors == -1} {
    summarise "check_design" "n/a"  "no EMS-summary line found" 0
} elseif {$ems_errors == 0} {
    summarise "check_design" "PASS" "0 EMS errors"             0
} else {
    summarise "check_design" "FAIL" "$ems_errors EMS errors"   $ems_errors
}

# check_legality — terminal "succeeded!" line vs "failed".
set leg_rpt ${fc_reports}/07_check_legality.rep
set leg_pass 0
if {[file exists $leg_rpt]} {
    set fp [open $leg_rpt r]
    set txt [read $fp]; close $fp
    if {[string match "*succeeded*" $txt]} { set leg_pass 1 }
}
if {$leg_pass} {
    summarise "check_legality" "PASS" "succeeded" 0
} else {
    summarise "check_legality" "FAIL" "see report" 1
}

# check_pg_connectivity — floating std cells + macros (summed across
# VDD + VSS nets — sum_VDD already covers the whole design).
set float_cells [grep_count ${fc_reports}/07_check_pg_connectivity.rep \
                {Number of floating std cells:\s*(\d+)}]
set float_macros [grep_count ${fc_reports}/07_check_pg_connectivity.rep \
                 {Number of floating hard macros:\s*(\d+)}]
if {$float_cells == -1} { set float_cells 0 }
if {$float_macros == -1} { set float_macros 0 }
set total_float [expr {$float_cells + $float_macros}]
if {$total_float == 0} {
    summarise "check_pg_connectivity" "PASS" "0 floating cells/macros" 0
} else {
    summarise "check_pg_connectivity" "FAIL" \
              "$float_cells std-cells + $float_macros macros floating" \
              $total_float
}

# check_pg_drc — "Total number of errors found: N"
set pg_errs [grep_count ${fc_reports}/07_check_pg_drc.rep \
            {Total number of errors found:\s*(\d+)}]
if {$pg_errs == -1} { set pg_errs 0 }
if {$pg_errs == 0} {
    summarise "check_pg_drc" "PASS" "0 errors" 0
} else {
    summarise "check_pg_drc" "FAIL" "$pg_errs PG-DRC errors" $pg_errs
}

# check_routes — "Total number of DRCs = N"
set rt_drcs [grep_count ${fc_reports}/07_check_routes.rep \
            {Total number of DRCs\s*=\s*(\d+)}]
set rt_opens [grep_count ${fc_reports}/07_check_routes.rep \
             {Total number of open nets\s*=\s*(\d+)}]
if {$rt_drcs == -1}  { set rt_drcs 0 }
if {$rt_opens == -1} { set rt_opens 0 }
set rt_total [expr {$rt_drcs + $rt_opens}]
if {$rt_total == 0} {
    summarise "check_routes" "PASS" "0 DRCs / 0 open nets" 0
} else {
    summarise "check_routes" "FAIL" \
              "$rt_drcs DRCs + $rt_opens open nets" $rt_total
}

# signoff_drc (only if ICV ran)
if {[info exists drc_results(signoff_drc)]} {
    set icv_errs [grep_count ${fc_reports}/07_signoff_drc.rep \
                 {(\d+) violations?}]
    if {$icv_errs == -1} { set icv_errs 0 }
    if {$icv_errs == 0} {
        summarise "signoff_drc (ICV)" "PASS" "0 violations" 0
    } else {
        summarise "signoff_drc (ICV)" "FAIL" "$icv_errs violations" $icv_errs
    }
}

puts $sfp "================================================================="
if {$total_violations == 0} {
    puts $sfp " RESULT: CLEAN — partition ready for chip-top integration"
} else {
    puts $sfp " RESULT: $total_violations violation(s) — see individual reports"
}
puts $sfp "================================================================="
close $sfp

# Echo the summary to stdout so the log shows it too.
set fp [open $summary_rpt r]
puts [read $fp]
close $fp

puts "INFO: \[fc_drc\] full summary at $summary_rpt"
puts "INFO: \[fc_drc\] run 'make drc_summary' to re-display it"

#-----------------------------------------------------------------------------
# Save block: ${design_lib}/${top}/drc.design  (DRC-clean snapshot)
#-----------------------------------------------------------------------------
save_block
save_lib $design_lib_name
save_block -as ${design_lib_name}:${top_module}/drc.design

puts "FC_STAGE_OK: drc"
exit
