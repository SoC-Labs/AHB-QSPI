//-----------------------------------------------------------------------------
// AHB QSPI Subsystem - Pynq-Z2 Board-Level Wrapper
// A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
//
// Contributors
//
// David Mapstone (d.a.mapstone@soton.ac.uk)
//
// Copyright (C) 2026, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------
// Top-level wrapper for Pynq-Z2 deployment. Instantiates the qspi_design
// block design and inserts IOBUF primitives on the bidirectional QSPI IO[3:0]
// pads. PmodSF3 (Micron N25Q256 / MT25QL256 family) connects on PMODA.
//-----------------------------------------------------------------------------

module qspi_design_wrapper (
    // DDR3 Interface (to Zynq PS)
    inout  wire [14:0] DDR_addr,
    inout  wire  [2:0] DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire  [3:0] DDR_dm,
    inout  wire [31:0] DDR_dq,
    inout  wire  [3:0] DDR_dqs_n,
    inout  wire  [3:0] DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,

    // Fixed IO (Zynq PS)
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb,

    // PmodSF3 on PMODA (Pynq-Z2 v1.0)
    output wire        qspi_sclk,           // JA4 / Y17
    output wire        qspi_cs_n,           // JA1 / Y18
    inout  wire  [3:0] qspi_io,             // JA2,JA3,JA7,JA8 = Y19,Y16,U18,U19

    // Board LEDs (accent green, accent active-high)
    output wire        led0,                 // LD0 / R14 - heartbeat (FPGA alive)
    output wire        led1,                 // LD1 / P14 - SPI active (CS low)
    output wire        led2,                 // LD2 / N16 - IRQ pulse (transaction done)
    output wire        led3                  // LD3 / M14 - unused / reserved
);

    //=========================================================================
    // QSPI bidirectional IO - one IOBUF per data line
    //
    // Internal naming convention from top_ahb_qspi:
    //   QSPI_IO_o[3:0]  output data
    //   QSPI_IO_i[3:0]  input data sampled from pad
    //   QSPI_IO_e[3:0]  active-high output enable (1 = drive pad)
    //
    // Vivado IOBUF primitive convention:
    //   T = 1 -> Hi-Z (tristate active-high disable)
    //   So T = ~QSPI_IO_e
    //=========================================================================
    wire [3:0] qspi_io_o;
    wire [3:0] qspi_io_i;
    wire [3:0] qspi_io_e;

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_qspi_iobuf
            IOBUF u_iobuf (
                .I  (qspi_io_o[gi]),
                .O  (qspi_io_i[gi]),
                .T  (~qspi_io_e[gi]),
                .IO (qspi_io[gi])
            );
        end
    endgenerate

    //=========================================================================
    // Debug LEDs — accent active-high, accent accent accent
    //
    // LD0 (R14): ~CS_n        — lit whenever SPI chip-select is active
    // LD1 (P14): QSPI_SCLK   — blinks/glows during SPI clock activity
    // LD2 (N16): IRQ_FINISHED — pulses on each transaction complete
    // LD3 (M14): tied low     — reserved
    //=========================================================================
    wire irq_qspi_finished;

    assign led0 = ~qspi_cs_n;
    assign led1 = qspi_sclk;
    assign led2 = irq_qspi_finished;
    assign led3 = 1'b0;

    //=========================================================================
    // Block Design Instance
    //=========================================================================
    qspi_design qspi_design_i (
        // DDR
        .DDR_addr          (DDR_addr),
        .DDR_ba            (DDR_ba),
        .DDR_cas_n         (DDR_cas_n),
        .DDR_ck_n          (DDR_ck_n),
        .DDR_ck_p          (DDR_ck_p),
        .DDR_cke           (DDR_cke),
        .DDR_cs_n          (DDR_cs_n),
        .DDR_dm            (DDR_dm),
        .DDR_dq            (DDR_dq),
        .DDR_dqs_n         (DDR_dqs_n),
        .DDR_dqs_p         (DDR_dqs_p),
        .DDR_odt           (DDR_odt),
        .DDR_ras_n         (DDR_ras_n),
        .DDR_reset_n       (DDR_reset_n),
        .DDR_we_n          (DDR_we_n),

        // Fixed IO
        .FIXED_IO_ddr_vrn  (FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp  (FIXED_IO_ddr_vrp),
        .FIXED_IO_mio      (FIXED_IO_mio),
        .FIXED_IO_ps_clk   (FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb  (FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb (FIXED_IO_ps_srstb),

        // QSPI
        .qspi_sclk         (qspi_sclk),
        .qspi_cs_n         (qspi_cs_n),
        .qspi_io_o         (qspi_io_o),
        .qspi_io_i         (qspi_io_i),
        .qspi_io_e         (qspi_io_e),

        // Debug
        .irq_qspi_finished (irq_qspi_finished)
    );

endmodule
