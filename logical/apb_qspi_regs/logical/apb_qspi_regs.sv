
module apb_qspi_regs(
    // APB Signals
    input  wire                 PCLK,
    input  wire                 PRESETn,
    input  wire [11:2]          PADDR,
    input  wire [2:0]           PPROT,
    input  wire                 PSEL,
    input  wire                 PENABLE,
    input  wire                 PWRITE,
    input  wire [31:0]          PWDATA,
    input  wire [3:0]           PSTRB,
    output reg [31:0]           PRDATA,
    output wire                 PREADY,
    output wire                 PSLVERR
);   
// Registers
reg [31:0] reg0;
reg [31:0] reg1;


always @(posedge PCLK or negedge PRESETn) begin
    if(~PRESETn) begin
        reg0 = 32'd0;
        reg1 = 32'd0;
    end else begin
        if(PSEL & PENABLE & PWRITE) begin
            case(PADDR)
                10'h000: reg0 = PWDATA;
                10'h001: reg1 = PWDATA;
            endcase
        end 
    end
end

always @(PCLK, PADDR) begin
    if(PCLK) begin 
        case(PADDR) 
            10'h000: PRDATA = reg0;
            10'h001: PRDATA = reg1;
        endcase
    end
end

assign PREADY =  1'b1; //(PSEL & PENABLE & PWRITE) | (PSEL & ~PWRITE);
assign PSLVERR = 1'b0;

endmodule