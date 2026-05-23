#-----------------------------------------------------------------------------
# Formality LEC — RTL (reference) vs post-layout netlist (implementation)
#
# Invoked from the Formality Makefile via:
#   fm_shell -file scripts/run_lec.tcl
#
# Environment variables (exported by the Makefile + common.mk):
#   MODULE                top module name (top_ahb_qspi)
#   FLIST                 RTL filelist (the same one synthesis read)
#   FC_OUTPUTS            where FC wrote the gate netlist + SVF
#   FC_WORK               where legacy unnamed default-*.svf live (fallback)
#   SOCLABS_AHB_QSPI_DIR  repo root (for $-expansion in the flist)
#   ARM_IP_LIBRARY_PATH   ARM IP root (referenced by the flist)
#   TARGET_LIB            stdcell .db (slow corner — link/tech library)
#   MEM_DBS_SS            memory macro .db's (space-separated)
#   FM_REPORTS            where to drop human-readable reports
#-----------------------------------------------------------------------------

set top_module   $::env(MODULE)
set flist        $::env(FLIST)
set fc_outputs   $::env(FC_OUTPUTS)
set fm_reports   $::env(FM_REPORTS)

set netlist      ${fc_outputs}/${top_module}.v
set svf_dir      ${fc_outputs}/svf

#-----------------------------------------------------------------------------
# Auto-blackbox unresolved modules — flash_cache_data + flash_cache_tag
# arrive as Verilog stubs from /research/precompiled_mems/TSMC65/. For LEC
# purposes memory cells are correctly opaque: their I/O ports must match
# on both sides, but the storage element itself is uninteresting.
#-----------------------------------------------------------------------------
set hdlin_unresolved_modules black_box

#-----------------------------------------------------------------------------
# Belt-and-braces: ICG insertion is disabled in the FC flow
# (setup_design_options.tcl marks PREICG_*/ICGT_* dont_use), so the
# implementation netlist contains no ICG cells. Set the CG hold mode
# anyway so any future CG cells that slip through still get matched.
#   - low: handles latch-based ICGs (PREICG_*) plus latch-free CGs at
#          the "before-edge" hold model.
#-----------------------------------------------------------------------------
set verification_clock_gate_hold_mode low

# Treat undriven nets the way Design Compiler / FC do — i.e. force them
# to logic 0 — so blackbox input pins that the RTL leaves unconnected
# (cache_ram.v doesn't wire flash_cache_tag's GWEN port) match the
# implementation, which the synth tool ties to the same default.
# Recommended directly by Formality's analyze_points -all output for
# the GWEN unmatched-cone-input case.
set verification_set_undriven_signals synthesis

#-----------------------------------------------------------------------------
# Tech / link libraries — Formality needs the cell models on both sides.
# read_db loads them once into both the reference and implementation
# containers (default behaviour: when no -r/-i is given, libs go to both).
#-----------------------------------------------------------------------------
read_db $::env(TARGET_LIB)
foreach db [split $::env(MEM_DBS_SS) " "] {
    if {$db ne ""} { read_db $db }
}

#-----------------------------------------------------------------------------
# SVF guidance. Two options, in priority order:
#  1) Per-stage named SVFs at $FC_OUTPUTS/svf/$top.{init,synth,cts,route}.svf
#     (produced by the stage scripts). Read in stage order.
#  2) None — Formality often passes without guidance for designs that
#     didn't see retiming or sequential merging.
# set_svf must be called BEFORE the implementation netlist is read.
#-----------------------------------------------------------------------------
set svfs [list]
foreach stage {init synth cts route signoff} {
    set f ${svf_dir}/${top_module}.${stage}.svf
    if {[file exists $f]} { lappend svfs $f }
}
if {[llength $svfs] > 0} {
    # IMPORTANT: set_svf REPLACES the SVF list on each call (it does not
    # append). Pass every stage's SVF as a single multi-arg invocation so
    # all of them are honoured; otherwise only the last one is consumed
    # and synthesis-stage transformations (clock-gating, retiming, etc.)
    # cause spurious "not equivalent" failures at verify time.
    puts "INFO: set_svf [llength $svfs] file(s):"
    foreach f $svfs { puts "INFO:   $f" }
    set_svf {*}$svfs
} else {
    puts "WARNING: no SVF guidance found — LEC will rely on auto-matching."
}

#-----------------------------------------------------------------------------
# Parse the RTL filelist (same logic as syn/asic/scripts/*.FC.read_design.tcl)
#-----------------------------------------------------------------------------
set include_dirs   [list]
set defines        [list]
set verilog_files  [list]
set sverilog_files [list]

