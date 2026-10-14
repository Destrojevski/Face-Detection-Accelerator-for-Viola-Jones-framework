`ifndef VJ_TESTS_SV
`define VJ_TESTS_SV

// vj_tests.sv
//
// Testovi su poredani od najjednostavnijeg prema najslozenijem. Svaki sljedeci
// pretpostavlja da je prethodni prosao.
//   test_reset       reset vrijednosti registara
//   test_regs        registarski fajl i varijacije AXI handshake-a
//   test_ctrl        START impuls, DONE sticky, irq, soft reset
//   test_mode_a      mod A na slucaju 4 (jedan prihvacen prozor)
//   test_mode_b      mod B na slucaju 4, provjera hit buffera
//   test_sweep_edge  degenerisani sweep-ovi i uzastopni sweep-ovi
//   test_full        svi slucajevi iz fajla vektora, oba rezima
//   test_random      nasumicni stimulus za punjenje pokrivenosti
// Sve konkretne klase samo biraju virtuelnu sekvencu - bazna klasa radi svu
// izgradnju okruzenja, pa dodavanje novog testa znaci desetak linija koda bez
// ikakvih promjena u ostatku okruzenja.



class vj_test_base extends uvm_test;

  `uvm_component_utils(vj_test_base)

  vj_env    env;
  vj_config cfg;

  // Konkretni testovi postavljaju ovo u build_phase prije super.build_phase
  bit load_vectors = 1'b1;

  function new(string name = "vj_test_base", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cfg = vj_config::type_id::create("cfg");
    cfg.get_cmdline_overrides();
    configure();

    if (load_vectors) cfg.load_golden_vectors();

    uvm_config_db#(vj_config)::set(this, "*", "vj_config", cfg);

    env = vj_env::type_id::create("env", this);
  endfunction

  // Tacka prosirenja za konkretne testove
  virtual function void configure();
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction


  // Pomocna metoda: pokretanje virtuelne sekvence uz podizanje objection-a.
  task automatic run_vseq(vj_vseq_base vseq, uvm_phase phase);
    phase.raise_objection(this, get_type_name());
    vseq.cfg = cfg;
    vseq.start(env.vseqr);
    // Kratka pauza da posljednje transakcije stignu do scoreboard-a
    #1us;
    phase.drop_objection(this, get_type_name());
  endtask

  function void report_phase(uvm_phase phase);
    uvm_report_server svr;
    int n_err, n_fatal, n_warn;

    super.report_phase(phase);

    svr     = uvm_report_server::get_server();
    n_err   = svr.get_severity_count(UVM_ERROR);
    n_fatal = svr.get_severity_count(UVM_FATAL);
    n_warn  = svr.get_severity_count(UVM_WARNING);

    `uvm_info(get_type_name(), "===============================================", UVM_NONE)
    `uvm_info(get_type_name(), $sformatf("TEST %s", get_type_name()), UVM_NONE)
    `uvm_info(get_type_name(), $sformatf("UVM_FATAL   : %0d", n_fatal), UVM_NONE)
    `uvm_info(get_type_name(), $sformatf("UVM_ERROR   : %0d", n_err), UVM_NONE)
    `uvm_info(get_type_name(), $sformatf("UVM_WARNING : %0d", n_warn), UVM_NONE)
    if (n_err == 0 && n_fatal == 0) `uvm_info(get_type_name(), "STATUS: PASS", UVM_NONE)
    else `uvm_info(get_type_name(), "STATUS: FAIL", UVM_NONE)
    `uvm_info(get_type_name(), "===============================================", UVM_NONE)
  endfunction

endclass : vj_test_base


// Reset vrijednosti registara. Ne trebaju mu zlatni vektori.
class vj_test_reset extends vj_test_base;

  `uvm_component_utils(vj_test_reset)

  function new(string name = "vj_test_reset", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void configure();
    load_vectors      = 1'b0;
    cfg.check_results = 1'b0;
  endfunction

  task run_phase(uvm_phase phase);
    vj_vseq_reset vseq;
    vseq = vj_vseq_reset::type_id::create("vseq");
    run_vseq(vseq, phase);
  endtask

endclass : vj_test_reset


// Registarski fajl i handshake.
class vj_test_regs extends vj_test_base;

  `uvm_component_utils(vj_test_regs)

  function new(string name = "vj_test_regs", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void configure();
    load_vectors      = 1'b0;
    cfg.check_results = 1'b0;
  endfunction

  task run_phase(uvm_phase phase);
    vj_vseq_regs vseq;
    vseq = vj_vseq_regs::type_id::create("vseq");
    run_vseq(vseq, phase);
  endtask

endclass : vj_test_regs


// Semantika kontrolnih bitova. Row banke sadrze samo markere, pa se rezultati
// ne provjeravaju - provjerava se ponasanje kontrolne logike.
class vj_test_ctrl extends vj_test_base;

  `uvm_component_utils(vj_test_ctrl)

  function new(string name = "vj_test_ctrl", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void configure();
    load_vectors      = 1'b0;
    cfg.check_results = 1'b0;
  endfunction

  task run_phase(uvm_phase phase);
    vj_vseq_ctrl vseq;
    vseq = vj_vseq_ctrl::type_id::create("vseq");
    run_vseq(vseq, phase);
  endtask

endclass : vj_test_ctrl


// Mod A na slucaju 4. Taj slucaj ima tacno jedan prihvacen prozor, pa test
// pokriva i prihvatanje i odbijanje na raznim fazama kaskade.
class vj_test_mode_a extends vj_test_base;

  `uvm_component_utils(vj_test_mode_a)

  int case_idx = 4;

  function new(string name = "vj_test_mode_a", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    vj_vseq_mode_a vseq;
    vseq = vj_vseq_mode_a::type_id::create("vseq");
    vseq.case_idx = case_idx;
    run_vseq(vseq, phase);
  endtask

endclass : vj_test_mode_a


// Mod B na slucaju 4: sweep pa citanje hit buffera.
class vj_test_mode_b extends vj_test_base;

  `uvm_component_utils(vj_test_mode_b)

  int case_idx = 4;

  function new(string name = "vj_test_mode_b", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    vj_vseq_mode_b vseq;
    vseq = vj_vseq_mode_b::type_id::create("vseq");
    vseq.case_idx = case_idx;
    run_vseq(vseq, phase);
  endtask

endclass : vj_test_mode_b

// Granicni sweep-ovi.
class vj_test_sweep_edge extends vj_test_base;

  `uvm_component_utils(vj_test_sweep_edge)

  function new(string name = "vj_test_sweep_edge", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    vj_vseq_sweep_edge vseq;
    vseq = vj_vseq_sweep_edge::type_id::create("vseq");
    run_vseq(vseq, phase);
  endtask

endclass : vj_test_sweep_edge

// Puna kampanja: svi slucajevi, oba rezima. Ovo je glavni test.
class vj_test_full extends vj_test_base;

  `uvm_component_utils(vj_test_full)

  function new(string name = "vj_test_full", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    vj_vseq_full vseq;
    vseq = vj_vseq_full::type_id::create("vseq");
    run_vseq(vseq, phase);
  endtask

endclass : vj_test_full


// Nasumicni stimulus. Pokrece se sa razlicitim seedovima u regresiji kako bi
// se popunila pokrivenost koju direktni testovi ne dostizu.

class vj_test_random extends vj_test_base;

  `uvm_component_utils(vj_test_random)

  function new(string name = "vj_test_random", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    vj_vseq_random vseq;
    vseq = vj_vseq_random::type_id::create("vseq");
    if (!vseq.randomize())
      `uvm_error(get_type_name(), "Randomizacija virtuelne sekvence nije uspjela")
    run_vseq(vseq, phase);
  endtask

endclass : vj_test_random


// Rotacija row banaka. Popunjava rupu u pokrivenosti - svi ostali testovi rade
// sa ROW_BASE = 0, pa mehanizam rotacije inace ostaje neverifikovan.
class vj_test_rotation extends vj_test_base;

  `uvm_component_utils(vj_test_rotation)

  int case_idx = 4;

  function new(string name = "vj_test_rotation", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    vj_vseq_rotation vseq;
    vseq = vj_vseq_rotation::type_id::create("vseq");
    vseq.case_idx = case_idx;
    run_vseq(vseq, phase);
  endtask

endclass : vj_test_rotation


// Obrada cijele slike u streaming rezimu.
// NIJE dio podrazumijevane regresije - traje oko deset puta duze od
// vj_test_full. Verifikuje inkrementalni put koji nijedan drugi test ne
// dodiruje: izmedju dva sweep-a mijenja se samo jedan od 25 integralnih redova,
// a ROW_BASE se pomjera za jedan.
// Zahtijeva tb_frame.txt.
// Broj y-pozicija se moze ograniciti plusargom radi kraceg pokretanja:
// -testplusarg VJ_MAX_Y=10
class vj_test_frame extends vj_test_base;

  `uvm_component_utils(vj_test_frame)

  int max_y = 0;  // 0 = sve y-pozicije iz fajla

  function new(string name = "vj_test_frame", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void configure();
    // Frame test ne koristi tb_vectors.txt
    load_vectors = 1'b0;
  endfunction

  function void build_phase(uvm_phase phase);
    int n;
    super.build_phase(phase);
    cfg.load_frame_vectors();
    if ($value$plusargs("VJ_MAX_Y=%d", n)) begin
      max_y = n;
      `uvm_info(get_type_name(), $sformatf("Ograniceno na %0d y-pozicija", max_y), UVM_LOW)
    end
  endfunction

  task run_phase(uvm_phase phase);
    vj_vseq_frame vseq;
    vseq = vj_vseq_frame::type_id::create("vseq");
    vseq.max_y = max_y;
    run_vseq(vseq, phase);
  endtask

endclass : vj_test_frame


// Probing hazardnih hipoteza
// Ovi testovi NISU dio regularne kampanje. Svaki od njih namjerno gadja jedno
// nedokumentovano ili nezasticeno stanje dizajna i sluzi da hipotezu potvrdi
// ili obori. Neki od njih mogu prekinuti simulaciju - zato je svaki zaseban
// test, da ne obori ostatak kampanje.


// H1: ROW_BASE = 25 ili 26. Ocekuje se tiho odstupanje od zlatnih vektora
// (rot_bank vraca indeks banke kvadrirane integralne slike), bez pada simulacije.
class vj_test_h1_rotbase_25 extends vj_test_base;

  `uvm_component_utils(vj_test_h1_rotbase_25)

  function new(string name = "vj_test_h1_rotbase_25", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    vj_vseq_rotbase_edge vseq;
    vseq = vj_vseq_rotbase_edge::type_id::create("vseq");
    vseq.row_base = 25;
    run_vseq(vseq, phase);
  endtask

endclass : vj_test_h1_rotbase_25

// H1: ROW_BASE = 31. Ocekuje se pristup izvan opsega niza dout_a (0 to 26) i
// prekid simulacije. Prekid je potvrda hipoteze, a ne kvar okruzenja.
class vj_test_h1_rotbase_31 extends vj_test_base;

  `uvm_component_utils(vj_test_h1_rotbase_31)

  function new(string name = "vj_test_h1_rotbase_31", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    vj_vseq_rotbase_edge vseq;
    vseq = vj_vseq_rotbase_edge::type_id::create("vseq");
    vseq.row_base = 31;
    run_vseq(vseq, phase);
  endtask

endclass : vj_test_h1_rotbase_31


// H2: X_STEP = 0.
class vj_test_h2_step_zero extends vj_test_base;

  `uvm_component_utils(vj_test_h2_step_zero)

  function new(string name = "vj_test_h2_step_zero", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    vj_vseq_step_zero vseq;
    vseq = vj_vseq_step_zero::type_id::create("vseq");
    run_vseq(vseq, phase);
  endtask

endclass : vj_test_h2_step_zero

// H3: prekoracenje 9-bitnog sabiranja x_reg + x_step.
class vj_test_h3_sweep_wrap extends vj_test_base;

  `uvm_component_utils(vj_test_h3_sweep_wrap)

  function new(string name = "vj_test_h3_sweep_wrap", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void configure();
    load_vectors      = 1'b0;
    cfg.check_results = 1'b0;
  endfunction

  task run_phase(uvm_phase phase);
    vj_vseq_sweep_wrap vseq;
    vseq = vj_vseq_sweep_wrap::type_id::create("vseq");
    run_vseq(vseq, phase);
  endtask

endclass : vj_test_h3_sweep_wrap


// H4: START upisan dok je jezgro zauzeto.
class vj_test_h4_start_busy extends vj_test_base;

  `uvm_component_utils(vj_test_h4_start_busy)

  function new(string name = "vj_test_h4_start_busy", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    vj_vseq_start_busy vseq;
    vseq = vj_vseq_start_busy::type_id::create("vseq");
    run_vseq(vseq, phase);
  endtask

endclass : vj_test_h4_start_busy

`endif
