`ifndef VJ_TEST_PKG_SV
`define VJ_TEST_PKG_SV


// vj_test_pkg.sv
//
// Posljednji paket u redoslijedu kompajliranja i ulazna tacka cijelog
// okruzenja - top modul uvozi samo njega.


package vj_test_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import vj_defs_pkg::*;
  import vj_config_pkg::*;
  import vj_axil_agent_pkg::*;
  import vj_bram_agent_pkg::*;
  import vj_seq_pkg::*;

  `include "vj_scoreboard.sv"
  `include "vj_env.sv"
  `include "vj_tests.sv"

endpackage : vj_test_pkg

`endif
