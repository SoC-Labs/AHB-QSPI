// =============================================================================
// A2 formal harness for ahb_qspi_interface (AHB-Lite slave properties).
//
// Assessor A2, 2026-10-13. Not part of the IP; read-only use of the RTL.
// Source: ~/SoCLabs/qspi-assess-A2 assess/A2 80e2ee8,
// formal/ahb_qspi_interface/ahb_if_formal.sv. Copied for the H-PIPE
// regression. Additions (all behind defines, so A2's checks are unchanged):
//   HPIPE_SRC  pass SOFT_RESET_HCLK_CYCLES to the DUT (fixed RTL only)
//   WDCOVER    cover: a read accepted after a watchdog ERROR completes OKAY
//              and was fetched (shows the *_wdsr checks are not vacuous)
//   HPIPE_INV  helper invariants for k-induction (hierarchical references
//              into the DUT; read with yosys-slang)
//   SLANG      set by gen_sby.sh for the yosys-slang frontend
//
// The harness instantiates the UNMODIFIED ahb_qspi_interface and drives it
// from:
//   * a legal AHB-Lite master (assumptions below), and
//   * an SCLK-side abstraction selected by CTRL_MODEL:
//       0 = free: AHB_QSPI_ENABLE_ACK / AHB_QSPI_BUSY / AHB_QSPI_RDATA are
//           unconstrained every cycle (the most hostile controller side).
//           Used for the response-shape properties (P3, P4, P5).
//       1 = handshake model: a nondeterministically-stalled controller that
//           obeys the ENABLE -> BUSY -> ACK -> ~ACK -> ~BUSY order and
//           returns RDATA = f(captured address) once BUSY falls. f(sym_addr)
//           = sym_data (anyconst); every other address returns junk.
//           Used for the transfer-accounting and data properties (P1, P2, P6).
//   MULTI = 0: this is the only slave; an unselected transfer goes to a
//              zero-wait default slave (HREADY = 1 in that data phase).
//   MULTI = 1: other slaves exist; HREADY is free in data phases that are not
//              ours (other slaves may insert wait states).
//
// Properties (all checked in the HCLK domain):
//   P1  every accepted read address phase is served by a fetch of ITS line:
//       an OKAY completion of an accepted read must have been preceded,
//       inside its own data phase, by a controller capture of its line.
//   P2  read data corresponds to the address accepted (symbolic tracker).
//   P3  IDLE and BUSY transfers to this slave get a zero-wait OKAY.
//   P4  ERROR is a two-cycle response (HREADYOUT=0,HRESP=1 then 1,1).
//   P5  no HRESP glitch: within a data phase, once HRESP=1 it stays 1 until
//       the transfer completes; HRESP=1 never appears on an IDLE/BUSY phase.
//   P6  a write, or any transfer while XIP is off, is answered ERROR (the
//       slave is read-only XIP; an OKAY would silently drop the write).
//
// Covers:
//   C_WR_EXIT   a read completes OKAY in the same cycle a new NONSEQ address
//               phase to this slave is accepted (WAIT_READ -> IDLE exit).
//   C_ERR2_EXIT the 2nd ERROR cycle accepts a new NONSEQ address phase
//               (ERR2 -> IDLE exit).
//   C_*_NEXT_OK the transfer accepted at that exit later completes OKAY.
// =============================================================================
`default_nettype none

module ahb_if_formal #(
    parameter WDW        = 4,   // ahb_qspi_interface WATCHDOG_WIDTH
    parameter CTRL_MODEL = 0,
    parameter MULTI      = 0,
    parameter XIP_FREE   = 0    // 0: XIP_ACTIVE is anyconst; 1: free, stable in a transfer
)(
    input  wire          HCLK,

    // Master-driven (free, constrained by assumptions)
    input  wire [21:0]   HADDR,
    input  wire [1:0]    HTRANS,
    input  wire          HWRITE,
    input  wire [2:0]    HSIZE,
    input  wire [127:0]  HWDATA,
    input  wire          HSELx,

    // Other-slave response (MULTI=1 only)
    input  wire          HREADY_other,

    input  wire          XIP_in,

    // Free SCLK side (CTRL_MODEL=0) and model nondeterminism (CTRL_MODEL=1)
    input  wire          ACK_free,
    input  wire          BUSY_free,
    input  wire [127:0]  RDATA_free,
    input  wire          m_go,
    input  wire          m_sr_go
);

    // ------------------------------------------------------------------
    // Reset: low for the first cycle, high afterwards.
    // ------------------------------------------------------------------
    reg init = 1'b1;
    always @(posedge HCLK) init <= 1'b0;
    wire HRESETn = ~init;

    // ------------------------------------------------------------------
    // Symbolic tracker constants
    // ------------------------------------------------------------------
`ifdef SLANG
    // yosys-slang ignores (* anyconst *): use never-written registers with
    // no initial value instead (arbitrary at step 0, constant afterwards).
    reg [21:0]  sym_addr;
    reg [127:0] sym_data;
    reg         xip_const;
    always @(posedge HCLK) begin
        sym_addr <= sym_addr; sym_data <= sym_data; xip_const <= xip_const;
    end
