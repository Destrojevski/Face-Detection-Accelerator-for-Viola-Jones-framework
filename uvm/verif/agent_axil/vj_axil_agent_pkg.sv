`ifndef VJ_AXIL_AGENT_PKG_SV
`define VJ_AXIL_AGENT_PKG_SV


// vj_axil_agent_pkg.sv
//
// Paket AXI4-Lite agenta. Uvozi vj_config_pkg jer sve komponente agenta
// koriste konstante registarske mape i konfiguracioni objekat.

package vj_axil_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import vj_defs_pkg::*;
  import vj_config_pkg::*;

  `include "vj_axil_seq_item.sv"
  `include "vj_axil_sequencer.sv"
  `include "vj_axil_driver.sv"
  `include "vj_axil_monitor.sv"
  `include "vj_axil_agent.sv"

endpackage : vj_axil_agent_pkg

`endif
