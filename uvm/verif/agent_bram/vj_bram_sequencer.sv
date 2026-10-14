`ifndef VJ_BRAM_SEQUENCER_SV
`define VJ_BRAM_SEQUENCER_SV

//
// vj_bram_sequencer.sv
//

class vj_bram_sequencer extends uvm_sequencer #(vj_bram_seq_item);

  `uvm_component_utils(vj_bram_sequencer)

  function new(string name = "vj_bram_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

endclass : vj_bram_sequencer

`endif