proc parse_flist {filepath} {
    upvar include_dirs include_dirs
    upvar defines defines
    upvar verilog_files verilog_files
    upvar sverilog_files sverilog_files

    set fp [open $filepath r]
    while {[gets $fp line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string match "//*" $line] \
                || [string index $line 0] eq "#"} { continue }

        # Expand ${VAR} and $(VAR)
        set skip 0
        while {[regexp {\$\{(\w+)\}|\$\((\w+)\)} $line -> v1 v2]} {
            set v [expr {$v1 ne "" ? $v1 : $v2}]
            if {[info exists ::env($v)]} {
                set line [regsub {\$[\{\(]\w+[\}\)]} $line $::env($v)]
            } else {
                puts "WARNING: env $v unset, dropping: $line"
                set skip 1; break
            }
        }
        if {$skip} { continue }

        if {[string match "+incdir+*" $line]} {
            lappend include_dirs [string range $line 8 end]; continue
        }
        if {[string match "+define+*" $line]} {
            lappend defines [string range $line 8 end]; continue
        }
        if {[string match "+libext+*" $line]} { continue }
        if {[string match "-f *" $line] || [string match "-f\t*" $line]} {
            set nested [string trim [string range $line 2 end]]
            if {[file exists $nested]} {
                parse_flist $nested
            } else {
                puts "WARNING: nested flist missing: $nested"
            }
            continue
        }
        if {[string match "*.sv" $line]} {
            lappend sverilog_files $line
        } elseif {[string match "*.v" $line]} {
            lappend verilog_files $line
        }
    }
    close $fp
}

parse_flist $flist

# Drop the precompiled SRAM behavioural models from the reference RTL set.
# Both flash_cache_data.v and flash_cache_tag.v contain INITIAL statements
# and use non-local variables in tasks/functions (FMR_VLOG-091/-101) —
# legitimate sim-only constructs that trigger the "RTL interpretation
# messages were produced during read" gate (FM-089) and abort elaboration.
# `hdlin_unresolved_modules black_box` (set above) makes Formality treat
# them as opaque cells, which is what LEC wants for memory macros anyway:
# the I/O ports must match on both sides, but the storage element itself
# is uninteresting.
set rtl_skip_re {flash_cache_(data|tag)\.v$}
set verilog_files [lsearch -all -inline -not -regexp $verilog_files $rtl_skip_re]

puts "INFO: reference RTL: [llength $verilog_files] .v + [llength $sverilog_files] .sv"

# Apply +incdir+ via search_path (Formality uses the same global as fc_shell)
if {[llength $include_dirs] > 0} {
    set search_path [concat $search_path $include_dirs]
}

#-----------------------------------------------------------------------------
# Reference: RTL. Read everything as SystemVerilog to match what FC's
# shared FC.read_design.tcl does — keeps the .v/.sv mix in
# ahb_QSPI_ASIC.flist on a single parser.
#-----------------------------------------------------------------------------
set all_rtl [concat $verilog_files $sverilog_files]
if {[llength $all_rtl] == 0} {
    error "no RTL files found in $flist"
}

if {[llength $defines] > 0} {
    read_sverilog -r -define $defines $all_rtl
} else {
    read_sverilog -r $all_rtl
}
set_top r:/WORK/${top_module}

#-----------------------------------------------------------------------------
# Implementation: gate-level netlist from FC. Plain Verilog-2001.
#-----------------------------------------------------------------------------
if {![file exists $netlist]} {
    error "implementation netlist not found: $netlist  (run `make fc` first)"
}
puts "INFO: implementation netlist: $netlist"
read_verilog -i $netlist
set_top i:/WORK/${top_module}

#-----------------------------------------------------------------------------
# Match + verify
#-----------------------------------------------------------------------------
file mkdir $fm_reports

puts "INFO: match"
match
redirect ${fm_reports}/01_match.rep      { report_matched_points }
redirect ${fm_reports}/02_unmatched.rep  { report_unmatched_points }

puts "INFO: verify"
set verify_status [verify]

redirect ${fm_reports}/03_verify_summary.rep { report_status }
redirect ${fm_reports}/04_failing.rep        { report_failing_points }
redirect ${fm_reports}/05_aborted.rep        { report_aborted_points }

# When verify fails, dump analyze_points so the report tells us *why*
# (Formality's own root-cause analysis). Useful for distinguishing
# clock-gating / scan-mux equivalence issues from real RTL/netlist
# divergence.
if {$verify_status != 1} {
    puts "INFO: analyze_points (root-cause analysis for failing points)"
    redirect ${fm_reports}/06_analyze_points.rep { analyze_points -all }
}

# verify returns 1 on success, 0 on failure. Translate to a shell exit
# code (0 = pass) for Make.
if {$verify_status == 1} {
    puts "FM_LEC_OK: $top_module"
    exit 0
} else {
    puts "FM_LEC_FAIL: $top_module — see ${fm_reports}/04_failing.rep + ${fm_reports}/06_analyze_points.rep"
    exit 1
}
