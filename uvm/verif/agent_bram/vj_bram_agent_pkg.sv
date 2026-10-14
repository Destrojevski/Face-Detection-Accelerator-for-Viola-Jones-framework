`ifndef VJ_BRAM_AGENT_PKG_SV
`define VJ_BRAM_AGENT_PKG_SV

package vj_bram_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import vj_defs_pkg::*;
  import vj_config_pkg::*;

  `include "vj_bram_seq_item.sv"
  `include "vj_bram_sequencer.sv"
  `include "vj_bram_driver.sv"
  `include "vj_bram_monitor.sv"
  `include "vj_bram_agent.sv"

endpackage : vj_bram_agent_pkg

`endif