`else
    (* anyconst *) reg [21:0]  sym_addr;
    (* anyconst *) reg [127:0] sym_data;
    (* anyconst *) reg         xip_const;
`endif
    always @(*) assume(sym_addr[3:0] == 4'h0);

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    wire [127:0] HRDATA;
    wire         HREADYOUT, HRESP;
    wire         HREADY;
    wire         XIP_ACTIVE = XIP_FREE ? XIP_in : xip_const;

    wire         AHB_QSPI_ENABLE;
    wire [21:0]  AHB_QSPI_ADDR;
    wire         SOFT_RESET;
    wire         ACK, BUSY;
    wire [127:0] RDATA;

    ahb_qspi_interface #(
        .ADDR_W(22), .DATA_W(128), .WATCHDOG_WIDTH(WDW)
`ifdef HPIPE_SRC
        , .SOFT_RESET_HCLK_CYCLES(`HPIPE_SRC)
`endif
    ) dut (
        .HCLK(HCLK), .HRESETn(HRESETn),
        .HADDR(HADDR), .HTRANS(HTRANS), .HWRITE(HWRITE), .HSIZE(HSIZE),
        .HBURST(3'b000), .HPROT(4'b0011), .HWDATA(HWDATA), .HSELx(HSELx),
        .HRDATA(HRDATA), .HREADY(HREADY), .HREADYOUT(HREADYOUT), .HRESP(HRESP),
        .XIP_ACTIVE(XIP_ACTIVE),
        .AHB_QSPI_ENABLE(AHB_QSPI_ENABLE), .AHB_QSPI_READ(), .AHB_QSPI_WRITE(),
        .AHB_QSPI_ADDR_EN(), .AHB_QSPI_N_RW_BYTES(), .AHB_QSPI_ADDR(AHB_QSPI_ADDR),
        .AHB_QSPI_WDATA(),
        .AHB_QSPI_ENABLE_ACK(ACK), .AHB_QSPI_BUSY(BUSY), .AHB_QSPI_RDATA(RDATA),
        .SOFT_RESET(SOFT_RESET)
    );

    // ------------------------------------------------------------------
    // Bus model: the data-phase owner is the registered HSELx (standard
    // AHB-Lite multiplexor). HREADY is ours in our data phase.
    // ------------------------------------------------------------------
    reg        dp_sel;      // our data phase
    reg [1:0]  dp_trans;
    reg        dp_write;
    reg [21:0] dp_addr;
    reg        dp_xip;
    wire       other_ready = MULTI ? HREADY_other : 1'b1;
    assign HREADY = dp_sel ? HREADYOUT : other_ready;
    wire       HRESP_bus = dp_sel ? HRESP : 1'b0;

    wire acc = HRESETn && HREADY && HSELx && HTRANS[1];   // our NONSEQ/SEQ accepted

    always @(posedge HCLK) begin
        if (!HRESETn) begin
            dp_sel <= 1'b0; dp_trans <= 2'b00; dp_write <= 1'b0;
            dp_addr <= 22'd0; dp_xip <= 1'b0;
        end else if (HREADY) begin
            dp_sel <= HSELx; dp_trans <= HTRANS; dp_write <= HWRITE;
            dp_addr <= HADDR; dp_xip <= XIP_ACTIVE;
        end
    end

    // ------------------------------------------------------------------
    // AHB-Lite master assumptions
    // ------------------------------------------------------------------
    reg        p_valid = 1'b0;
    reg        p_ready, p_err1;
    reg [1:0]  p_trans;
    reg [21:0] p_addr;
    reg        p_write, p_sel;
    reg [2:0]  p_size;
    always @(posedge HCLK) begin
        p_valid <= HRESETn;
        p_ready <= HREADY;
        p_err1  <= HRESP_bus && !HREADY;
        p_trans <= HTRANS; p_addr <= HADDR; p_write <= HWRITE;
        p_sel <= HSELx; p_size <= HSIZE;
    end
    always @(*) begin
        if (HRESETn && p_valid && !p_ready && p_trans[1]) begin
            // A waited NONSEQ/SEQ address phase must be held...
            if (p_err1) begin
                // ...except that after the first ERROR cycle the master may
                // cancel the next transfer by driving IDLE (AHB-Lite 5.1.3).
                assume((HTRANS == p_trans && HADDR == p_addr && HWRITE == p_write &&
                        HSELx == p_sel && HSIZE == p_size) || HTRANS == 2'b00);
            end else begin
                assume(HTRANS == p_trans && HADDR == p_addr && HWRITE == p_write &&
                       HSELx == p_sel && HSIZE == p_size);
            end
        end
`ifdef RDONLY
        // Restrict the master to reads with XIP on, so that any P1/P2
        // counterexample must go through the WAIT_READ -> IDLE exit (no
        // ERROR path at all).
        assume(!HWRITE && XIP_ACTIVE);
