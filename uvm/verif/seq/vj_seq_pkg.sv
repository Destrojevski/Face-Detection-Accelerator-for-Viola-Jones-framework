`ifndef VJ_SEQ_PKG_SV
`define VJ_SEQ_PKG_SV


// vj_seq_pkg.sv
//
// Paket sekvenci. Uvozi oba agentska paketa jer virtuelne sekvence pokrecu
// sekvence i na AXI4-Lite i na BRAM sekvenceru.


package vj_seq_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import vj_defs_pkg::*;
  import vj_config_pkg::*;
  import vj_axil_agent_pkg::*;
  import vj_bram_agent_pkg::*;

  `include "vj_axil_seqs.sv"
  `include "vj_bram_seqs.sv"
  `include "vj_virtual_sequencer.sv"
  `include "vj_virtual_seqs.sv"
  `include "vj_hazard_seqs.sv"
  `include "vj_frame_seqs.sv"

endpackage : vj_seq_pkg

`endif
