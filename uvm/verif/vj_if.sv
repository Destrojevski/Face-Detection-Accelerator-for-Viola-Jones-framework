`ifndef VJ_IF_SV
`define VJ_IF_SV


// vj_if.sv
//
// Virtuelni interfejs koji spaja SystemVerilog UVM okruzenje sa VHDL DUT-om.
// Dizajn ima dva magistralna interfejsa:
//   S00_AXI      AXI4-Lite slave, kontrolni i statusni registri
//   BRAM_PORTA   port kojim u sistemu upravlja AXI BRAM kontroler, sluzi za
//                prenos redova integralne slike u row banke
// plus level-high interrupt liniju irq koja prati CTRL.DONE.
// Napomena: bram_clk_a mora biti isti takt kao s00_axi_aclk - row banke su
// taktovane AXI taktom. Zbog toga interfejs ima samo jedan clk ulaz koji se u
// top modulu vodi na oba porta.


interface vj_if #(
    parameter int AXIL_AW = 6,
    parameter int AXIL_DW = 32
) (
    input logic clk
);


  // Globalni reset (aktivan na nuli)
  logic                   aresetn;


  // AXI4-Lite - write address kanal
  logic [    AXIL_AW-1:0] awaddr;
  logic [            2:0] awprot;
  logic                   awvalid;
  logic                   awready;

  // AXI4-Lite - write data kanal
  logic [    AXIL_DW-1:0] wdata;
  logic [(AXIL_DW/8)-1:0] wstrb;
  logic                   wvalid;
  logic                   wready;


  // AXI4-Lite - write response kanal
  logic [            1:0] bresp;
  logic                   bvalid;
  logic                   bready;


  // AXI4-Lite - read address kanal
  logic [    AXIL_AW-1:0] araddr;
  logic [            2:0] arprot;
  logic                   arvalid;
  logic                   arready;


  // AXI4-Lite - read data kanal
  logic [    AXIL_DW-1:0] rdata;
  logic [            1:0] rresp;
  logic                   rvalid;
  logic                   rready;


  // BRAM port A (upload redova integralne slike)
  logic                   bram_en;
  logic [            3:0] bram_we;
  logic [           31:0] bram_addr;
  logic [           31:0] bram_wrdata;
  logic [           31:0] bram_rddata;


  // Interrupt
  logic                   irq;

endinterface : vj_if

`endif
