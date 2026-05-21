# Common ASIC synthesis definitions
# Included by all flow Makefiles under syn/asic/

export SOCLABS_AHB_QSPI_DIR := $(realpath $(dir $(lastword $(MAKEFILE_LIST)))/../..)

# ARM IP root (CG092 cache + Corstone-101 APB slave mux live here).
# Override via the environment for non-default install paths.
export ARM_IP_LIBRARY_PATH ?= /research/AAA/ip_library

# ── Target module ──────────────────────────────────────────────────────────
export MODULE ?= top_ahb_qspi
export TOP    ?= $(MODULE)

# ── File lists ─────────────────────────────────────────────────────────────
# The ASIC flist pulls real SRAM macros from /research/precompiled_mems/TSMC65
# (flash_cache_data + flash_cache_tag), via ahb_QSPI_ASIC.flist + its sv-only
# nested flist. Use the SIM flist for behavioural cache_ram models instead.
export FLIST := $(SOCLABS_AHB_QSPI_DIR)/flist/Top/ahb_QSPI_ASIC.flist

# ── Cell libraries (TSMC 65nm LP, 9-track tcbn65lp) ───────────────────────
# Migrated 2026-05-21 from 12-track Arm sc12 -> 9-track TSMC tcbn65lp.
# Standard cln65lp corners: wc = SS @ 0.9 V / 125 C, tc = TT @ 1.0 V /
# 25 C, bc = FF @ 1.1 V / -40 C (foundry naming).
export TARGET_LIB     ?= /home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/stclib/9-track/tcbn65lp-set/tcbn65lp_220a_FE/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65lp_220a/tcbn65lpwc1d081d08.db

# ── Memory macro libraries ─────────────────────────────────────────────────
# top_ahb_qspi instantiates two cache ways (cache_subsystem.v): each way's
# cache_ram has 4× flash_cache_data (256×32) and 1× flash_cache_tag (256×11)
# = 10 SRAM macros at the partition top. Both come precompiled with .lef +
# slow/fast .db under /research/precompiled_mems/TSMC65/.
export MEM_BASE       ?= /research/precompiled_mems/TSMC65

export FCD_DB_SS      ?= $(MEM_BASE)/flash_cache_data/flash_cache_data_ss_1p08v_1p08v_125c.db
export FCT_DB_SS      ?= $(MEM_BASE)/flash_cache_tag/flash_cache_tag_ss_1p08v_1p08v_125c.db

# FF .db files: not shipped by the foundry; generated from the .lib's
# in-tree by `make mem_ff_db` (lc_shell). Keeping them inside the repo
# avoids writing into the shared /research/precompiled_mems/ tree.
export MEM_FF_DB_DIR  ?= $(SOCLABS_AHB_QSPI_DIR)/syn/asic/libs/mem_ff
export FCD_DB_FF      ?= $(MEM_FF_DB_DIR)/flash_cache_data_ff_1p32v_1p32v_m40c.db
export FCT_DB_FF      ?= $(MEM_FF_DB_DIR)/flash_cache_tag_ff_1p32v_1p32v_m40c.db

# Aggregate slow/fast macro library lists for link_library.
# MEM_DBS_FF is populated only when the FF .db's exist on disk
# (built by `make mem_ff_db`); otherwise scen_fast is auto-skipped.
export MEM_DBS_SS     := $(FCD_DB_SS) $(FCT_DB_SS)
export MEM_DBS_FF     := $(if $(wildcard $(FCD_DB_FF)),$(FCD_DB_FF) $(FCT_DB_FF),)

# Link libraries — target + every macro corner present
export LINK_LIBS      ?= $(TARGET_LIB) $(MEM_DBS_SS)

# ── Physical references (TSMC 65nm LP tcbn65lp, 9-track, 9-layer-metal T2)
# Tech file = 9LM T2 stack from the TSMC tcbn65lp_220a FE distribution.
# LEF + .db + GDS likewise come direct from the TSMC distribution
# (foundry-original, no Arm-wrapper). The CLN65LP_TECH_PATH below is
# the user's /home/dwn1c21 mirror — adjust on systems where TSMCHOME
# lives elsewhere.
export PHYS_IP_PATH   ?= /home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/stclib/9-track/tcbn65lp-set/tcbn65lp_220a_FE/TSMCHOME/digital
export STDCELL_VERILOG ?= $(PHYS_IP_PATH)/Front_End/verilog/tcbn65lp_200a
export TF_FILE        ?= $(PHYS_IP_PATH)/Back_End/milkyway/tcbn65lp_200a/techfiles/tsmcn65_9lmT2.tf
export MW_REF_LIB     ?= $(PHYS_IP_PATH)/Back_End/milkyway/tcbn65lp_200a/tcbn65lp_9lmT2

