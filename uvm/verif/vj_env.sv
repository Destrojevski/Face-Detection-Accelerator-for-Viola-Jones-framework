`ifndef VJ_ENV_SV
`define VJ_ENV_SV


// vj_env.sv
//
// Environment povezuje dva agenta, virtuelni sekvencer i scoreboard.
//   vj_axil_agent  kontrolni interfejs DUT-a (AXI4-Lite registri)
//   vj_bram_agent  upload redova integralne slike (BRAM_PORTA)
//   vj_virtual_sequencer  drzi handle-ove na oba sekvencera
//   vj_scoreboard  prima transakcije sa oba monitora i radi sve provjere


class vj_env extends uvm_env;

  `uvm_component_utils(vj_env)

  vj_config            cfg;
  virtual vj_if        vif;

  vj_axil_agent        axil_agent;
  vj_bram_agent        bram_agent;
  vj_virtual_sequencer vseqr;
  vj_scoreboard        sb;

  function new(string name = "vj_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual vj_if)::get(this, "", "vj_if", vif))
      `uvm_fatal("NOVIF", {"Virtuelni interfejs mora biti postavljen za ", get_full_name(), ".vif"})
    if (!uvm_config_db#(vj_config)::get(this, "", "vj_config", cfg))
      `uvm_fatal("NOCFG", {"Config objekat mora biti postavljen za ", get_full_name(), ".cfg"})

    // Prosljedjivanje niz hijerarhiju
    uvm_config_db#(virtual vj_if)::set(this, "*", "vj_if", vif);
    uvm_config_db#(vj_config)::set(this, "*", "vj_config", cfg);

    axil_agent = vj_axil_agent::type_id::create("axil_agent", this);
    bram_agent = vj_bram_agent::type_id::create("bram_agent", this);
    vseqr      = vj_virtual_sequencer::type_id::create("vseqr", this);
    sb         = vj_scoreboard::type_id::create("sb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Monitori i scoreboard
    axil_agent.mon.ap.connect(sb.axil_imp);
    bram_agent.mon.ap.connect(sb.bram_imp);

    // Virtuelni sekvencer i stvarni sekvenceri
    if (cfg.axil_is_active == UVM_ACTIVE) vseqr.axil_seqr = axil_agent.seqr;
    if (cfg.bram_is_active == UVM_ACTIVE) vseqr.bram_seqr = bram_agent.seqr;
  endfunction

endclass : vj_env

`endif
