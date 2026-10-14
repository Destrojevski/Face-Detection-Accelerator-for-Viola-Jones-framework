`ifndef VJ_AXIL_SEQUENCER_SV
`define VJ_AXIL_SEQUENCER_SV

//
// vj_axil_sequencer.sv
//
// Generator stimulusa za AXI4-Lite agent. Uloga sekvencera je standardna -
// prosljedjuje seq_item-e od sekvence ka driveru i vodi arbitrazu kada vise
// sekvenci gadja isti driver.
//

class vj_axil_sequencer extends uvm_sequencer #(vj_axil_seq_item);

  `uvm_component_utils(vj_axil_sequencer)

  function new(string name = "vj_axil_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

endclass : vj_axil_sequencer

`endif