`endif
`ifdef NOPIPE
        // Restrict the master so that no address phase to this slave is
        // accepted in the same cycle one of our data phases completes (no
        // back-to-back to this slave). Used to show that the base passes
        // P1/P2 once H-PIPE stimulus is excluded.
        assume(!(HRESETn && dp_sel && HREADYOUT && HSELx && HTRANS[1]));
`endif
        // SEQ only continues a burst (previous accepted transfer not IDLE)
        // (and stays on the same slave: a burst never crosses a slave)
        if (HTRANS == 2'b11) assume(p_valid && p_trans != 2'b00 && HSELx == p_sel);
        // XIP_ACTIVE is a PCLK register: when free, it may only change when
        // no transfer is in a data phase (software never flips it mid-read).
        if (XIP_FREE && p_valid && dp_sel) assume(XIP_in == dp_xip);
    end

    // ------------------------------------------------------------------
    // SCLK-side abstraction
    // ------------------------------------------------------------------
    localparam M_IDLE = 2'd0, M_BUSY = 2'd1, M_ACK = 2'd2, M_RUN = 2'd3;
    reg [1:0]   m_st;
    reg         m_busy, m_ack;
    reg [21:0]  m_addr;
    reg [127:0] m_rdata;
    reg         m_cap;          // pulses in the cycle the model captures an address

    always @(posedge HCLK) begin
        m_cap <= 1'b0;
        if (!HRESETn) begin
            m_st <= M_IDLE; m_busy <= 1'b0; m_ack <= 1'b0;
            m_addr <= 22'd0; m_rdata <= RDATA_free;
        end else if (SOFT_RESET && m_sr_go) begin
            // the synchronised soft reset reaches the controller at some
            // nondeterministic point while SOFT_RESET is held
            m_st <= M_IDLE; m_busy <= 1'b0; m_ack <= 1'b0; m_rdata <= RDATA_free;
        end else begin
            case (m_st)
                M_IDLE: if (AHB_QSPI_ENABLE && m_go) begin
                            m_st <= M_BUSY; m_busy <= 1'b1; m_addr <= AHB_QSPI_ADDR;
                            m_cap <= 1'b1;
                        end
                M_BUSY: if (m_go) begin m_st <= M_ACK; m_ack <= 1'b1; end
                M_ACK:  if (m_go) begin m_st <= M_RUN; m_ack <= 1'b0; end
                // The real controller's transaction (>= ~40 SCLK in QPI) is far
                // longer than the ENABLE round trip, and NO_FETCH waits for
                // ~enable_sync explicitly: the controller never returns to IDLE
                // while ENABLE is still high. Encode that as a model contract.
                M_RUN:  if (m_go && !AHB_QSPI_ENABLE) begin m_st <= M_IDLE; m_busy <= 1'b0; end
            endcase
            // RDATA is shifting while BUSY; it is f(addr) once BUSY falls
            if (m_st == M_RUN && m_go && !AHB_QSPI_ENABLE)
                m_rdata <= (m_addr == sym_addr) ? sym_data : RDATA_free;
            else if (m_busy)
                m_rdata <= RDATA_free;
        end
    end

    assign ACK   = CTRL_MODEL ? m_ack   : ACK_free;
    assign BUSY  = CTRL_MODEL ? m_busy  : BUSY_free;
    assign RDATA = CTRL_MODEL ? m_rdata : RDATA_free;

    // ------------------------------------------------------------------
    // Expected HRDATA for sym_data (same word/byte lane mapping as the RTL,
    // ahb_qspi_interface.sv:89-94)
    // ------------------------------------------------------------------
    wire [31:0] e_w0 = {sym_data[71:64],  sym_data[79:72],  sym_data[87:80],  sym_data[95:88]};
    wire [31:0] e_w1 = {sym_data[39:32],  sym_data[47:40],  sym_data[55:48],  sym_data[63:56]};
    wire [31:0] e_w2 = {sym_data[7:0],    sym_data[15:8],   sym_data[23:16],  sym_data[31:24]};
    wire [31:0] e_w3 = {sym_data[103:96], sym_data[111:104],sym_data[119:112],sym_data[127:120]};
    wire [127:0] exp_hrdata = {e_w3, e_w0, e_w1, e_w2};

    // ------------------------------------------------------------------
    // Fetch accounting for P1: did the controller capture THIS data phase's
    // line while the data phase was open?
    // ------------------------------------------------------------------
    reg dp_fetched;
    always @(posedge HCLK) begin
        if (!HRESETn)
            dp_fetched <= 1'b0;
        else if (HREADY)
            dp_fetched <= 1'b0;                 // new data phase starts
        else if (dp_sel && m_cap && m_addr == {dp_addr[21:4], 4'h0})
            dp_fetched <= 1'b1;
    end
    // m_cap is registered one cycle after the capture decision; the capture
    // itself (m_addr update) happens on the same edge, so m_addr is valid here.

    wire complete      = HRESETn && dp_sel && HREADY;            // our data phase ends
    wire complete_okay = complete && !HRESP;
    wire rd_xfer       = dp_trans[1] && !dp_write && dp_xip;

    // ------------------------------------------------------------------
    // Properties
    // ------------------------------------------------------------------
    reg q_err1;     // previous cycle was ERR phase 1 in our data phase
    reg q_sel_open; // previous cycle was an open (waited) data phase of ours
    reg q_resp;     // HRESP in the previous cycle
    always @(posedge HCLK) begin
        q_resp     <= HRESP;
        q_err1     <= HRESETn && dp_sel && HRESP && !HREADYOUT;
        q_sel_open <= HRESETn && dp_sel && !HREADY;
    end

    always @(*) begin
        if (HRESETn && p_valid) begin
`ifdef P1
            // P1: an OKAY read was fetched for its own line
            if (CTRL_MODEL && complete_okay && rd_xfer)
                assert(dp_fetched);
