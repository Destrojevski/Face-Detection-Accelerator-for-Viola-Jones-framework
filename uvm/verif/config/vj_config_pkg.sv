`ifndef VJ_CONFIG_PKG_SV
`define VJ_CONFIG_PKG_SV


// vj_config_pkg.sv
//
// Prvi paket u redoslijedu kompajliranja. Sve ostale komponente ga uvoze jer
// sadrzi konstante dizajna i konfiguracioni objekat.


package vj_config_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import vj_defs_pkg::*;

  `include "vj_image_case.sv"
  `include "vj_frame_case.sv"
  `include "vj_config.sv"

endpackage : vj_config_pkg

`endif
