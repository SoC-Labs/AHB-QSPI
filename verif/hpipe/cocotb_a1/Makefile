# H-PIPE regression: cocotb makefile (standalone core, no CG092 cache).
#
# Source: assessor A1's harness, ~/SoCLabs/qspi-assess-A1 branch assess/A1
# 0c3ca6c, verif/cocotb_a1/ (AHB-QSPI PR #1 assessment, 13 Oct 2026). The
# tb, the AHB master/checker and the tests are copied unchanged; only the
# default RTL_DIR/VIP_DIR paths moved with the directory.
#
#   RTL_DIR  : root of the AHB-QSPI tree whose logical/ RTL is simulated
#              (default: this checkout). Point it at an export of another
#              commit to run the same tests on base and candidate.
#   VIP_DIR  : directory holding SST26VF064B.v (make get_flash_model)
#
# Run via run_a1.sh.
A1_DIR   := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
RTL_DIR  ?= $(abspath $(A1_DIR)/../../..)
VIP_DIR  ?= $(abspath $(A1_DIR)/../../VIP)

TOPLEVEL_LANG = verilog
SIM ?= vcs
COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps
TOPLEVEL = tb_a1_core
COCOTB_TOPLEVEL = tb_a1_core
MODULE ?= test_a1_core
COCOTB_TEST_MODULES ?= $(MODULE)
export PYTHONPATH := $(A1_DIR):$(PYTHONPATH)

VERILOG_SOURCES += $(A1_DIR)/tb_a1_core.v
VERILOG_SOURCES += $(RTL_DIR)/logical/apb_qspi_regs/logical/apb_qspi_regs.v
VERILOG_SOURCES += $(RTL_DIR)/logical/ahb_qspi_interface/logical/ahb_qspi_interface.sv
VERILOG_SOURCES += $(RTL_DIR)/logical/qspi_controller/logical/qspi_controller.sv
VERILOG_SOURCES += $(RTL_DIR)/logical/qspi_controller/logical/qspi_controller_mux.v
VERILOG_SOURCES += $(RTL_DIR)/logical/qspi_controller/logical/qspi_clock_div.v
VERILOG_SOURCES += $(VIP_DIR)/SST26VF064B.v

ifeq ($(SIM),vcs)
  COMPILE_ARGS += -sverilog +acc+3 -debug_access+all +neg_tchk
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
