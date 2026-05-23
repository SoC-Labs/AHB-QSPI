#-----------------------------------------------------------------------------
# Shared PDK / cell-library / memory paths for the top_ahb_qspi flow.
# 9-track TSMC tcbn65lp variant (2026-05-21) — replaces the previous
# 12-track Arm sc12 wrapper.
#
# This file is the single source of truth for every external path the
# ASIC flow needs. Source it from any Tcl context that needs the
# values, or read it via the parallel Make variables in
# syn/asic/common.mk.
#
# ## Paths Please Edit for your system
#
# The values below come from the project-wide SoC-Labs convention; not
# every path is reachable from every host. For this partition flow
# (top_ahb_qspi), only a SUBSET of the paths is actually used at the
# moment — see the "PARTITION-FLOW DEPENDENCY" comments. The rest are
# captured here so the chip-top / wider-project context can be brought
# in without re-deriving them.
#-----------------------------------------------------------------------------

# ── A) Process tech + std-cell library (TSMC cln65lp, 9-track) ───────────
# PARTITION-FLOW DEPENDENCY: YES — tech file + LEF used by fc_init;
# .db files linked by synthesis.
#
# The 12-track Arm-sc12 wrapper was retired in favour of the
# foundry-direct 9-track TSMC library (tcbn65lp_220a_FE). Standard
# cln65lp LP corners: wc = SS @ 0.9 V / 125 C, tc = TT @ 1.0 V / 25 C,
# bc = FF @ 1.1 V / -40 C.
set cln65lp_tech_path           /home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/stclib/9-track/tcbn65lp-set/tcbn65lp_220a_FE/TSMCHOME/digital/Back_End
set standard_cell_base_path     /home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/stclib/9-track/tcbn65lp-set/tcbn65lp_220a_FE/TSMCHOME/digital

# Technology files (9-track, 9 layers metal, T2 stack)
set cln65lp_tech_file       $cln65lp_tech_path/milkyway/tcbn65lp_200a/techfiles/tsmcn65_9lmT2.tf
set cln65lp_lef_file        $cln65lp_tech_path/lef/tcbn65lp_200a/lef/tcbn65lp_9lmT2.lef

# Standard Cell libraries (9-track TSMC tcbn65lp, NLDM)
# Use BASE variants (wc/tc/bc) — these contain the full 816 std cells
# at 1.08 / 1.20 / 1.32 V (matching the cache-macro corners). The
# dual-voltage variants (wcXdYYZdWW) contain only 28 multi-voltage
# IO/ISO/level-shifter cells and are NOT a std-cell library; they
# would be linked separately only for a flow that uses multi-voltage
# pad-ring infrastructure (not this partition).
#
# Library names inside the .db:  tcbn65lpwc, tcbn65lptc, tcbn65lpbc
# Operating conditions in .lib:  WCCOM,      NCCOM,      BCCOM
set standard_cell_lef_file                  $cln65lp_tech_path/lef/tcbn65lp_200a/lef/tcbn65lp_9lmT2.lef
set standard_cell_gds_file                  $standard_cell_base_path/Back_End/celtic/tcbn65lp_200a/tcbn65lp.gds
set _NLDM                                   $standard_cell_base_path/Front_End/timing_power_noise/NLDM/tcbn65lp_220a
set standard_cell_db_file_ss_1p08v_125C     $_NLDM/tcbn65lpwc.db
set standard_cell_lib_file_ss_1p08v_125C    $_NLDM/tcbn65lpwc.lib
set standard_cell_db_file_tt_1p20v_25C      $_NLDM/tcbn65lptc.db
set standard_cell_lib_file_tt_1p20v_25C     $_NLDM/tcbn65lptc.lib
set standard_cell_db_file_ff_1p32v_m40C     $_NLDM/tcbn65lpbc.db
set standard_cell_lib_file_ff_1p32v_m40C    $_NLDM/tcbn65lpbc.lib
set standard_cell_antenna_file              $cln65lp_tech_path/celtic/tcbn65lp_200a/tcbn65lp_antenna.cl

# ── B) Arm IO library (chip-top pad ring) ──────────────────────────────────
# PARTITION-FLOW DEPENDENCY: NO. The partition has no pad cells.
set io_base_path                /home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/IO2.5V/iolib/linear/tpdn65lpnv2od3_200a_FE/TSMCHOME/digital

set io_lef_file                 $io_base_path/Back_End/lef/tpdn65lpnv2od3_140b/mt_2/9lm/lef/tpdn65lpnv2od3_9lm.lef
set io_gds_file                 $io_base_path/Back_End/celtic/tpdn65lpnv2od3_200a/tpdn65lpnv2od3.gds
set io_db_file_ss_1p08v_125C    $io_base_path/Front_End/timing_power_noise/NLDM/tpdn65lpnv2od3_200a/tpdn65lpnv2od3wc.db
set io_db_file_tt_1p20v_25C     $io_base_path/Front_End/timing_power_noise/NLDM/tpdn65lpnv2od3_200a/tpdn65lpnv2od3tc.db
set io_db_file_ff_1p32v_m40C    $io_base_path/Front_End/timing_power_noise/NLDM/tpdn65lpnv2od3_200a/tpdn65lpnv2od3bc.db
set io_antenna_file             $io_base_path/Back_End/celtic/tpdn65lpnv2od3_200a/tpdn65lpnv2od3_antenna.cl

