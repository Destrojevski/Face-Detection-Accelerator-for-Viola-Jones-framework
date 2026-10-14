`ifndef VJ_AXIL_AGENT_SV
`define VJ_AXIL_AGENT_SV

//
// vj_axil_agent.sv
//
// Aktivni agent za AXI4-Lite kontrolni interfejs DUT-a. Sadrzi sekvencer,
// driver i monitor. U pasivnom rezimu se instancira samo monitor, sto
// omogucava da se isto okruzenje kasnije iskoristi za verifikaciju na nivou
// cijelog sistema gdje AXI transakcije generise procesorski model.
//

class vj_axil_agent extends uvm_agent;

  `uvm_component_utils(vj_axil_agent)

  vj_config         cfg;
  virtual vj_if     vif;

  vj_axil_sequencer seqr;
  vj_axil_driver    drv;
  vj_axil_monitor   mon;

  function new(string name = "vj_axil_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual vj_if)::get(this, "", "vj_if", vif))
      `uvm_fatal("NOVIF", {"Virtuelni interfejs mora biti postavljen za ", get_full_name(), ".vif"})
    if (!uvm_config_db#(vj_config)::get(this, "", "vj_config", cfg))
      `uvm_fatal("NOCFG", {"Config objekat mora biti postavljen za ", get_full_name(), ".cfg"})

    uvm_config_db#(virtual vj_if)::set(this, "*", "vj_if", vif);
    uvm_config_db#(vj_config)::set(this, "*", "vj_config", cfg);

    mon = vj_axil_monitor::type_id::create("mon", this);

    if (cfg.axil_is_active == UVM_ACTIVE) begin
      seqr = vj_axil_sequencer::type_id::create("seqr", this);
      drv  = vj_axil_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.axil_is_active == UVM_ACTIVE) drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction

endclass : vj_axil_agent

`endif
