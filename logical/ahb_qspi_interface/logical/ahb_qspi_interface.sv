
module ahb_qspi_interface #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    // Width of the WAIT_READ watchdog counter. Default 16 bits gives
    // 65536 HCLK cycles (~1.3 ms at 50 MHz HCLK) which is:
    //   - ~6x margin over worst-case transaction at CLK_DIV=31
    //     (168 SCLK * 62 HCLK/SCLK = 10416 HCLK)
    //   - Headroom for any reasonable XIP operation across the full
    //     CLK_DIV=[0..31] range
    // A 12-bit (4096 HCLK, ~82 us) counter is too tight — it fires on
    // any CLK_DIV >= 12, where the legitimate FAST_READ transaction
    // already takes 4032+ HCLK cycles, causing the Xilinx bridge to
    // return AXI SLVERR (bus error / SIGBUS) mid-stress-test.
    // Override to smaller values for tight simulation loops (the
    // cocotbext.ahb master has a 5000-cycle internal timeout).
    parameter WATCHDOG_WIDTH = 16
    )(
    input  wire                 HCLK,
    input  wire                 HRESETn,

    // AHB Signals
    input  wire [ADDR_W-1:0]    HADDR,
    input  wire [1:0]           HTRANS,
    input  wire                 HWRITE,
    input  wire [2:0]           HSIZE,
    input  wire [2:0]           HBURST,
    input  wire [3:0]           HPROT,
    input  wire [DATA_W-1:0]    HWDATA,
    input  wire                 HSELx,
    output reg  [DATA_W-1:0]    HRDATA,
    input  wire                 HREADY,
    output wire                 HREADYOUT,
    output wire                 HRESP,

    input  wire                 XIP_ACTIVE,

    output reg                  AHB_QSPI_ENABLE,
    output wire                 AHB_QSPI_READ,
    output wire                 AHB_QSPI_WRITE,
    output wire                 AHB_QSPI_ADDR_EN,
    output wire [3:0]           AHB_QSPI_N_RW_BYTES,
    output reg  [21:0]          AHB_QSPI_ADDR,
    output wire [127:0]         AHB_QSPI_WDATA,

    input  wire                 AHB_QSPI_ENABLE_ACK,
    input  wire                 AHB_QSPI_BUSY,
    input  wire [127:0]         AHB_QSPI_RDATA,

    // Soft-reset request to the QSPI controller. Pulsed high for several
    // HCLK cycles when the WAIT_READ watchdog expires, so the downstream
    // controller FSM returns to IDLE instead of remaining wedged in
    // whatever state caused the hang. Without this, a hang survivor
    // would see the watchdog release the AHB bus but the next XiP read
    // would immediately hang again.
    output reg                  SOFT_RESET
);

assign AHB_QSPI_ADDR_EN = 1'b1;
assign AHB_QSPI_READ=1'b1;
assign AHB_QSPI_WRITE=1'b0;
assign AHB_QSPI_WDATA = HWDATA;
assign AHB_QSPI_N_RW_BYTES = 4'hF;

// 2-FF CDC synchronizers for signals from QSPI_SCLK_i domain into HCLK domain
reg ahb_qspi_enable_ack_meta, ahb_qspi_enable_ack_sync;
reg ahb_qspi_busy_meta,       ahb_qspi_busy_sync;

always @(posedge HCLK or negedge HRESETn) begin
    if(~HRESETn) begin
        ahb_qspi_enable_ack_meta <= 1'b0;
        ahb_qspi_enable_ack_sync <= 1'b0;
        ahb_qspi_busy_meta       <= 1'b0;
        ahb_qspi_busy_sync       <= 1'b0;
    end else begin
        ahb_qspi_enable_ack_meta <= AHB_QSPI_ENABLE_ACK;
        ahb_qspi_enable_ack_sync <= ahb_qspi_enable_ack_meta;
        ahb_qspi_busy_meta       <= AHB_QSPI_BUSY;
        ahb_qspi_busy_sync       <= ahb_qspi_busy_meta;
    end
end

// AHB_QSPI_RDATA is safe-by-protocol: the 128-bit data from the QSPI_SCLK_i
// domain is guaranteed stable for multiple cycles before QSPI_BUSY deasserts.
// The synchronized ahb_qspi_busy_sync serves as the valid qualifier — by the
// time it deasserts in the HCLK domain, RDATA has been stable for at least
// 2 HCLK cycles (the sync latency), providing adequate setup margin.

