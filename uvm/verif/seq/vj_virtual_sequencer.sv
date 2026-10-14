`ifndef VJ_VIRTUAL_SEQUENCER_SV
`define VJ_VIRTUAL_SEQUENCER_SV


// vj_virtual_sequencer.sv
//
// Dizajn ima dva interfejsa cije se aktivnosti ne smiju preklapati: redovi
// integralne slike se uploaduju kroz BRAM_PORTA iskljucivo dok je jezgro u
// idle stanju, a tek zatim se preko AXI4-Lite-a pokrece obrada. Virtuelni
// sekvencer postoji upravo zbog toga - drzi handle-ove na oba sekvencera, pa
// jedna virtuelna sekvenca moze redom, a ne paralelno, voditi cijeli scenario.


class vj_virtual_sequencer extends uvm_sequencer;

  `uvm_component_utils(vj_virtual_sequencer)

  vj_axil_sequencer axil_seqr;
  vj_bram_sequencer bram_seqr;

  vj_config cfg;

  function new(string name = "vj_virtual_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(vj_config)::get(this, "", "vj_config", cfg))
      `uvm_fatal("NOCFG", {"Config objekat mora biti postavljen za ", get_full_name(), ".cfg"})
  endfunction

endclass : vj_virtual_sequencer

`endif