`endif
`ifdef P2
            // P2: an OKAY read of the tracked line returns the tracked data
            if (CTRL_MODEL && complete_okay && rd_xfer &&
                dp_addr[21:4] == sym_addr[21:4])
                assert(HRDATA == exp_hrdata);
`endif
`ifdef P3
            // P3: IDLE/BUSY to this slave -> zero-wait OKAY
            if (dp_sel && !dp_trans[1])
                assert(HREADYOUT && !HRESP);
`endif
`ifdef P4
            // P4a: an ERROR completion must follow an ERROR phase-1 cycle
            if (dp_sel && HRESP && HREADYOUT)
                assert(q_err1 && q_sel_open);
            // P4b: ERROR phase 1 is followed by ERROR phase 2
            if (q_err1)
                assert(dp_sel && HRESP && HREADYOUT);
`endif
`ifdef P5
            // P5: once HRESP rises inside an open data phase it stays high
            //     until completion (no ERROR -> OKAY glitch), and no HRESP
            //     on an IDLE/BUSY data phase
            if (q_sel_open && q_resp)
                assert(HRESP);
            if (dp_sel && !dp_trans[1])
                assert(!HRESP);
`endif
`ifdef P6
            // P6: writes and XIP-off transfers must be answered ERROR
            if (complete && dp_trans[1] && (dp_write || !dp_xip))
                assert(HRESP);
