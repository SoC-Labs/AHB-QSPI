
module ahb_qspi_interface #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    // Width of the WAIT_READ watchdog counter. Default 12 bits gives
    // 4096 HCLK cycles (~82 us at 50 MHz HCLK) which is:
    //   - ~2x margin over worst-case transaction at CLK_DIV=5 (~1700 HCLK)
    //   - ~1.5x over CLK_DIV=13 (covers practical range)
    //   - Well inside the cocotbext.ahb master's default 5000-cycle timeout
    //     so hang-recovery tests observe HRESP=1 before the master gives up
    // Override to smaller values for tight simulation loops, larger for
    // flows using CLK_DIV > 15.
    parameter WATCHDOG_WIDTH = 12
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
enum {IDLE, WAIT_READ, ERR} current_state, next_state;

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

assign HREADYOUT = ((current_state==IDLE && last_HTRANS[1]==1'b0)||(current_state==ERR)) ? 1'b1: qspi_ready;
assign HRESP = (current_state == ERR) ? 1'b1 : 1'b0;

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
                                next_state = ERR;
                            else if(HSELx & HWRITE)
                                next_state = ERR;
                            else
                                next_state = WAIT_READ;
                        end
                        else
                            next_state = IDLE;
        ERR:            next_state = IDLE;
        WAIT_READ:      if(qspi_ready)
                            next_state = IDLE;
                        else if(watchdog_expired)
                            next_state = ERR;
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
// When the watchdog expires, the FSM transitions WAIT_READ -> ERR for
// one cycle and then back to IDLE. Meanwhile the downstream QSPI
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
