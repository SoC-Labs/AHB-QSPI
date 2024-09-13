#-------------------------------------
# - Commonly Overloaded Variables
#-------------------------------------
# Simulator type (mti/vcs/xm)
SIMULATOR   = mti

#-------------------------------------
# - Directory Setups
#-------------------------------------
# Directory to put simulation files
SIM_TOP_DIR ?= $(SOCLABS_AHB_QSPI_DIR)/simulate/sim
SIM_DIR ?= $(SIM_TOP_DIR)


ifeq ($(ASIC),yes)
	DESIGN_VC ?= $(SOCLABS_AHB_QSPI_DIR)/flist/Top/ahb_QSPI_ASIC.flist
else
	DESIGN_VC ?= $(SOCLABS_AHB_QSPI_DIR)/flist/Top/ahb_QSPI.flist
endif

#Include flows
include ./flows/makefile.simulate
