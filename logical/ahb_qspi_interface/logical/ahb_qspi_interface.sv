
module ahb_qspi_interface #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32
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
    input  wire [127:0]         AHB_QSPI_RDATA


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

// AHB lite last regs
reg                 last_HSEL;
reg [ADDR_W-1:0]    last_HADDR;
reg                 last_HWRITE;
reg [1:0]           last_HTRANS;
reg [2:0]           last_HSIZE;

//
reg         qspi_ready;
reg         qspi_started;

assign HREADYOUT = ((current_state==IDLE && last_HTRANS[1]==1'b0)||(current_state==ERR)) ? 1'b1: qspi_ready; //(current_state==IDLE)? 1'b1 : qspi_ready;
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
                        else
                            next_state = WAIT_READ;
        default:        next_state = IDLE;
    endcase
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
