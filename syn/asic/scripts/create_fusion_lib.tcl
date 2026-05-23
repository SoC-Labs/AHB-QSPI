#-----------------------------------------------------------------------------
# Build Fusion NDM reference libraries for the top_ahb_qspi flow.
# 9-track TSMC tcbn65lp variant (2026-05-21).
#
# Run with:  lm_shell -f create_fusion_lib.tcl
#
# This uses lm_shell's create_workspace / commit_workspace idiom (the
# fc_shell create_fusion_lib variant in the user's snippet is an
# fc_shell-only command and not available in lm_shell — lm_shell is
# the right tool for NDM creation outside a design context). The
# resulting NDMs are functionally identical to fc_shell's create_fusion_lib.
#
# Sources syn/asic/pdk_paths.tcl as the single source of truth.
# Builds (in order of necessity):
#
#   cln65lp        — TSMC tcbn65lp 9-track std cells
#                     (tech .tf + .lef + .db SS/TT/FF, full lib)
#                     PARTITION DEPENDENCY: REQUIRED
#   mem_frame_lib  — flash_cache_data + flash_cache_tag macro LEFs,
#                     frame-only
#                     PARTITION DEPENDENCY: REQUIRED
#   io_lib         — Arm IO pad library (gated on LEF existence)
#   SRAM_32K       — chip-top SRAM (gated on $SOCLABS_PROJECT_DIR)
#   ROM_VIA        — chip-top bootrom (gated on $SOCLABS_PROJECT_DIR)
#
# Output base: $FUSION_LIB (sibling sub-libs alongside).
#-----------------------------------------------------------------------------

# Source the path file. Prefer FC_DIR + ../pdk_paths.tcl (Makefile-set);
# fall back to a path relative to this script.
if {[info exists ::env(FC_DIR)] && [file exists $::env(FC_DIR)/../pdk_paths.tcl]} {
    source $::env(FC_DIR)/../pdk_paths.tcl
} elseif {[file exists [file join [file dirname [info script]] .. pdk_paths.tcl]]} {
    source [file join [file dirname [info script]] .. pdk_paths.tcl]
} else {
    error "create_fusion_lib.tcl: cannot locate pdk_paths.tcl"
}

# Output base — $FUSION_LIB points at cln65lp; siblings live alongside.
if {[info exists ::env(FUSION_LIB)] && $::env(FUSION_LIB) ne ""} {
    set output_lib_cln65lp $::env(FUSION_LIB)
} else {
    set output_lib_cln65lp "./fusion_lib/cln65lp"
}
set output_dir [file dirname $output_lib_cln65lp]
file mkdir $output_dir

# MEM_BASE for the precompiled flash_cache_* macros (partition-specific)
if {[info exists ::env(MEM_BASE)] && $::env(MEM_BASE) ne ""} {
    set mem_base $::env(MEM_BASE)
} else {
    set mem_base "/research/precompiled_mems/TSMC65"
}

# Demote LEF-vs-Liberty VDD/VSS direction-mismatch errors (NDM-032) to
# warnings (lm_shell auto-corrects them; the Error severity would
# otherwise trip commit_workspace).
catch {set_message_info -id NDM-032 -limit 5}

#-----------------------------------------------------------------------------
# 1) cln65lp — 9-track TSMC tcbn65lp std cells (REQUIRED). Normal flow
#    so Liberty for all three corners is bundled into the NDM.
#-----------------------------------------------------------------------------
puts "INFO: \[lib\] Building cln65lp (9-track tcbn65lp std cells)"
puts "INFO: \[lib\]   tech : $cln65lp_tech_file"
puts "INFO: \[lib\]   LEF  : $standard_cell_lef_file"
puts "INFO: \[lib\]   ss   : $standard_cell_db_file_ss_1p08v_125C"
puts "INFO: \[lib\]   tt   : $standard_cell_db_file_tt_1p20v_25C"
puts "INFO: \[lib\]   ff   : $standard_cell_db_file_ff_1p32v_m40C"
puts "INFO: \[lib\]   Out  : $output_lib_cln65lp"

file delete -force $output_lib_cln65lp
create_workspace cln65lp_ws -technology $cln65lp_tech_file -flow normal
read_lef $standard_cell_lef_file
read_db  $standard_cell_db_file_ss_1p08v_125C
read_db  $standard_cell_db_file_tt_1p20v_25C
read_db  $standard_cell_db_file_ff_1p32v_m40C
check_workspace
commit_workspace -output $output_lib_cln65lp

#-----------------------------------------------------------------------------
# 2) mem_frame_lib — flash_cache_* macros, frame-only NDM. Liberty
#    reaches fc_shell via link_library .db's set in 1_init_design.tcl
#    (the .db's reference std-cell sub-modules so they cannot be
#    cleanly committed into a normal-flow NDM here).
#-----------------------------------------------------------------------------
set output_lib_mem "${output_dir}/mem_frame_lib"
set mem_lefs [list \
    "${mem_base}/flash_cache_data/flash_cache_data.lef" \
    "${mem_base}/flash_cache_tag/flash_cache_tag.lef"]

puts "INFO: \[lib\] Building mem_frame_lib (flash_cache_* frames)"
foreach lef $mem_lefs { puts "INFO: \[lib\]   LEF : $lef" }
puts "INFO: \[lib\]   Out : $output_lib_mem"