# ── C) Arm power-management kit (cln16fcll001, cross-process) ──────────────
# PARTITION-FLOW DEPENDENCY: NO. For chip-top power-domain crossings.
set pmk_base_path               /research/AAA/phys_ip_library/arm/tsmc/cln16fcll001/sc9mcpp96c_pmk_svt_c24/r2p0
set ret_base_path               /research/AAA/phys_ip_library/arm/tsmc/cln16fcll001/sc9mcpp96c_rklo_lvt_svt_c20_c24/r1p0

# ── D) Project memories (chip-top SRAM + bootrom) ──────────────────────────
# PARTITION-FLOW DEPENDENCY: NO. The top_ahb_qspi partition uses the
# precompiled flash_cache_data + flash_cache_tag macros (see common.mk
# MEM_BASE). SRAM_32K + ROM_VIA are wider-project memories.
if {[info exists ::env(SOCLABS_PROJECT_DIR)]} {
    set _proj_root $::env(SOCLABS_PROJECT_DIR)
} elseif {[info exists ::env(SOCLABS_AHB_QSPI_DIR)]} {
    set _proj_root $::env(SOCLABS_AHB_QSPI_DIR)
} else {
    set _proj_root "."
}

set SRAM_32K_PATH            $_proj_root/memories/sram_32k
set SRAM_32K_lef_file        $SRAM_32K_PATH/sram_32k.lef
set SRAM_32K_gds_file        $SRAM_32K_PATH/sram_32k.gds2
set SRAM_32K_lib_file_ss     $SRAM_32K_PATH/sram_32k_ssgnp_0p90v_0p90v_125c.lib
set SRAM_32K_lib_file_tt     $SRAM_32K_PATH/sram_32k_tt_1p00v_1p00v_25c.lib
set SRAM_32K_lib_file_ff     $SRAM_32K_PATH/sram_32k_ffgnp_1p10v_1p10v_m40c.lib
set SRAM_32K_db_file_ss      $SRAM_32K_PATH/sram_32k_ssgnp_0p90v_0p90v_125c.db
set SRAM_32K_db_file_tt      $SRAM_32K_PATH/sram_32k_tt_1p00v_1p00v_25c.db
set SRAM_32K_db_file_ff      $SRAM_32K_PATH/sram_32k_ffgnp_1p10v_1p10v_m40c.db

set ROM_VIA_PATH            $_proj_root/memories/bootrom
set ROM_VIA_lef_file        $ROM_VIA_PATH/rom_via.lef
set ROM_VIA_gds_file        $ROM_VIA_PATH/rom_via.gds2
set ROM_VIA_lib_file_ss     $ROM_VIA_PATH/rom_via_ssgnp_0p90v_0p90v_125c.lib
set ROM_VIA_lib_file_tt     $ROM_VIA_PATH/rom_via_tt_1p00v_1p00v_25c.lib
set ROM_VIA_lib_file_ff     $ROM_VIA_PATH/rom_via_ffgnp_1p10v_1p10v_m40c.lib
set ROM_VIA_db_file_ss      $ROM_VIA_PATH/rom_via_ssgnp_0p90v_0p90v_125c.db
set ROM_VIA_db_file_tt      $ROM_VIA_PATH/rom_via_tt_1p00v_1p00v_25c.db
set ROM_VIA_db_file_ff      $ROM_VIA_PATH/rom_via_ffgnp_1p10v_1p10v_m40c.db

# ── E) TSMC Calibre PDK (signoff DRC + LVS) ────────────────────────────────
# PARTITION-FLOW DEPENDENCY: YES (signoff). Calibre v2023.1 is
# installed at /eda/mentor/calibre/ and is wired by syn/asic/calibre/.
# Stack default 1p9m_6X2Z0U; override via STACK= or TSMC65_DRC_DECK=
# in the calibre/ Makefile.
set tsmc65_calibre_pdk          /home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/pdk/Calibre

set tsmc65_drc_deck             $tsmc65_calibre_pdk/online/drc_online/1p9m_6X2Z0U/calibre.drc
set tsmc65_drc_top_deck         $tsmc65_calibre_pdk/drc/calibre.drc
set tsmc65_lvs_deck             $tsmc65_calibre_pdk/lvs/calibre.lvs
set tsmc65_rcx_deck             $tsmc65_calibre_pdk/rcx/calibre.rcx
set tsmc65_antenna_deck         $tsmc65_calibre_pdk/drc/ANTENNA_DRC

# Calibre binary
set tsmc65_calibre_bin          /eda/mentor/calibre/bin/calibre
