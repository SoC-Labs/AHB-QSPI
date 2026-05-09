#-----------------------------------------------------------------------------
# AHB QSPI — FC Read Design Script for Fusion Compiler / RTL Architect.
#
# Sourced by the FC stage scripts (and the RM init_design.tcl when
# RTL_SOURCE_FORMAT = script). Reads RTL from the filelist, elaborates,
# sets up MCMM, and applies the AHB/APB clock + reset constraints.
#
# Environment variables (set by the Makefile via common.mk):
#   SOCLABS_AHB_QSPI_DIR  - Repository root
#   MODULE                - Top-level module name (top_ahb_qspi)
#   FLIST                 - Path to the filelist
#   CLK_NAME              - Primary clock (HCLK)
#   CLK_PERIOD            - HCLK period (ns)
#   CLK_UNCERTAINTY       - Clock uncertainty (ns)
#   RST_NAME              - Primary reset (HRESETn)
#   TLUPLUS_PATH          - Path to TLU+ extraction models
#   TLUPLUS_MAP           - Path to TLU+ layer map file
#
# The PCLK clock + the divided-by-2 generated QSPI_SCLK are applied via
# the Fusion Compiler partition-level overlay
# (fusion-compiler/inputs/constraints.sdc), since both the period and
# generator-pin path are partition-specific.
#-----------------------------------------------------------------------------

set top_module    $::env(MODULE)
set flist         $::env(FLIST)
set clk_name      $::env(CLK_NAME)
set clk_period    $::env(CLK_PERIOD)
set clk_uncert    $::env(CLK_UNCERTAINTY)
set rst_name      $::env(RST_NAME)
set tluplus_path  $::env(TLUPLUS_PATH)
set tluplus_map   $::env(TLUPLUS_MAP)

# Extra resets / non-default clocks that must be excluded from the
# all_inputs sweep (their I/O delays are set in the SDC overlay).
set extra_excludes [list PRESETn PCLK]

#-----------------------------------------------------------------------------
# Read design from filelist
#-----------------------------------------------------------------------------
echo "FC_RTL_SCRIPT: parsing filelist $flist"

set include_dirs [list]
set defines [list]
set verilog_files [list]
set sverilog_files [list]

proc parse_flist {filepath} {
    upvar include_dirs include_dirs
    upvar defines defines
    upvar verilog_files verilog_files
    upvar sverilog_files sverilog_files

    set fp [open $filepath r]
    while {[gets $fp line] >= 0} {
        set line [string trim $line]

        # Skip blank lines and comments
        if {$line eq "" || [string match "//*" $line] || [string index $line 0] eq "#"} { continue }

        # Expand environment variable references: ${VAR} and $(VAR)
        set skip 0
        while {[regexp {\$\{(\w+)\}|\$\((\w+)\)} $line -> var1 var2]} {
            set varname [expr {$var1 ne "" ? $var1 : $var2}]
            if {[info exists ::env($varname)]} {
                set line [regsub {\$[\{\(]\w+[\}\)]} $line $::env($varname)]
            } else {
                puts "WARNING: Environment variable $varname not set, skipping: $line"
                set skip 1
                break
            }
        }
        if {$skip} { continue }

        # +incdir+
        if {[string match "+incdir+*" $line]} {
            lappend include_dirs [string range $line 8 end]
            continue
        }

        # +define+
        if {[string match "+define+*" $line]} {
            lappend defines [string range $line 8 end]
            continue
        }

        # +libext+ (ignore — irrelevant for analyze)
        if {[string match "+libext+*" $line]} { continue }

        # -f nested filelist
        if {[string match "-f *" $line] || [string match "-f\t*" $line]} {
            set nested [string trim [string range $line 2 end]]
            if {[file exists $nested]} {
                parse_flist $nested
            } else {
                puts "WARNING: Nested filelist not found: $nested"
            }
            continue
        }

        # Classify by extension
        if {[string match "*.v" $line]} {
            lappend verilog_files $line
        } elseif {[string match "*.sv" $line]} {
            lappend sverilog_files $line
        }
    }
    close $fp
}

parse_flist $flist

# Apply +incdir+ via search_path
if {[llength $include_dirs] > 0} {
    set_app_var search_path [concat [get_app_var search_path] $include_dirs]
}

#-----------------------------------------------------------------------------
# Analyze RTL — read everything as SystemVerilog so the .v + .sv mix in
# ahb_QSPI_ASIC.flist parses through one analyze call (matches the lint
# / cdc flows, which also use -sv).
#-----------------------------------------------------------------------------
echo "FC_RTL_SCRIPT: analyze"

set define_args [list]
foreach def $defines { lappend define_args $def }

set all_rtl [concat $verilog_files $sverilog_files]
if {[llength $all_rtl] > 0} {
    puts "INFO: Analyzing [llength $verilog_files] .v + [llength $sverilog_files] .sv file(s) as SystemVerilog"
    if {[llength $define_args] > 0} {
        analyze -format sverilog -define $define_args $all_rtl
    } else {
        analyze -format sverilog $all_rtl
    }
}

