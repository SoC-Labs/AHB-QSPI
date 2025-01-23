include $(SOCLABS_AHB_QSPI_DIR)/make.cfg

#-------------------------------------
# - Commonly Overloaded Variables
#-------------------------------------
# Simulator type (mti/vcs/xm)
SIMULATOR   = vcs
GATE_SIMS  ?= no
export GATE_SIMS
#-------------------------------------
# - Directory Setups
#-------------------------------------
# Directory to put simulation files
SIM_TOP_DIR ?= $(SOCLABS_AHB_QSPI_DIR)/simulate/sim
SIM_DIR ?= $(SIM_TOP_DIR)


ifeq ($(ASIC),yes)
	DESIGN_VC ?= $(SOCLABS_AHB_QSPI_DIR)/flist/Top/ahb_QSPI_ASIC.flist
else ifeq ($(GATE_SIMS),yes)
	DESIGN_VC ?= $(SOCLABS_AHB_QSPI_DIR)/flist/Top/ahb_QSPI_SIM_GATES.flist
else
	DESIGN_VC ?= $(SOCLABS_AHB_QSPI_DIR)/flist/Top/ahb_QSPI_SIM.flist
endif

get_flash_model:
	@cd $(SOCLABS_AHB_QSPI_DIR)/verif/VIP; wget https://ww1.microchip.com/downloads/en/DeviceDoc/SST26VF064B.zip 
	@cd $(SOCLABS_AHB_QSPI_DIR)/verif/VIP; unzip SST26VF064B.zip
	@cd $(SOCLABS_AHB_QSPI_DIR)/verif/VIP; rm SST26VF064B.zip

#Include flows
include ./flows/makefile.simulate
include ./flows/makefile.lint
include ./flows/makefile.asic
export BP210_DIR