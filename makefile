include $(SOCLABS_AHB_QSPI_DIR)/make.cfg

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
	DESIGN_VC ?= $(SOCLABS_AHB_QSPI_DIR)/flist/Top/ahb_QSPI_SIM.flist
endif

get_flash_model:
	@cd $(SOCLABS_AHB_QSPI_DIR)/verif/VIP; wget https://ww1.microchip.com/downloads/en/DeviceDoc/sst26wf040b.v

#Include flows
include ./flows/makefile.simulate

export BP210_DIR