wire [31:0] AHB_QSPI_RDATA_W0 = {AHB_QSPI_RDATA[71:64],AHB_QSPI_RDATA[79:72],AHB_QSPI_RDATA[87:80],AHB_QSPI_RDATA[95:88]}; //AHB_QSPI_RDATA[95:64];
wire [31:0] AHB_QSPI_RDATA_W1 = {AHB_QSPI_RDATA[39:32], AHB_QSPI_RDATA[47:40], AHB_QSPI_RDATA[55:48], AHB_QSPI_RDATA[63:56]}; //AHB_QSPI_RDATA[63:32]; //94000049
wire [31:0] AHB_QSPI_RDATA_W2 = {AHB_QSPI_RDATA[7:0], AHB_QSPI_RDATA[15:8], AHB_QSPI_RDATA[23:16], AHB_QSPI_RDATA[31:24]};
wire [31:0] AHB_QSPI_RDATA_W3 = {AHB_QSPI_RDATA[103:96],AHB_QSPI_RDATA[111:104],AHB_QSPI_RDATA[119:112],AHB_QSPI_RDATA[127:120]};//AHB_QSPI_RDATA[127:96];

wire [127:0] AHB_QSPI_RDATA_i = {AHB_QSPI_RDATA_W3,AHB_QSPI_RDATA_W0, AHB_QSPI_RDATA_W1, AHB_QSPI_RDATA_W2};

// AHB FSM
//
// ERR is split into two states (ERR1 -> ERR2) to emit a spec-compliant
// two-cycle AHB-Lite error response:
//   ERR1: HREADYOUT=0, HRESP=1   (error phase 1)
//   ERR2: HREADYOUT=1, HRESP=1   (error phase 2, master samples)
// A single-cycle "HREADYOUT=1 & HRESP=1" pulse is accepted by the
// cocotbext.ahb model but rejected by Xilinx's axi_ahblite_bridge 3.0 on
// real hardware — without the split, a watchdog-driven recovery fires on
// the FPGA but the AXI side never accepts the error and stays stuck,
// wedging the PS. See AMBA AHB-Lite spec §5.1.3.
enum {IDLE, WAIT_READ, ERR1, ERR2} current_state, next_state;

