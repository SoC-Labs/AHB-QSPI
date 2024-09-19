`timescale 1ns/1ps 

module ahb_qspi_cocotb(
    input  wire                 HCLK,
    input  wire                 HRESETn,

    // AHB Signals
    input  wire [32-1:0]    config_HADDR,
    input  wire [1:0]       config_HTRANS,
    input  wire             config_HWRITE,
    input  wire [2:0]       config_HSIZE,
    input  wire [2:0]       config_HBURST,
    input  wire [3:0]       config_HPROT,
    input  wire [32-1:0]    config_HWDATA,
    input  wire             config_HSEL,
    output wire [32-1:0]    config_HRDATA,
    input  wire             config_HREADY_IN,
    output wire             config_HREADY,
    output wire             config_HRESP,

    input  wire [32-1:0]    data_HADDR,
    input  wire [1:0]       data_HTRANS,
    input  wire             data_HWRITE,
    input  wire [2:0]       data_HSIZE,
    input  wire [2:0]       data_HBURST,
    input  wire [3:0]       data_HPROT,
    input  wire [32-1:0]    data_HWDATA,
    input  wire             data_HSEL,
    output wire [32-1:0]    data_HRDATA,
    input  wire             data_HREADY_IN,
    output wire             data_HREADY,
    output wire             data_HRESP
);

initial
begin
   $dumpfile("ahb_qspi.vcd");
   $dumpvars;
end


wire [15:0]          PADDR;
wire [2:0]           PPROT;
wire                 PSEL;
wire                 PENABLE;
wire                 PWRITE;
wire [31:0]          PWDATA;
wire [3:0]           PSTRB;
wire [31:0]          PRDATA;
wire                 PREADY;
wire                 PSLVERR;   

cmsdk_ahb_to_apb #(
    .ADDRWIDTH(16),
    .REGISTER_RDATA(1),
    .REGISTER_WDATA(0)
) u_cmsdk_ahb_to_apb (
    .HCLK(HCLK),
    .HRESETn(HRESETn),
    .PCLKEN(1'b1),

    .HSEL(config_HSEL),
    .HADDR(config_HADDR[15:0]),
    .HTRANS(config_HTRANS),
    .HSIZE(config_HSIZE),
    .HPROT(config_HPROT),
    .HWRITE(config_HWRITE),
    .HREADY(config_HREADY_IN),
    .HWDATA(config_HWDATA),

    .HREADYOUT(config_HREADY),
    .HRDATA(config_HRDATA),
    .HRESP(config_HRESP),

    .PADDR(PADDR),
    .PENABLE(PENABLE),
    .PWRITE(PWRITE),
    .PSTRB(PSTRB),
    .PPROT(PPROT),
    .PWDATA(PWDATA),
    .PSEL(PSEL),
    .APBACTIVE(),
    .PRDATA(PRDATA),
    .PREADY(PREADY),
    .PSLVERR(PSLVERR)
);


wire QSPI_SCLK;
wire QSPI_nCS;
wire [3:0] QSPI_IO_o;
wire [3:0] QSPI_IO_i;
wire [3:0] QSPI_IO_e;
wire [3:0] QSPI_IO;
top_ahb_qspi u_top_ahb_qspi(
    .HCLK(HCLK),
    .HRESETn(HRESETn),
    .PCLK(HCLK),
    .PRESETn(HRESETn),

    .HADDR(data_HADDR),
    .HTRANS(data_HTRANS),
    .HWRITE(data_HWRITE),
    .HSIZE(data_HSIZE),
    .HBURST(data_HBURST),
    .HPROT(data_HPROT),
    .HWDATA(data_HWDATA),
    .HSELx(data_HSEL),
    .HRDATA(data_HRDATA),
    .HREADY(data_HREADY),
    .HREADYOUT(data_HREADY),
    .HRESP(data_HRESP),
    
    .PADDR(PADDR),
    .PPROT(PPROT),
    .PSEL(PSEL),
    .PENABLE(PENABLE),
    .PWRITE(PWRITE),
    .PWDATA(PWDATA),
    .PSTRB(PSTRB),
    .PRDATA(PRDATA),
    .PREADY(PREADY),
    .PSLVERR(PSLVERR), 
    .QSPI_SCLK(QSPI_SCLK),
    .QSPI_nCS(QSPI_nCS),
    .QSPI_IO_o(QSPI_IO_o),
    .QSPI_IO_i(QSPI_IO_i),
    .QSPI_IO_e(QSPI_IO_e)
);

assign QSPI_IO[0] = QSPI_IO_e[0] ? QSPI_IO_o[0] : 1'bz;
assign QSPI_IO[1] = QSPI_IO_e[1] ? QSPI_IO_o[1] : 1'bz;
assign QSPI_IO[2] = QSPI_IO_e[2] ? QSPI_IO_o[2] : 1'bz;
assign QSPI_IO[3] = QSPI_IO_e[3] ? QSPI_IO_o[3] : 1'bz;

assign QSPI_IO_i[0] = QSPI_IO[0];
assign QSPI_IO_i[1] = QSPI_IO[1];
assign QSPI_IO_i[2] = QSPI_IO[2];
assign QSPI_IO_i[3] = QSPI_IO[3];

sst26wf040b u_sst26wfxxxb(
    .SCK(QSPI_SCLK),
    .SIO(QSPI_IO),
    .CEb(QSPI_nCS)
);
	//defparam u_sst26wfxxxb.IO.Ksize = 512;  //Size of memory in Kilo bytes
	//defparam u_sst26wfxxxb.I0.Msize = 0;				// Size of memory in Mega bites. I.E. 8-bit field size, use S080=1, S016=2, S032=4
	//defparam u_sst26wfxxxb.I0.ADDR_MSB=18;			// most significant address bit, 32Mb=21,16Mb=20, 8Mb=19, 4Mb=18;
	//defparam u_sst26wfxxxb.I0.Memory_Capacity = 8'h54;		// ID read memory size 32M=52,16M=51,8M=58, JEDEC read value
	//// change below values if you need non-default values on POR
	//defparam u_sst26wfxxxb.I0.WLLD_value = 24'h00_0000;	// init WLLD protection register non-volitale, default to all 0's
	//defparam u_sst26wfxxxb.I0.INIT_WPEN = 1'b0;			// value of WPEN, configuration register bit 7 default on POR
	//defparam u_sst26wfxxxb.I0.SECURITY_LOCKOUT_VALUE=1'b0;	// Value of SEC, status register bit 5 on POR

endmodule 