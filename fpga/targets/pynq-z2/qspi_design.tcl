###-----------------------------------------------------------------------------
### AHB QSPI Subsystem - Pynq-Z2 Block Design TCL
### A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
###
### Contributors
###
### David Mapstone (d.a.mapstone@soton.ac.uk)
###
### Copyright (C) 2026, SoC Labs (www.soclabs.org)
###-----------------------------------------------------------------------------
### Creates a Vivado block design for the Pynq-Z2 (Zynq XC7Z020CLG400-1)
### containing:
###   - Zynq PS7 (FCLK_CLK0=100MHz, M_AXI_GP0 enabled for PYNQ MMIO)
###   - Clocking Wizard (100 MHz -> 50 MHz for the QSPI subsystem)
###   - Processor System Reset (synchronized to 50 MHz domain)
###   - AXI SmartConnect (1 master, 2 slaves)
###   - AXI4-Lite -> AHB-Lite bridge -> qspi_ip S_AHB (XiP data path)
###   - AXI4-Lite -> APB bridge      -> qspi_ip apb_interface (config regs)
###   - QSPI subsystem IP (qspi_vivado_wrapper)
###
### QSPI tristate IO is exposed as separate _o/_i/_e ports; the board-level
### wrapper inserts the IOBUF primitives.
###-----------------------------------------------------------------------------