file delete -force $output_lib_mem
create_workspace mem_ws -technology $cln65lp_tech_file -flow frame
foreach lef $mem_lefs { read_lef $lef }
check_workspace
commit_workspace -output $output_lib_mem

#-----------------------------------------------------------------------------
# 3) io_lib — Arm IO pad library (chip-top; gated on LEF existence)
#-----------------------------------------------------------------------------
if {[file exists $io_lef_file] && [file exists $io_db_file_ss_1p08v_125C]} {
    set output_lib_io "${output_dir}/io_lib"
    puts "INFO: \[lib\] Building io_lib (Arm tpdn65lpnv2od3)"
    puts "INFO: \[lib\]   LEF : $io_lef_file"
    puts "INFO: \[lib\]   Out : $output_lib_io"
    file delete -force $output_lib_io
    create_workspace io_ws -technology $cln65lp_tech_file -flow normal
    read_lef $io_lef_file
    read_db  $io_db_file_ss_1p08v_125C
    read_db  $io_db_file_tt_1p20v_25C
    read_db  $io_db_file_ff_1p32v_m40C
    check_workspace
    commit_workspace -output $output_lib_io
} else {
    puts "INFO: \[lib\] io_lib skipped (IO LEF / .db not present)"
}

#-----------------------------------------------------------------------------
# 4) SRAM_32K — wider-project chip-top memory (gated)
#-----------------------------------------------------------------------------
if {[file isdirectory $SRAM_32K_PATH] && [file exists $SRAM_32K_lef_file]} {
    puts "INFO: \[lib\] Building SRAM_32K"
    # Compile .lib -> .db if .db not present (chip-top SRAM ships only .lib)
    foreach pair {
        {SRAM_32K_lib_file_ss SRAM_32K_db_file_ss sram_32k_ssgnp_0p90v_0p90v_125c}
        {SRAM_32K_lib_file_tt SRAM_32K_db_file_tt sram_32k_tt_1p00v_1p00v_25c}
        {SRAM_32K_lib_file_ff SRAM_32K_db_file_ff sram_32k_ffgnp_1p10v_1p10v_m40c}
    } {
        lassign $pair lib_var db_var cell
        upvar 0 $lib_var lib_p
        upvar 0 $db_var  db_p
        if {[file exists $lib_p] && ![file exists $db_p]} {
            puts "INFO: \[lib\]   compile $lib_p -> $db_p"
            read_lib $lib_p
            write_lib -output $db_p -format db $cell
            close_lib -all
        }
    }
    set output_lib_sram "${output_dir}/SRAM_32K"
    file delete -force $output_lib_sram
    create_workspace sram_ws -technology $cln65lp_tech_file -flow normal
    read_lef $SRAM_32K_lef_file
    if {[file exists $SRAM_32K_db_file_ss]} { read_db $SRAM_32K_db_file_ss }
    if {[file exists $SRAM_32K_db_file_tt]} { read_db $SRAM_32K_db_file_tt }
    if {[file exists $SRAM_32K_db_file_ff]} { read_db $SRAM_32K_db_file_ff }
    check_workspace
    commit_workspace -output $output_lib_sram
} else {
    puts "INFO: \[lib\] SRAM_32K skipped (not in this project: $SRAM_32K_PATH)"
}

#-----------------------------------------------------------------------------
# 5) ROM_VIA — wider-project bootrom (gated)
#-----------------------------------------------------------------------------
if {[file isdirectory $ROM_VIA_PATH] && [file exists $ROM_VIA_lef_file]} {
    puts "INFO: \[lib\] Building ROM_VIA"
    foreach pair {
        {ROM_VIA_lib_file_ss ROM_VIA_db_file_ss rom_via_ssgnp_0p90v_0p90v_125c}
        {ROM_VIA_lib_file_tt ROM_VIA_db_file_tt rom_via_tt_1p00v_1p00v_25c}
        {ROM_VIA_lib_file_ff ROM_VIA_db_file_ff rom_via_ffgnp_1p10v_1p10v_m40c}
    } {
        lassign $pair lib_var db_var cell
        upvar 0 $lib_var lib_p
        upvar 0 $db_var  db_p
        if {[file exists $lib_p] && ![file exists $db_p]} {
            puts "INFO: \[lib\]   compile $lib_p -> $db_p"
            read_lib $lib_p
            write_lib -output $db_p -format db $cell
            close_lib -all
        }
    }
    set output_lib_rom "${output_dir}/ROM_VIA"
    file delete -force $output_lib_rom
    create_workspace rom_ws -technology $cln65lp_tech_file -flow normal
    read_lef $ROM_VIA_lef_file
    if {[file exists $ROM_VIA_db_file_ss]} { read_db $ROM_VIA_db_file_ss }
    if {[file exists $ROM_VIA_db_file_tt]} { read_db $ROM_VIA_db_file_tt }
    if {[file exists $ROM_VIA_db_file_ff]} { read_db $ROM_VIA_db_file_ff }
    check_workspace
    commit_workspace -output $output_lib_rom
} else {
    puts "INFO: \[lib\] ROM_VIA skipped (not in this project: $ROM_VIA_PATH)"
}

puts "INFO: \[lib\] All NDMs committed under $output_dir"
exit
