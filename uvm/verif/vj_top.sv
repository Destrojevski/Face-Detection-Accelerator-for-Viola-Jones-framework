`ifndef VJ_TOP_SV
`define VJ_TOP_SV

`timescale 1ns / 1ps


// vj_top.sv
//
// Top modul simulacije. Instancira DUT i virtuelni interfejs, generise takt i
// pokrece UVM test.
//
// Dva detalja koja dizajn zahtijeva:
//
//  1. bram_clk_a i s00_axi_aclk moraju biti isti takt. Row banke su taktovane
//     AXI taktom, a bram_clk_a je u dizajnu namjerno neiskoriscen. Ovdje se oba
//     porta vode istim signalom, kao i u block designu gdje su oba na FCLK_CLK0.
//
//  2. Generik ROM_INIT_FILE se namjerno ne prepisuje - podrazumijevana
//     vrijednost "classifier_rom.mem" je tacno ono sto nam treba, pa se
//     izbjegava prenos string generika kroz mjesovitu jezicku granicu.
//     Fajl mora postojati u radnom direktorijumu simulacije.


module vj_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import vj_test_pkg::*;

  // 100 MHz, kao u originalnom VHDL testbenchu
  localparam time TCLK = 10ns;

  logic clk = 1'b0;
  always #(TCLK / 2) clk = ~clk;


  // Virtuelni interfejs
  vj_if vj_vif (.clk(clk));


  // DUT
  vj_cascade_v1_0 DUT (
      .irq(vj_vif.irq),

      // BRAM port A - isti takt kao AXI
      .bram_clk_a   (clk),
      .bram_en_a    (vj_vif.bram_en),
      .bram_we_a    (vj_vif.bram_we),
      .bram_addr_a  (vj_vif.bram_addr),
      .bram_wrdata_a(vj_vif.bram_wrdata),
      .bram_rddata_a(vj_vif.bram_rddata),

      // AXI4-Lite slave
      .s00_axi_aclk   (clk),
      .s00_axi_aresetn(vj_vif.aresetn),
      .s00_axi_awaddr (vj_vif.awaddr),
      .s00_axi_awprot (vj_vif.awprot),
      .s00_axi_awvalid(vj_vif.awvalid),
      .s00_axi_awready(vj_vif.awready),
      .s00_axi_wdata  (vj_vif.wdata),
      .s00_axi_wstrb  (vj_vif.wstrb),
      .s00_axi_wvalid (vj_vif.wvalid),
      .s00_axi_wready (vj_vif.wready),
      .s00_axi_bresp  (vj_vif.bresp),
      .s00_axi_bvalid (vj_vif.bvalid),
      .s00_axi_bready (vj_vif.bready),
      .s00_axi_araddr (vj_vif.araddr),
      .s00_axi_arprot (vj_vif.arprot),
      .s00_axi_arvalid(vj_vif.arvalid),
      .s00_axi_arready(vj_vif.arready),
      .s00_axi_rdata  (vj_vif.rdata),
      .s00_axi_rresp  (vj_vif.rresp),
      .s00_axi_rvalid (vj_vif.rvalid),
      .s00_axi_rready (vj_vif.rready)
  );


  // Pokretanje testa

  initial begin
    uvm_config_db#(virtual vj_if)::set(null, "*", "vj_if", vj_vif);
    run_test();
  end


  // Zastita od beskonacne simulacije. Puni test sa svih pet slucajeva staje
  // u nekoliko milisekundi simulacijskog vremena, pa je ova granica postavljena
  // sa velikom rezervom.
  initial begin
    #500ms;
    `uvm_fatal("VJ_TOP", "Simulacija je prekoracila vremensku granicu od 500 ms")
  end

endmodule : vj_top

`endif