`endif
        end
    end

    // ------------------------------------------------------------------
    // Covers
    // ------------------------------------------------------------------
    reg wr_exit_q, err2_exit_q;
    always @(posedge HCLK) begin
        if (!HRESETn) begin
            wr_exit_q <= 1'b0; err2_exit_q <= 1'b0;
        end else begin
            if (complete_okay && rd_xfer && acc)            wr_exit_q <= 1'b1;
            else if (complete)                              wr_exit_q <= 1'b0;
            if (complete && HRESP && acc)                   err2_exit_q <= 1'b1;
            else if (complete)                              err2_exit_q <= 1'b0;
        end
    end
    // wr_exit_q / err2_exit_q are 1 during the data phase of the transfer
    // accepted at the exit, and cleared at its completion.
    always @(*) begin
        if (HRESETn) begin
            cover(complete_okay && rd_xfer && acc);                 // C_WR_EXIT
            cover(complete && HRESP && acc);                        // C_ERR2_EXIT
            cover(wr_exit_q && complete_okay);                      // C_WR_NEXT_OK
            cover(err2_exit_q && complete_okay);                    // C_ERR2_NEXT_OK
            cover(wr_exit_q && complete_okay && rd_xfer && dp_fetched); // ...and fetched
        end
    end

`ifdef WDCOVER
    // A read accepted after the first watchdog ERROR completes OKAY, fetched.
    reg wd_seen;
    always @(posedge HCLK) begin
        if (!HRESETn)        wd_seen <= 1'b0;
        else if (SOFT_RESET) wd_seen <= 1'b1;
    end
    reg wd_rd_open;   // a read data phase that was accepted after wd_seen
    always @(posedge HCLK) begin
        if (!HRESETn)                         wd_rd_open <= 1'b0;
        else if (HREADY)                      wd_rd_open <= wd_seen && acc && !HWRITE;
    end
    always @(*) if (HRESETn) cover(wd_rd_open && complete_okay && rd_xfer && dp_fetched);
`endif

`ifdef HPIPE_INV
`include "hpipe_inv.svh"
`endif

endmodule
`default_nettype wire
