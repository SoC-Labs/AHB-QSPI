//-----------------------------------------------------------------------------
// AHB QSPI Subsystem - Vivado IP Wrapper
// A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
//
// Contributors
//
// David Mapstone (d.a.mapstone@soton.ac.uk)
// Daniel Newbrook (d.newbrook@soton.ac.uk) - original ahb_qspi_fpga_wrapper.v
//
// Copyright (C) 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------
// Vivado IP Integrator wrapper for top_ahb_qspi. Exposes:
//   - AHB-Lite slave (XiP data path, decorated with Xilinx bus attributes)
//   - APB slave (register config path, decorated with Xilinx bus attributes)
//   - QSPI pads (SCLK, nCS, 4-bit bidirectional IO with output enable)
//   - HCLK/HRESETn and PCLK/PRESETn (tied together externally for FPGA)
//   - IRQ_QSPI_FINISHED (for PS IRQ_F2P routing)
//
// Connect the AHB-Lite slave to xilinx.com:ip:axi_ahblite_bridge:3.0 and the
// APB slave to xilinx.com:ip:axi_apb_bridge:3.0 in the block design.
//-----------------------------------------------------------------------------

module qspi_vivado_wrapper (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK.HCLK CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK.HCLK, ASSOCIATED_RESET HRESETn, ASSOCIATED_BUSIF S_AHB, FREQ_HZ 50000000, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.0" *)
    input  wire        HCLK,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RST.HRESETN RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RST.HRESETN, INSERT_VIP 0, POLARITY ACTIVE_LOW" *)
    input  wire        HRESETn,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK.PCLK CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK.PCLK, ASSOCIATED_RESET PRESETn, ASSOCIATED_BUSIF apb_interface, FREQ_HZ 50000000, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.0" *)
    input  wire        PCLK,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RST.PRESETN RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RST.PRESETN, INSERT_VIP 0, POLARITY ACTIVE_LOW" *)
    input  wire        PRESETn,

    // AHB-Lite slave (XiP data path)
    //
    // The xilinx.com:interface:ahblite:2.0 interface definition lists HSEL
    // and HREADY_IN as required slave sub-signals, but Xilinx's matching
    // masters (axi_ahblite_bridge 3.0) deliberately omit both — they assume
    // a single-slave bus where the slave is always selected and where the
    // slave's HREADY_OUT is the only HREADY on the wire. If we expose HSEL
    // and HREADY_IN through the interface annotation, Vivado auto-connect
    // leaves them unconnected (CRITICAL WARNING [BD 41-759]) and ties them
    // to 0 — the slave is then NEVER selected and every XiP read hangs the
    // PS.
    //
    // Fix: keep those two pins INTERNAL (no X_INTERFACE_INFO), hard-wire
    // HSEL=1 and feed HREADY_OUT back into HREADY_IN inside the wrapper.
    // Only expose HREADY_OUT as the single bus HREADY via sub-signal
    // "HREADY" so the bridge's m_ahb_hready input connects to it.
    (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HADDR" *)      input  wire [31:0] S_AHB_HADDR,
    (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HPROT" *)      input  wire  [3:0] S_AHB_HPROT,
    (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HTRANS" *)     input  wire  [1:0] S_AHB_HTRANS,
    (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HSIZE" *)      input  wire  [2:0] S_AHB_HSIZE,
    (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HWRITE" *)     input  wire        S_AHB_HWRITE,
    (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HBURST" *)     input  wire  [2:0] S_AHB_HBURST,
    (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HWDATA" *)     input  wire [31:0] S_AHB_HWDATA,
    (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HRDATA" *)     output wire [31:0] S_AHB_HRDATA,
    (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HRESP" *)      output wire        S_AHB_HRESP,
    (* X_INTERFACE_INFO = "xilinx.com:interface:ahblite:2.0 S_AHB HREADY" *)     output wire        S_AHB_HREADY,

    // APB slave (register config path)
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PADDR" *)   input  wire [31:0] apb_interface_PADDR,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PPROT" *)   input  wire  [2:0] apb_interface_PPROT,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PSEL" *)    input  wire        apb_interface_PSEL,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PENABLE" *) input  wire        apb_interface_PENABLE,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PWRITE" *)  input  wire        apb_interface_PWRITE,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PWDATA" *)  input  wire [31:0] apb_interface_PWDATA,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PSTRB" *)   input  wire  [3:0] apb_interface_PSTRB,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PREADY" *)  output wire        apb_interface_PREADY,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PRDATA" *)  output wire [31:0] apb_interface_PRDATA,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 apb_interface PSLVERR" *) output wire        apb_interface_PSLVERR,

    // QSPI pads (tristate convention: _e high = drive output)
    output wire        QSPI_SCLK,
    output wire        QSPI_nCS,
    output wire  [3:0] QSPI_IO_o,
    input  wire  [3:0] QSPI_IO_i,
    output wire  [3:0] QSPI_IO_e,

    // Interrupt (to PS IRQ_F2P)
    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq INTERRUPT" *)
    (* X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *)
    output wire        IRQ_QSPI_FINISHED,

    // Debug / LED wiring
    output wire        DBG_XIP_ACTIVE,
    output wire        DBG_SOFT_RESET
);

    // Bridge-driven AHB-Lite has no HSEL (single-slave — always selected)
    // and no shared HREADY (the bridge *reads* HREADY from us). Self-loop
    // HREADY so the slave's "previous transfer done" input matches its own
    // "this transfer done" output — correct for a 1-slave bus.
    wire s_ahb_hready_internal;
    assign S_AHB_HREADY = s_ahb_hready_internal;

    top_ahb_qspi u_top_ahb_qspi (
        .HCLK       (HCLK),
        .HRESETn    (HRESETn),
        .PCLK       (PCLK),
        .PRESETn    (PRESETn),

        .HADDR      (S_AHB_HADDR),
        .HTRANS     (S_AHB_HTRANS),
        .HWRITE     (S_AHB_HWRITE),
        .HSIZE      (S_AHB_HSIZE),
        .HBURST     (S_AHB_HBURST),
        .HPROT      (S_AHB_HPROT),
        .HWDATA     (S_AHB_HWDATA),
        .HSELx      (1'b1),
        .HRDATA     (S_AHB_HRDATA),
        .HREADY     (s_ahb_hready_internal),
        .HREADYOUT  (s_ahb_hready_internal),
        .HRESP      (S_AHB_HRESP),

        .PADDR      (apb_interface_PADDR[15:0]),
        .PPROT      (apb_interface_PPROT),
        .PSEL       (apb_interface_PSEL),
        .PENABLE    (apb_interface_PENABLE),
        .PWRITE     (apb_interface_PWRITE),
        .PWDATA     (apb_interface_PWDATA),
        .PSTRB      (apb_interface_PSTRB),
        .PRDATA     (apb_interface_PRDATA),
        .PREADY     (apb_interface_PREADY),
        .PSLVERR    (apb_interface_PSLVERR),

        .QSPI_SCLK  (QSPI_SCLK),
        .QSPI_nCS   (QSPI_nCS),
        .QSPI_IO_o  (QSPI_IO_o),
        .QSPI_IO_i  (QSPI_IO_i),
        .QSPI_IO_e  (QSPI_IO_e),

        .IRQ_QSPI_FINISHED (IRQ_QSPI_FINISHED),

        .DBG_XIP_ACTIVE    (DBG_XIP_ACTIVE),
        .DBG_SOFT_RESET    (DBG_SOFT_RESET)
    );

endmodule
