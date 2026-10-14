`ifndef VJ_HAZARD_SEQS_SV
`define VJ_HAZARD_SEQS_SV


// vj_hazard_seqs.sv
// Sekvence koje ciljaju konkretne hipoteze za potencijalni diplomski rad. Svaka od njih postoji da bi potvrdila ili
// oborila jednu hipotezu, pa su namjerno razdvojene u zasebne testove, neke od
// njih mogu prekinuti simulaciju, sto je samo po sebi rezultat, ali ne smije
// oboriti ostatak verifikacione kampanje.
//   vj_vseq_rotation      rotacija row banaka - invarijanta rezultata
//   vj_vseq_rotbase_edge  ROW_BASE izvan dokumentovanog opsega 0..24
//   vj_vseq_step_zero     X_STEP = 0
//   vj_vseq_sweep_wrap    prekoracenje 9-bitnog sabiranja x_reg + x_step
//   vj_vseq_start_busy    START upisan dok je jezgro zauzeto

// Rotacija row banaka.
// Ovo nije proba greske nego popunjavanje rupe u pokrivenosti: svi ostali
// testovi rade sa ROW_BASE = 0, pa mehanizam rotacije - razlog zbog kojeg bank
// array uopste postoji u ovom obliku - nije verifikovan.
// Invarijanta: ako softver logicki red r upise u fizicku banku
// (r + R) mod 25 i u ROW_BASE upise R, jezgro mora dati IDENTICNE rezultate kao
// za R = 0. Zlatni vektori se ne mijenjaju, pa nije potrebna nova referenca -
// ista referenca vazi za svaku rotaciju.
class vj_vseq_rotation extends vj_vseq_base;

  `uvm_object_utils(vj_vseq_rotation)

  int case_idx   = 4;

  // Rotacije unutar dokumentovanog opsega 0..24: nula, susjedna, sredina,
  // i gornja granica gdje je uslovno oduzimanje u rot_bank() najaktivnije.
  int shifts  [] = '{0, 1, 12, 24};

  function new(string name = "vj_vseq_rotation");
    super.new(name);
  endfunction

  task body();
    vj_image_case img;
    int i, w, r;

    `uvm_info(get_type_name(), "=== Scenario: rotacija row banaka ===", UVM_LOW)

    img = cfg.cases[case_idx-1];

    foreach (shifts[i]) begin
      r = shifts[i];

      `uvm_info(get_type_name(), $sformatf("--- ROW_BASE = %0d, slucaj %0d ---", r, case_idx),
                UVM_LOW)

      do_reset(10);
      do_load_case(case_idx, r);

      // Svaki prozor mora dati isti rezultat kao pri ROW_BASE = 0.
      // Scoreboard poredi rezultat sa istim zlatnim vektorima.
      for (w = 0; w < img.nwin; w++) do_run_mode_a(img.win_x[w], r, img.width);
    end
  endtask

endclass : vj_vseq_rotation

// ROW_BASE izvan dokumentovanog opsega.
// HIPOTEZA H1: rot_bank() rotaciju racuna jednim uslovnim oduzimanjem, sto je
// ispravno samo ako su oba operanda manja od 25. ROW_BASE je 5-bitan registar,
// pa softver moze upisati 25 do 31. Za takve vrijednosti rot_bank() moze vratiti
// indeks 25 ili 26 (tiho citanje banaka kvadrirane integralne slike umjesto
// integralne) ili indeks 27..30 (pristup izvan opsega niza dout_a koji je
// deklarisan kao 0 to 26).
// Ocekivano ponasanje pri potvrdi hipoteze:
//   ROW_BASE = 25, 26  -> rezultati odstupaju od zlatnih vektora, bez faila
//                         simulacije
//   ROW_BASE = 27..31  -> greska pristupa nizu, simulacija se prekida
// Zbog druge mogucnosti ova sekvenca ide u zaseban test.
class vj_vseq_rotbase_edge extends vj_vseq_base;

  `uvm_object_utils(vj_vseq_rotbase_edge)

  int case_idx  = 4;
  int row_base  = 26;  // postavlja test
  int n_windows = 3;  // dovoljno prozora da se hipoteza ispolji

  function new(string name = "vj_vseq_rotbase_edge");
    super.new(name);
  endfunction

  task body();
    vj_image_case img;
    int w, lim;

    `uvm_info(get_type_name(),
              $sformatf("=== Proba H1: ROW_BASE = %0d (dokumentovani opseg je 0..24) ===",
                        row_base), UVM_LOW)
    `uvm_info(get_type_name(),
              "Ako se simulacija ovdje prekine greskom pristupa nizu, hipoteza H1 je potvrdjena.",
              UVM_LOW)

    img = cfg.cases[case_idx-1];

    do_reset(10);

    // Slika se upisuje bez rotacije, a ROW_BASE se postavlja na nedozvoljenu
    // vrijednost - tacno ono sto bi uradio softver sa greskom u racunanju
    // y-biasa.
    do_load_case(case_idx, 0);

    lim = (n_windows < img.nwin) ? n_windows : img.nwin;
    for (w = 0; w < lim; w++) do_run_mode_a(img.win_x[w], row_base, img.width);

    `uvm_info(
        get_type_name(),
        "Simulacija nije prekinuta - provjeriti da li scoreboard prijavljuje odstupanje od zlatnih vektora.",
        UVM_LOW)
  endtask

endclass : vj_vseq_rotbase_edge

// X_STEP = 0.
// HIPOTEZA H2: uslov nastavka sweep-a u ST_WIN_END glasi
//     mode_sweep = '1' AND (x_reg + x_step) <= x_last
// Za x_step = 0 uslov je trajno tacan, x_reg se nikada ne mijenja, pa FSM
// beskonacno ponavlja isti prozor. DONE se ne postavlja, BUSY ostaje visok.
// Sekvenca ne poziva wait_done() nego citanjem STATUS registra provjerava da li
// je jezgro i dalje zauzeto nakon vise nego dovoljno taktova, pa se oporavlja
// soft resetom. Time probing ne blokira simulaciju bez obzira na ishod.
class vj_vseq_step_zero extends vj_vseq_base;

  `uvm_object_utils(vj_vseq_step_zero)

  int case_idx = 4;

  function new(string name = "vj_vseq_step_zero");
    super.new(name);
  endfunction

  task body();
    vj_axil_hazard_probe_seq s;
    vj_image_case img;

    `uvm_info(get_type_name(), "=== Proba H2: X_STEP = 0 ===", UVM_LOW)

    img = cfg.cases[case_idx-1];

    do_reset(10);
    do_load_case(case_idx, 0);

    // Od ovog trenutka rezultati nisu uporedivi sa zlatnim vektorima
    cfg.active_case = 0;

    s               = vj_axil_hazard_probe_seq::type_id::create("step_zero_probe");
    s.probe_name    = "X_STEP = 0";
    s.x_start       = img.win_x[0];
    s.x_last        = img.win_x[img.nwin-1];
    s.x_step        = 0;
    s.wait_cycles   = 200000;
    s.start(p_sequencer.axil_seqr);
  endtask

endclass : vj_vseq_step_zero

// Prekoracenje 9-bitnog sabiranja.
// HIPOTEZA H3: x_reg, x_step i x_last su svi unsigned(8 downto 0), pa je
// x_reg + x_step devetobitno sabiranje koje se omotava po modulu 512. Za
// x_last = 511 i x_step = 1 sweep dolazi do 511, izracuna 512 -> 0, uslov
// 0 <= 511 je tacan, i sweep krece ispocetka - beskonacna petlja.
class vj_vseq_sweep_wrap extends vj_vseq_base;

  `uvm_object_utils(vj_vseq_sweep_wrap)

  function new(string name = "vj_vseq_sweep_wrap");
    super.new(name);
  endfunction

  task body();
    vj_axil_hazard_probe_seq s;

    `uvm_info(get_type_name(), "=== Proba H3: prekoracenje x_reg + x_step ===", UVM_LOW)

    do_reset(10);
    do_markers();  // sadrzaj banaka nije bitan, bitno je ponasanje FSM-a

    s             = vj_axil_hazard_probe_seq::type_id::create("wrap_probe");
    s.probe_name  = "x_last = 511, x_step = 1";
    s.x_start     = 0;
    s.x_last      = 511;
    s.x_step      = 1;
    // 512 prozora bi u najgorem slucaju trajalo dugo, ali svaki prozor nad
    // markerima se odbacuje na fazi 0, pa je ovo sa velikom rezervom.
    s.wait_cycles = 400000;
    s.start(p_sequencer.axil_seqr);
  endtask

endclass : vj_vseq_sweep_wrap

// START dok je jezgro zauzeto.
// HIPOTEZA H4: ST_IDLE je jedino stanje koje sampluje start signal, pa je START
// upisan u toku izvrsavanja tiho odbacen. Probing provjerava da drugi START ne kvari tekuce
// izvrsavanje i da se ono uredno zavrsi.
class vj_vseq_start_busy extends vj_vseq_base;

  `uvm_object_utils(vj_vseq_start_busy)

  int case_idx = 1;  // najsira skala, najduze izvrsavanje

  function new(string name = "vj_vseq_start_busy");
    super.new(name);
  endfunction

  task body();
    vj_axil_double_start_seq s;
    vj_image_case img;

    `uvm_info(get_type_name(), "=== Proba H4: START dok je jezgro zauzeto ===", UVM_LOW)

    img = cfg.cases[case_idx-1];

    do_reset(10);
    do_load_case(case_idx, 0);

    s = vj_axil_double_start_seq::type_id::create("double_start");
    s.x_start = img.win_x[0];
    s.x_last = img.win_x[img.nwin-1];
    s.x_step = sweep_step(img);
    s.start(p_sequencer.axil_seqr);
  endtask

endclass : vj_vseq_start_busy

`endif
