
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

    output wire [7:0]           AHB_QSPI_CMD,
    output reg                  AHB_QSPI_ENABLE,
    output wire                 AHB_QSPI_READ,
    output wire                 AHB_QSPI_WRITE,
    output wire                 AHB_QSPI_ADDR_EN,
    output wire [3:0]           AHB_QSPI_DUMMY_CYCLES,
    output wire [3:0]           AHB_QSPI_N_RW_BYTES,
    output reg  [21:0]          AHB_QSPI_ADDR,
    output wire [127:0]         AHB_QSPI_WDATA,

    input  wire                 AHB_QSPI_ENABLE_ACK,
    input  wire                 AHB_QSPI_BUSY,
    input  wire [127:0]         AHB_QSPI_RDATA


);

assign HRESP = 1'b0;
assign AHB_QSPI_CMD = 8'h0B;
assign AHB_QSPI_ADDR_EN = 1'b1;
assign AHB_QSPI_DUMMY_CYCLES = 4'h4;
assign AHB_QSPI_READ=1'b1;
assign AHB_QSPI_WRITE=1'b0;
assign AHB_QSPI_WDATA = HWDATA;
assign AHB_QSPI_N_RW_BYTES = 4'hF;


wire [31:0] AHB_QSPI_RDATA_W0 = {AHB_QSPI_RDATA[71:64],AHB_QSPI_RDATA[79:72],AHB_QSPI_RDATA[87:80],AHB_QSPI_RDATA[95:88]}; //AHB_QSPI_RDATA[95:64];
wire [31:0] AHB_QSPI_RDATA_W1 = {AHB_QSPI_RDATA[39:32], AHB_QSPI_RDATA[47:40], AHB_QSPI_RDATA[55:48], AHB_QSPI_RDATA[63:56]}; //AHB_QSPI_RDATA[63:32]; //94000049
wire [31:0] AHB_QSPI_RDATA_W2 = {AHB_QSPI_RDATA[7:0], AHB_QSPI_RDATA[15:8], AHB_QSPI_RDATA[23:16], AHB_QSPI_RDATA[31:24]};
wire [31:0] AHB_QSPI_RDATA_W3 = {AHB_QSPI_RDATA[103:96],AHB_QSPI_RDATA[111:104],AHB_QSPI_RDATA[119:112],AHB_QSPI_RDATA[127:120]};//AHB_QSPI_RDATA[127:96];

wire [127:0] AHB_QSPI_RDATA_i = {AHB_QSPI_RDATA_W3,AHB_QSPI_RDATA_W0, AHB_QSPI_RDATA_W1, AHB_QSPI_RDATA_W2};

// AHB FSM
enum {IDLE, WAIT_READ, WAIT_WRITE, WRITE, READ} current_state, next_state;

// AHB lite last regs
reg                 last_HSEL;
reg [ADDR_W-1:0]    last_HADDR;
reg                 last_HWRITE;
reg [1:0]           last_HTRANS;
reg [2:0]           last_HSIZE;

//
reg         qspi_ready;
reg         qspi_started;

assign HREADYOUT = (current_state==IDLE && last_HTRANS==2'b00) ? 1'b1: qspi_ready; //(current_state==IDLE)? 1'b1 : qspi_ready;

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
        IDLE:           if(HTRANS==2'b00)
                            next_state = IDLE;
                        else if(HSELx & HWRITE & ~qspi_ready) begin
                            next_state = WAIT_WRITE;
                        end
                        else if(HSELx & ~qspi_ready) begin
                            next_state = WAIT_READ;
                        end
        WAIT_WRITE:     if(qspi_ready)
                            next_state = WRITE;
                        else
                            next_state = WAIT_WRITE;
        WAIT_READ:      if(qspi_ready)
                            next_state = READ;
                        else
                            next_state = WAIT_READ;
        READ:           next_state = IDLE;
        WRITE:          next_state = IDLE;
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
            if(AHB_QSPI_BUSY!=1'b1) begin
                if(qspi_started==1'b0) begin
                    AHB_QSPI_ENABLE <= 1'b1;
                    qspi_started <= 1'b1;
                end
            end
            if(AHB_QSPI_ENABLE_ACK)
                AHB_QSPI_ENABLE <= 1'b0;
            if(qspi_started==1'b1) begin
                if(AHB_QSPI_BUSY==1'b0) begin
                    HRDATA <= AHB_QSPI_RDATA_i;
                    qspi_ready <= 1'b1;
                end
            end
        end else begin 
            qspi_started <= 1'b0;
            qspi_ready <=1'b0;
            AHB_QSPI_ADDR <= {HADDR[ADDR_W-1:4],4'b0000};
        end
    end

end

endmodule
