#-----------------------------------------------------------------------------
# PrimeTime ETM extraction — boundary timing model for the partition.
#
# Invoked from the PrimeTime Makefile via:
#   pt_shell -f scripts/extract_etm.tcl
#
# WHY THIS EXISTS
#   fc_shell U-2022.12 has no `write_lib_model -format etm`, so
#   6_partition_export.tcl can only hand the integrator the .dlib block
#   + per-scenario SPEF/SDF. That forces chip-top STA into NDM-based
#   hierarchical timing (FC-only). A PrimeTime ETM (.db/.lib) is the
#   tool-neutral boundary model an integrator actually wants. This is
#   the missing follow-on stage.
#
# SCAFFOLD STATUS
#   Not execution-verified — no pt_shell run in the authoring env.
#   Commands are standard PT 2022.12 (read_verilog / link_design /
#   read_parasitics / extract_model) and the env-var contract matches
#   syn/asic/common.mk + the FC flow. Validate on a real pt_shell run;
#   the Makefile greps PT_ETM_OK so a silent failure won't be missed.
#
# Environment (exported by the Makefile + common.mk):
#   MODULE        top module name (top_ahb_qspi)
#   FC_OUTPUTS    where FC wrote the gate netlist + per-scenario SPEF/SDC
#   PT_OUTPUTS    where to drop the ETM (.db/.lib)
#   PT_REPORTS    where to drop human-readable reports
#   TARGET_LIB    stdcell .db (slow corner) — link/tech library
#   DB_SS / DB_FF stdcell .db, slow / fast corner
#   MEM_DBS_SS    memory macro .db's, slow corner (space-separated)
#   MEM_DBS_FF    memory macro .db's, fast corner (empty -> fast skipped)
#   CLK_NAME / CLK_PERIOD / CLK_UNCERTAINTY  primary clock
#-----------------------------------------------------------------------------

set top_module  $::env(MODULE)
set fc_outputs  $::env(FC_OUTPUTS)
set pt_outputs  $::env(PT_OUTPUTS)
set pt_reports  $::env(PT_REPORTS)

set netlist     ${fc_outputs}/${top_module}.v
set boundary_sdc ${fc_outputs}/${top_module}.sdc

file mkdir $pt_outputs
file mkdir $pt_reports

if {![file exists $netlist]} {
    error "gate netlist not found: $netlist  (run `make -C ../fusion-compiler fc_abstract` first)"
}

#-----------------------------------------------------------------------------
# Corner table. The FC flow always emits scen_slow; scen_fast only when
# MEM_DBS_FF is populated (`make mem_ff_db`). Mirror that data-gating
# here so the ETM set tracks whatever the partition actually delivered:
# one model per corner whose SPEF is present.
#   { <corner-tag> <scenario> <stdcell .db> <mem .db list env> }
#-----------------------------------------------------------------------------
set corners [list]
lappend corners [list slow scen_slow $::env(DB_SS) MEM_DBS_SS]
if {[info exists ::env(MEM_DBS_FF)] && [string trim $::env(MEM_DBS_FF)] ne ""} {
    lappend corners [list fast scen_fast $::env(DB_FF) MEM_DBS_FF]
} else {
    puts "INFO: MEM_DBS_FF empty — fast-corner ETM skipped (slow only)"
}

set made 0
foreach c $corners {
    lassign $c tag scen db mem_env

    set spef ${fc_outputs}/${top_module}.${scen}.spef
    if {![file exists $spef]} {
        puts "WARNING: no SPEF for $scen ($spef) — skipping $tag ETM"
        puts "WARNING:   (signoff-stage extract_parasitics + per-scenario"
        puts "WARNING:    write_parasitics must have run in the FC flow)"
        continue
    }

    puts "INFO: \[etm\] ===== corner $tag (scenario $scen) ====="

    # Fresh session state per corner so models don't cross-contaminate.
    if {[catch {remove_design -all}]} {}

    # Link path: '*' (already-linked cells) + this corner's std-cell .db
    # + this corner's memory macro .db's.
    set mem_dbs {}
    if {[info exists ::env($mem_env)]} { set mem_dbs $::env($mem_env) }
    set_app_var link_path "* $db $mem_dbs"
    set_app_var search_path [concat [get_app_var search_path] $fc_outputs]

    read_verilog $netlist
    current_design $top_module
    if {[catch {link_design} lerr]} {
        puts "ERROR: \[etm\] link_design failed ($tag): $lerr"
        exit 1
    }

    # Boundary constraints: prefer the SDC FC wrote; fall back to a
    # minimal primary-clock definition so extract_model still has a
    # clock to characterise against.
    if {[file exists $boundary_sdc]} {
        puts "INFO: \[etm\] read_sdc $boundary_sdc"
        if {[catch {read_sdc $boundary_sdc} serr]} {
            puts "WARNING: \[etm\] read_sdc failed: $serr — using fallback clock"
            create_clock -name $::env(CLK_NAME) \
                -period $::env(CLK_PERIOD) [get_ports $::env(CLK_NAME)]
        }
    } else {
        puts "WARNING: \[etm\] $boundary_sdc absent — fallback primary clock"
        create_clock -name $::env(CLK_NAME) \
            -period $::env(CLK_PERIOD) [get_ports $::env(CLK_NAME)]
    }
    if {[info exists ::env(CLK_UNCERTAINTY)]} {
        set_clock_uncertainty $::env(CLK_UNCERTAINTY) \
            [get_clocks $::env(CLK_NAME)]
    }

    puts "INFO: \[etm\] read_parasitics $spef"
    if {[catch {read_parasitics -format spef $spef} perr]} {
        puts "ERROR: \[etm\] read_parasitics failed ($tag): $perr"
        exit 1
    }

    update_timing -full
    redirect -tee -file ${pt_reports}/etm_${tag}_timing.rep {
        report_timing -max_paths 5
    }
    redirect -file ${pt_reports}/etm_${tag}_constraint.rep {
        report_constraint -all_violators
    }

    # The ETM itself. extract_model black-boxes the design into a
    # tool-neutral timing model the integrator links at chip-top.
    set out ${pt_outputs}/${top_module}_${tag}
    puts "INFO: \[etm\] extract_model -> ${out}.{db,lib}"
    if {[catch {extract_model -output $out -format {db lib}} merr]} {
        puts "ERROR: \[etm\] extract_model failed ($tag): $merr"
        exit 1
    }
    incr made
}

if {$made == 0} {
    puts "PT_ETM_FAIL: $top_module — no ETM produced (no SPEF available?)"
    exit 1
}

puts "INFO: \[etm\] $made ETM model(s) written to $pt_outputs"
puts "PT_ETM_OK: $top_module"
exit 0