// Watchdog timeout (Layer 1 fix for the XiP lockup bug).
//
// Without this timer, any fault that prevents qspi_ready from rising —
// CDC pulse loss, downstream FSM wedge, upstream reset glitch — leaves
// HREADYOUT stuck low forever. That propagates back through the AXI-AHB
// bridge to the PS CPU, which blocks indefinitely on the MMIO read, and
// the kernel hangs.
//
// Sizing: worst-case XiP transaction at CLK_DIV=31 is ~10k HCLK cycles.
// The default 16-bit counter (65k HCLK ~= 1.3 ms at 50 MHz) gives ~6x
// margin — any longer and something is genuinely wrong; raise HRESP=1,
// release the bus, and let the OS recover.
reg  [WATCHDOG_WIDTH-1:0] watchdog_cnt;
wire                       watchdog_expired =
                               (watchdog_cnt == {WATCHDOG_WIDTH{1'b1}});

// AHB lite last regs
reg                 last_HSEL;
reg [ADDR_W-1:0]    last_HADDR;
reg                 last_HWRITE;
reg [1:0]           last_HTRANS;
reg [2:0]           last_HSIZE;

//
reg         qspi_ready;
reg         qspi_started;

// HREADYOUT completion qualifier (back-to-back-NONSEQ stale-serve fix).
//
// A transfer may ONLY complete (HREADYOUT=1) on the data from its OWN fetch.
//
// THE BUG (silicon-confirmed XiP branch livelock): the previous form
//   ((IDLE && last_HTRANS[1]==0) || ERR2) ? 1 : qspi_ready
// fell through to the *registered* qspi_ready in EVERY state that is not
// "IDLE with no pending transfer" or ERR2 — including the cycle the FSM has
// already dropped back to IDLE after a completed read while qspi_ready is
// still asserted (qspi_ready only clears one cycle later, in the datapath
// `else` branch). On a BACK-TO-BACK NONSEQ (a taken branch / loop presents a
// new address the same cycle the prior transfer completes) that left-over
// qspi_ready completed the NEW transfer in IDLE with the PREVIOUS transfer's
// HRDATA -> stale/wrong data, M0+ livelock. Straight-line code is immune (its
// fetches never present a new NONSEQ the same cycle a transfer completes).
//
// FIX: qspi_ready may drive HREADYOUT ONLY while the FSM is in WAIT_READ — the
// state that actually owns and fetched this transfer's data. Any newly
// address-phase-accepted transfer is therefore forced through a fresh
// WAIT_READ (the FSM clears qspi_ready/qspi_started in the `else` branch on
// leaving WAIT_READ, then re-fetches), so the branch-target fetch always
// returns its own data. Cases:
//   - WAIT_READ: complete on qspi_ready (this transfer's own fetch).
//   - ERR2:      complete the 2nd cycle of the AHB-Lite error response.
//   - IDLE:      ready=1 only when there is no pending transfer
//                (last_HTRANS[1]==0, i.e. IDLE/BUSY) — zero wait state;
//                a pending NONSEQ reads 0 (not-ready) so it cannot reuse the
//                stale qspi_ready and must enter WAIT_READ to be fetched.
//   - ERR1:      hold HREADYOUT low (error phase 1).
// The WAIT_READ data-capture path (when/how HRDATA is latched and qspi_ready
// asserted) is UNCHANGED, so normal single / sequential line-fill data and
// timing are bit-for-bit preserved.
assign HREADYOUT = (current_state==WAIT_READ) ? qspi_ready                :
                   (current_state==ERR2)      ? 1'b1                      :
                   (current_state==IDLE)      ? (last_HTRANS[1]==1'b0)    :
                                                 1'b0; // ERR1
assign HRESP = (current_state == ERR1 || current_state == ERR2) ? 1'b1 : 1'b0;

always @(posedge HCLK or negedge HRESETn) begin
    if(~HRESETn) begin
        last_HSEL   <= 1'b0;
        last_HADDR  <= {ADDR_W{1'b0}};
        last_HWRITE <= 1'b0;
        last_HTRANS <= 2'b00;
        last_HSIZE  <= 3'h0;

        current_state <= IDLE;
    end else begin
        last_HSEL   <= HSELx;
        last_HADDR  <= HADDR;
        last_HWRITE <= HWRITE;
        last_HTRANS <= HTRANS;
        last_HSIZE  <= HSIZE;

        current_state <= next_state;
    end
end

always_comb begin
    next_state = IDLE;

    case(current_state)
        IDLE:           if(HTRANS[1]==1'b0)
                            next_state = IDLE;
                        else if(HSELx) begin
                            if(~XIP_ACTIVE)
                                next_state = ERR1;
                            else if(HSELx & HWRITE)
                                next_state = ERR1;
                            else
                                next_state = WAIT_READ;
                        end
                        else
                            next_state = IDLE;
        ERR1:           next_state = ERR2;
        ERR2:           next_state = IDLE;
        WAIT_READ:      if(qspi_ready)
                            next_state = IDLE;
                        else if(watchdog_expired)
                            next_state = ERR1;
                        else
                            next_state = WAIT_READ;
        default:        next_state = IDLE;
    endcase
end

always @(posedge HCLK or negedge HRESETn) begin
    if(~HRESETn) begin
        watchdog_cnt <= {WATCHDOG_WIDTH{1'b0}};
    end else begin
        if(current_state == WAIT_READ && !watchdog_expired)
            watchdog_cnt <= watchdog_cnt + 1'b1;
        else
            watchdog_cnt <= {WATCHDOG_WIDTH{1'b0}};
    end
end

// Soft-reset pulse generator.
//
// When the watchdog expires, the FSM transitions WAIT_READ -> ERR1 ->
// ERR2 -> IDLE. Meanwhile the downstream QSPI
// controller may still be stuck in DATA_I / DATA_O / DUMMY waiting for
// counter-driven exit conditions that will never fire. Hold SOFT_RESET
// high for a few HCLK cycles once watchdog fires — long enough for the
// 2-FF synchroniser inside the controller to propagate the reset even
// at the slowest practical QSPI_SCLK_i (CLK_DIV=31 -> QSPI_SCLK_i =
// HCLK/62, so 128 HCLK gives us ~2 QSPI_SCLK_i cycles of margin).
localparam SOFT_RESET_HCLK_CYCLES = 8'd128;
reg [7:0] soft_reset_cnt;
always @(posedge HCLK or negedge HRESETn) begin
    if(~HRESETn) begin
        soft_reset_cnt <= 8'd0;
        SOFT_RESET     <= 1'b0;
    end else begin
        if(watchdog_expired) begin
            // Watchdog just fired this cycle — start the soft-reset pulse
            soft_reset_cnt <= SOFT_RESET_HCLK_CYCLES;
            SOFT_RESET     <= 1'b1;
        end else if (soft_reset_cnt != 8'd0) begin
            soft_reset_cnt <= soft_reset_cnt - 8'd1;
            SOFT_RESET     <= 1'b1;
        end else begin
            SOFT_RESET     <= 1'b0;
        end
    end
end

always @(posedge HCLK or negedge HRESETn) begin
    if(~HRESETn) begin
        AHB_QSPI_ENABLE <= 1'b0;
        qspi_ready <= 1'b0;
        qspi_started <= 1'b0;
        AHB_QSPI_ADDR <= 22'd0;
    end else begin
        if(current_state == WAIT_READ) begin
            if(ahb_qspi_busy_sync!=1'b1) begin
                if(qspi_started==1'b0) begin
                    AHB_QSPI_ENABLE <= 1'b1;
                end
            end
            if(ahb_qspi_enable_ack_sync) begin
                AHB_QSPI_ENABLE <= 1'b0;
                qspi_started <= 1'b1;
            end
            if(qspi_started==1'b1) begin
                if(ahb_qspi_busy_sync==1'b0) begin
                    HRDATA <= AHB_QSPI_RDATA_i;
                    qspi_ready <= 1'b1;
                end
            end
        end else begin
            AHB_QSPI_ENABLE <= 1'b0;
            qspi_started <= 1'b0;
            qspi_ready <=1'b0;
            AHB_QSPI_ADDR <= {HADDR[ADDR_W-1:4],4'b0000};
        end
    end

end

endmodule