# ── Multi-corner .db libraries (tcbn65lp std cells) ────────────────────────
# Corners aligned with the cache-macro characterisation (1.08/1.20/
# 1.32 V) so the macro Liberty + std-cell Liberty link at one corner.
# File naming: wcXdYYZdWW = wc-process at X.YY V core / Z.WW V io.
export DB_PATH        ?= $(PHYS_IP_PATH)/Front_End/timing_power_noise/NLDM/tcbn65lp_220a
export DB_SS          ?= $(DB_PATH)/tcbn65lpwc1d081d08.db
export DB_FF          ?= $(DB_PATH)/tcbn65lpbc1d321d32.db
export DB_TT          ?= $(DB_PATH)/tcbn65lptc1d21d2.db

# ── TLU+ parasitic extraction models ─────────────────────────────────────
# The TSMC tcbn65lp distribution does not ship TLU+ files itself — those
# live under the TSMC pdk subtree, alongside the Calibre/rcx files.
# Override if your site mirrors them elsewhere.
export TLUPLUS_PATH   ?= /home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/pdk/StarRC/cln65lp_9lmT2
export TLUPLUS_MAP    ?= $(TLUPLUS_PATH)/tluplus.map

# ── GDS stream-out — layer map + macro/stdcell GDS to merge ────────────────
# write_gds in 6_partition_export.tcl needs (a) a Synopsys-format layer
# map and (b) the GDS of every reference cell (std cells + macros) so
# the output stream-out is self-contained.
export GDS_LAYER_MAP   ?= $(PHYS_IP_PATH)/Back_End/milkyway/tcbn65lp_200a/techfiles/tsmc_layer_map
export GDS_STDCELL     ?= $(PHYS_IP_PATH)/Back_End/celtic/tcbn65lp_200a/tcbn65lp.gds
export GDS_MEM_FCD     ?= $(MEM_BASE)/flash_cache_data/flash_cache_data.gds2
export GDS_MEM_FCT     ?= $(MEM_BASE)/flash_cache_tag/flash_cache_tag.gds2
export GDS_MERGE_FILES ?= $(GDS_STDCELL) $(GDS_MEM_FCD) $(GDS_MEM_FCT)

# ── Shared PDK / cell-library / memory paths ─────────────────────────────
# Single-source-of-truth for the chip-top + partition flows: the Tcl
# file syn/asic/pdk_paths.tcl carries every external path the flow
# touches. Below are the parallel Make-variable forms (Make can't
# source Tcl), kept in sync — edit syn/asic/pdk_paths.tcl for the
# documentation/Tcl side, and edit this block for the Make side.
# Only the subset the PARTITION uses is materialised above (PHYS_IP_PATH
# et al.); the chip-top-only paths (IO, PMK, RET, SRAM_32K, ROM_VIA)
# are captured here for the wider-project context.
export CLN65LP_TECH_PATH       ?= /home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/stclib/12-track/tcbn65lpbwp12t-set/tcbn65lpbwp12t_200b_FE/TSMCHOME/digital/Back_End
export CLN65LP_TECH_FILE       ?= $(CLN65LP_TECH_PATH)/milkyway/tcbn65lpbwp12t_200a/techfiles/tsmcn65_9lmT2.tf
export CLN65LP_LEF_FILE        ?= $(CLN65LP_TECH_PATH)/lef/tcbn65lpbwp12t_140b/lef/tcbn65lpbwp12t_9lmT2.lef
export STANDARD_CELL_BASE_PATH ?= /research/AAA/phys_ip_library/arm/tsmc/cln65lp/sc12_base_rvt/r0p0
export IO_BASE_PATH            ?= /home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/IO2.5V/iolib/linear/tpdn65lpnv2od3_200a_FE/TSMCHOME/digital
export PMK_BASE_PATH           ?= /research/AAA/phys_ip_library/arm/tsmc/cln16fcll001/sc9mcpp96c_pmk_svt_c24/r2p0
export RET_BASE_PATH           ?= /research/AAA/phys_ip_library/arm/tsmc/cln16fcll001/sc9mcpp96c_rklo_lvt_svt_c20_c24/r1p0
# TSMC Calibre signoff DRC deck — pre-set to the 1p9m_6X2Z0U variant
# matching the TF_FILE 1p9m_6x2z stack; override via STACK= or
# TSMC65_DRC_DECK= when invoking `make calibre_drc`.
export TSMC65_CALIBRE_PDK      ?= /home/dwn1c21/SoC-Labs/phys_ip/TSMC/65/CMOS/LP/pdk/Calibre

# ── Design constraints ─────────────────────────────────────────────────────
# top_ahb_qspi has two boundary clocks (HCLK + PCLK, both 4 ns in the
# existing dc_synthesis_core.tcl baseline) plus a divided-by-2 generated
# QSPI_SCLK. The shared FC.read_design.tcl creates HCLK; the Fusion
# inputs/constraints.sdc overlay adds PCLK + the generated clock.
export CLK_NAME        ?= HCLK
export CLK_PERIOD      ?= 4.0
export CLK_UNCERTAINTY ?= 0.35

# Two reset ports: HRESETn (AHB) and PRESETn (APB). The shared script
# accepts a single RST_NAME; the second is treated as async via the SDC
# overlay's set_false_path -from list.
export RST_NAME        ?= HRESETn
