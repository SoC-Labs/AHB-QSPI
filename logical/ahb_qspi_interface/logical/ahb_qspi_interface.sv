
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
    output wire [DATA_W-1:0]    HRDATA,
    input  wire                 HREADY,
    output wire                 HREADYOUT,
    output wire                 HRESP
);

assign HREADYOUT = 1'b0;
assign HRESP = 1'b0;
// AHB FSM
enum {IDLE, WAIT_READ, WAIT_WRITE, WRITE, READ} current_state, next_state;

// AHB lite last regs
reg         last_HSEL;
reg [31:0]  last_HADDR;
reg         last_HWRITE;
reg [1:0]   last_HTRANS;

// 
reg         qspi_ready;

always @(posedge HCLK or negedge HRESETn) begin 
    if(~HRESETn) begin 
        last_HSEL   <= 1'b0;
        last_HADDR  <= 32'd0;
        last_HWRITE <= 1'b0;
        last_HTRANS <= 2'b00;

        current_state <= IDLE;
        qspi_ready <= 1'b0;
    end else begin 
        last_HSEL   <= HSELx;
        last_HADDR  <= HADDR;
        last_HWRITE <= HWRITE;
        last_HTRANS <= HTRANS;

        current_state <= next_state;
    end
end

always @(*) begin
    next_state = IDLE;
    case(current_state)
        IDLE:           if(HSELx & HWRITE & ~qspi_ready)
                            next_state = WAIT_WRITE;
                        else if(HSELx & ~qspi_ready)
                            next_state = WAIT_READ;
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
    endcase
end

endmodule 