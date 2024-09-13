`timescale 1ns/1ps 

module ahb_qspi_cocotb(
    input  wire                 HCLK,
    input  wire                 HRESETn,

    // AHB Signals
    input  wire [32-1:0]    cocotb_HADDR,
    input  wire [1:0]       cocotb_HTRANS,
    input  wire             cocotb_HWRITE,
    input  wire [2:0]       cocotb_HSIZE,
    input  wire [2:0]       cocotb_HBURST,
    input  wire [3:0]       cocotb_HPROT,
    input  wire [32-1:0]    cocotb_HWDATA,
    input  wire             cocotb_HSELx,
    output wire [32-1:0]    cocotb_HRDATA,
    input  wire             cocotb_HREADY,
    output wire             cocotb_HREADYOUT,
    output wire             cocotb_HRESP
);


top_ahb_qspi u_top_ahb_qspi(
    .HCLK(HCLK),
    .HRESETn(HRESETn),

    .HADDR(cocotb_HADDR),
    .HTRANS(cocotb_HTRANS),
    .HWRITE(cocotb_HWRITE),
    .HSIZE(cocotb_HSIZE),
    .HBURST(cocotb_HBURST),
    .HPROT(cocotb_HPROT),
    .HWDATA(cocotb_HWDATA),
    .HSELx(cocotb_HSELx),
    .HRDATA(cocotb_HRDATA),
    .HREADY(cocotb_HREADY),
    .HREADYOUT(cocotb_HREADYOUT),
    .HRESP(cocotb_HRESP),

    .QSPI_SCLK(),
    .QSPI_nCS(),
    .QSPI_IO_o(),
    .QSPI_IO_i(),
    .QSPI_IO_e()
);




endmodule 