proc create_root_design { parentCell } {

    if { $parentCell eq "" } {
        set parentCell [get_bd_cells /]
    }

    set parentObj [get_bd_cells $parentCell]
    if { $parentObj == "" } {
        catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
        return
    }

    set parentType [get_property TYPE $parentObj]
    if { $parentType ne "hier" } {
        catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
        return
    }

    set oldCurInst [current_bd_instance .]
    current_bd_instance $parentObj

    ###################################################################
    # CREATE EXTERNAL PORTS
    ###################################################################

    # QSPI pads (tristate handled in board wrapper)
    create_bd_port -dir O          qspi_sclk
    create_bd_port -dir O          qspi_cs_n
    create_bd_port -dir O -from 3 -to 0 qspi_io_o
    create_bd_port -dir I -from 3 -to 0 qspi_io_i
    create_bd_port -dir O -from 3 -to 0 qspi_io_e

    # Debug / activity signals for board LEDs
    create_bd_port -dir O          irq_qspi_finished

    # DDR and Fixed IO (Zynq PS)
    create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR
    create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO

    ###################################################################
    # CREATE IP INSTANCES
    ###################################################################

    #------------------------------------------------------------------
    # Zynq Processing System 7
    # M_AXI_GP0 enabled so PS-side Python (PYNQ MMIO) can drive the QSPI
    # subsystem registers and XiP data path.
    #------------------------------------------------------------------
    set processing_system7_0 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]
    set_property -dict [list \
        CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
        CONFIG.PCW_FPGA_FCLK0_ENABLE {1} \
        CONFIG.PCW_EN_CLK0_PORT {1} \
        CONFIG.PCW_EN_RST0_PORT {1} \
        CONFIG.PCW_USE_M_AXI_GP0 {1} \
        CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
        CONFIG.PCW_IRQ_F2P_INTR {1} \
        CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
        CONFIG.PCW_UART0_UART0_IO {MIO 14 .. 15} \
        CONFIG.PCW_EN_UART0 {1} \
        CONFIG.PCW_UART0_BAUD_RATE {115200} \
        CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125} \
        CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3 (Low Voltage)} \
    ] $processing_system7_0

    #------------------------------------------------------------------
    # Clocking Wizard: 100 MHz -> 50 MHz
    # 50 MHz HCLK -> QSPI_SCLK = HCLK / (2*CLK_DIV). With CLK_DIV=5
    # (the cocotb default) QSPI_SCLK = 5 MHz, well within PmodSF3 limits.
    #------------------------------------------------------------------
    set clk_wiz_0 [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0]
    set_property -dict [list \
        CONFIG.PRIM_IN_FREQ {100.000} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {50.000} \
        CONFIG.CLKOUT1_USED {true} \
        CONFIG.USE_LOCKED {true} \
        CONFIG.USE_RESET {true} \
        CONFIG.RESET_TYPE {ACTIVE_LOW} \
        CONFIG.RESET_PORT {resetn} \
    ] $clk_wiz_0

    #------------------------------------------------------------------
    # Processor System Reset (synchronized to 50 MHz domain)
    #------------------------------------------------------------------
    set proc_sys_reset_0 [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0]

    #------------------------------------------------------------------
    # AXI SmartConnect: 1 PS master -> 2 slaves (AHB bridge, APB bridge)
    #------------------------------------------------------------------
    set axi_smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc]
    set_property -dict [list \
        CONFIG.NUM_SI {1} \
        CONFIG.NUM_MI {2} \
        CONFIG.NUM_CLKS {1} \
    ] $axi_smc

    #------------------------------------------------------------------
    # AXI4-Lite -> AHB-Lite bridge (XiP data path)
    #------------------------------------------------------------------
    set axi_ahb [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_ahblite_bridge:3.0 axi_ahb]

    #------------------------------------------------------------------
    # AXI4-Lite -> APB bridge (config registers)
    #------------------------------------------------------------------
    set axi_apb [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_apb_bridge:3.0 axi_apb]
    set_property -dict [list \
        CONFIG.C_APB_NUM_SLAVES {1} \
    ] $axi_apb

    #------------------------------------------------------------------
    # AHB QSPI Subsystem IP
    #------------------------------------------------------------------
    set qspi_ip_0 [create_bd_cell -type ip -vlnv soclabs.org:user:qspi_vivado_wrapper:1.0 qspi_ip_0]

    ###################################################################
    # CONNECTIONS
    ###################################################################

    #-- Zynq PS DDR and Fixed IO
    connect_bd_intf_net [get_bd_intf_ports DDR] [get_bd_intf_pins processing_system7_0/DDR]
    connect_bd_intf_net [get_bd_intf_ports FIXED_IO] [get_bd_intf_pins processing_system7_0/FIXED_IO]

    #-- Clock: PS FCLK_CLK0 (100 MHz) -> Clocking Wizard input
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
                   [get_bd_pins clk_wiz_0/clk_in1]

    #-- Reset: PS FCLK_RESET0_N -> clk_wiz resetn + proc_sys_reset ext_reset_in
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
                   [get_bd_pins clk_wiz_0/resetn] \
                   [get_bd_pins proc_sys_reset_0/ext_reset_in]

    #-- Reset: clk_wiz locked -> proc_sys_reset dcm_locked
    connect_bd_net [get_bd_pins clk_wiz_0/locked] \
                   [get_bd_pins proc_sys_reset_0/dcm_locked]

    #-- Clock fan-out: clk_wiz output (50 MHz) drives QSPI_HCLK domain.
    #   PS M_AXI_GP0 also runs on this clock (single clock domain through
    #   the SmartConnect avoids any AXI-side CDC). Both bridges have a
    #   single ACLK pin; the master-side AHB/APB use the same clock.
    connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] \
                   [get_bd_pins proc_sys_reset_0/slowest_sync_clk] \
                   [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK] \
                   [get_bd_pins axi_smc/aclk] \
                   [get_bd_pins axi_ahb/s_axi_aclk] \
                   [get_bd_pins axi_apb/s_axi_aclk] \
                   [get_bd_pins qspi_ip_0/HCLK] \
                   [get_bd_pins qspi_ip_0/PCLK]

    #-- Reset fan-out (active-low). Each bridge has a single ARESETN.
    connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
                   [get_bd_pins axi_smc/aresetn] \
                   [get_bd_pins axi_ahb/s_axi_aresetn] \
                   [get_bd_pins axi_apb/s_axi_aresetn] \
                   [get_bd_pins qspi_ip_0/HRESETn] \
                   [get_bd_pins qspi_ip_0/PRESETn]

    #-- AXI: PS M_AXI_GP0 -> SmartConnect
    connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
                        [get_bd_intf_pins axi_smc/S00_AXI]

    #-- AXI: SmartConnect -> AHB bridge -> QSPI S_AHB
    #   axi_ahblite_bridge bus-interface names (Vivado 2024.1):
    #     slave  = AXI4
    #     master = M_AHB
    connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] \
                        [get_bd_intf_pins axi_ahb/AXI4]
    connect_bd_intf_net [get_bd_intf_pins axi_ahb/M_AHB] \
                        [get_bd_intf_pins qspi_ip_0/S_AHB]

    #-- AXI: SmartConnect -> APB bridge -> QSPI apb_interface
    #   axi_apb_bridge bus-interface names (Vivado 2024.1):
    #     slave  = AXI4_LITE
    #     master = APB_M
    connect_bd_intf_net [get_bd_intf_pins axi_smc/M01_AXI] \
                        [get_bd_intf_pins axi_apb/AXI4_LITE]
    connect_bd_intf_net [get_bd_intf_pins axi_apb/APB_M] \
                        [get_bd_intf_pins qspi_ip_0/apb_interface]

    #-- IRQ: QSPI -> PS IRQ_F2P[0] + debug port
    connect_bd_net [get_bd_pins qspi_ip_0/IRQ_QSPI_FINISHED] \
                   [get_bd_pins processing_system7_0/IRQ_F2P] \
                   [get_bd_ports irq_qspi_finished]

    #-- QSPI pads to external ports
    connect_bd_net [get_bd_pins qspi_ip_0/QSPI_SCLK] [get_bd_ports qspi_sclk]
    connect_bd_net [get_bd_pins qspi_ip_0/QSPI_nCS]  [get_bd_ports qspi_cs_n]
    connect_bd_net [get_bd_pins qspi_ip_0/QSPI_IO_o] [get_bd_ports qspi_io_o]
    connect_bd_net [get_bd_ports qspi_io_i]          [get_bd_pins qspi_ip_0/QSPI_IO_i]
    connect_bd_net [get_bd_pins qspi_ip_0/QSPI_IO_e] [get_bd_ports qspi_io_e]

    ###################################################################
    # ADDRESS MAP
    #
    # AHB bridge (XiP) at 0x4000_0000, 16 MB (matches SPI_ADDR width = 22b
    # plus byte offset; covers full PmodSF3 low half).
    # APB bridge (regs) at 0x4200_0000, 64 KB (covers PADDR[15:0] and the
    # CG092 cache regs at 0x1000).
    ###################################################################
    assign_bd_address -offset 0x40000000 -range 0x01000000 \
        [get_bd_addr_segs {qspi_ip_0/S_AHB/Reg}]
    assign_bd_address -offset 0x42000000 -range 0x00010000 \
        [get_bd_addr_segs {qspi_ip_0/apb_interface/Reg}]

    ###################################################################
    # VALIDATE AND SAVE
    ###################################################################
    validate_bd_design
    save_bd_design

    current_bd_instance $oldCurInst
}
