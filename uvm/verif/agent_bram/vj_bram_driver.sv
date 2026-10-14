`ifndef VJ_BRAM_DRIVER_SV
`define VJ_BRAM_DRIVER_SV

//
// vj_bram_driver.sv
//
// Upravlja portom BRAM_PORTA tacno onako kako to radi AXI BRAM kontroler u sistemu:
// jedan takt sa en=1 i we=1111 na byte adresi, pa jedan takt praznog hoda.
//
// Vazno ogranicenje dizajna: port A svake banke je dijeljen izmedju ove
// upisne putanje i col0 citanja koje radi jezgro, uz pretpostavku da se ta
// dva nikada ne preklapaju. Zbog toga virtuelna sekvenca nikada ne pokrece
// upis redova dok je jezgro zauzeto - redovi se uploaduju iskljucivo dok je
// jezgro u idle stanju.
//

class vj_bram_driver extends uvm_driver #(vj_bram_seq_item);

  `uvm_component_utils(vj_bram_driver)

  virtual vj_if vif;
  vj_config     cfg;

  function new(string name = "vj_bram_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual vj_if)::get(this, "", "vj_if", vif))
      `uvm_fatal("NOVIF", {"Virtuelni interfejs mora biti postavljen za ", get_full_name(), ".vif"})
    if (!uvm_config_db#(vj_config)::get(this, "", "vj_config", cfg))
      `uvm_fatal("NOCFG", {"Config objekat mora biti postavljen za ", get_full_name(), ".cfg"})
  endfunction

  task run_phase(uvm_phase phase);
    vj_bram_seq_item item;

    vif.bram_en     <= 1'b0;
    vif.bram_we     <= 4'h0;
    vif.bram_addr   <= '0;
    vif.bram_wrdata <= '0;

    forever begin
      seq_item_port.get_next_item(item);

      item.byte_addr = vj_bram_byte_addr(item.bank, item.col);

      @(posedge vif.clk);
      vif.bram_en     <= item.en;
      vif.bram_we     <= item.we;
      vif.bram_addr   <= item.byte_addr;
      vif.bram_wrdata <= item.data;

      @(posedge vif.clk);
      vif.bram_en <= 1'b0;
      vif.bram_we <= 4'h0;

      `uvm_info("BRAM_DRV", item.convert2string(), UVM_FULL)

      seq_item_port.item_done();
    end
  endtask

endclass : vj_bram_driver

`endif