#-----------------------------------------------------------------------------
# Elaborate
#-----------------------------------------------------------------------------
echo "FC_RTL_SCRIPT: elaborate $top_module"

elaborate $top_module
set_top_module $top_module

#-----------------------------------------------------------------------------
# MCMM — slow scenario by default. scen_fast is only created when the
# caller has bound matching FF macro libraries via MEM_DBS_FF; the
# precompiled flash_cache_data / flash_cache_tag .lib's haven't been
# converted to .db, so common.mk leaves MEM_DBS_FF empty and the fast
# scenario is skipped to keep the flow runnable end-to-end. Re-enable
# by populating MEM_DBS_FF in common.mk.
#-----------------------------------------------------------------------------
echo "FC_RTL_SCRIPT: apply MCMM constraints"

create_mode func
create_corner slow
create_scenario -mode func -corner slow -name scen_slow
set_operating_conditions \
    -analysis_type on_chip_variation \
    -max ss_typical_max_1p08v_125c -min ss_typical_max_1p08v_125c \
    -library sc12_cln65lp_base_rvt_ss_typical_max_1p08v_125c

set have_ff_mems 0
if {[info exists ::env(MEM_DBS_FF)] && [string trim $::env(MEM_DBS_FF)] ne ""} {
    set have_ff_mems 1
}

if {$have_ff_mems} {
    create_corner fast
    create_scenario -mode func -corner fast -name scen_fast
    set_operating_conditions \
        -analysis_type on_chip_variation \
        -max ff_typical_min_1p32v_m40c -min ff_typical_min_1p32v_m40c \
        -library sc12_cln65lp_base_rvt_ff_typical_min_1p32v_m40c
} else {
    puts "INFO: MEM_DBS_FF empty — skipping scen_fast (no FF macro libraries bound)"
}

#-----------------------------------------------------------------------------
# Parasitic extraction (TLU+)
#-----------------------------------------------------------------------------
read_parasitic_tech -name typical -tlup ${tluplus_path}/typical.tluplus -layermap ${tluplus_map}
read_parasitic_tech -name rcbest  -tlup ${tluplus_path}/rcbest.tluplus  -layermap ${tluplus_map}
read_parasitic_tech -name rcworst -tlup ${tluplus_path}/rcworst.tluplus -layermap ${tluplus_map}

set_parasitic_parameters -corners slow \
    -early_spec rcworst -early_temperature -40 \
    -late_spec  rcworst -late_temperature  125

if {$have_ff_mems} {
    set_parasitic_parameters -corners fast \
        -early_spec rcbest -early_temperature -40 \
        -late_spec  rcbest -late_temperature  125
}

#-----------------------------------------------------------------------------
# Primary clock + reset constraints. PCLK + QSPI_SCLK come from the
# overlay SDC because their generator-pin paths are partition-internal
# and the overlay needs to land after elaborate (so get_pins resolves).
#-----------------------------------------------------------------------------
echo "FC_RTL_SCRIPT: apply HCLK clock + reset constraints"

create_clock -name $clk_name -period $clk_period \
    -waveform "0 [expr {$clk_period / 2.0}]" [get_ports $clk_name]
set_clock_uncertainty $clk_uncert [get_clocks $clk_name]

# Reset: treat as asynchronous from the timing point of view.
foreach r [list $rst_name {*}$extra_excludes] {
    if {$r in [list HRESETn PRESETn] && \
        [sizeof_collection [get_ports $r -quiet]] > 0} {
        set_false_path -from [get_ports $r]
    }
}

# Default I/O delays — 25 % of HCLK period — for ports that aren't on
# QSPI_SCLK / PCLK. The overlay re-tightens QSPI port delays against
# QSPI_SCLK with -add_delay so both are honoured.
set io_delay [expr {$clk_period * 0.25}]

set all_inputs_raw [all_inputs]
set exclude_ports [list]
foreach p [list $clk_name $rst_name {*}$extra_excludes] {
    if {[sizeof_collection [get_ports $p -quiet]] > 0} {
        lappend exclude_ports $p
    }
}

if {[llength $exclude_ports] > 0} {
    set all_inputs [remove_from_collection $all_inputs_raw [get_ports $exclude_ports]]
} else {
    set all_inputs $all_inputs_raw
}
set all_outputs [all_outputs]

if {[sizeof_collection $all_inputs] > 0} {
    set_input_delay  -clock $clk_name $io_delay $all_inputs
}
if {[sizeof_collection $all_outputs] > 0} {
    set_output_delay -clock $clk_name $io_delay $all_outputs
}

set_scenario_status -setup true -leakage_power false *

# NOTE: floorplan is initialised by the calling stage (rtl-architect /
# fusion-compiler each pick their own shape) — not done here.

echo "FC_RTL_SCRIPT: done"
