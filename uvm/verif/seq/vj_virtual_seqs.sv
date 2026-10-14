`ifndef VJ_VIRTUAL_SEQS_SV
`define VJ_VIRTUAL_SEQS_SV

// vj_virtual_seqs.sv
// Virtuelne sekvence - kompletni verifikacioni scenariji. Svaka od njih vodi
// oba agenta kroz redoslijed koji dizajn zahtijeva:
//   reset  ->  upload redova kroz BRAM_PORTA  ->  konfiguracija registara
//          ->  START preko AXI4-Lite  ->  cekanje DONE  ->  citanje rezultata
// Nijedna od njih ne radi provjere - provjere su iskljucivo u scoreboard-u.
// Sekvence samo postavljaju cfg.active_case tako da scoreboard zna koji skup
// zlatnih vektora vazi za sadrzaj koji je trenutno u row bankama.

// Bazna virtuelna sekvenca
class vj_vseq_base extends uvm_sequence #(uvm_sequence_item);

  `uvm_object_utils(vj_vseq_base)
  `uvm_declare_p_sequencer(vj_virtual_sequencer)

  vj_config cfg;

  function new(string name = "vj_vseq_base");
    super.new(name);
  endfunction

  // cfg se preuzima od virtuelnog sekvencera ako ga test nije postavio.
  task pre_start();
    super.pre_start();
    if (cfg == null) cfg = p_sequencer.cfg;
    if (cfg == null) `uvm_fatal(get_type_name(), "Config objekat nije dostupan virtuelnoj sekvenci")
  endtask

  // Pomocne metode - svaka pokrece odgovarajucu sekvencu na svom sekvenceru
  task automatic do_reset(int unsigned cycles = 10);
    vj_axil_reset_seq s;
    s = vj_axil_reset_seq::type_id::create("reset_seq");
    s.reset_cycles = cycles;
    s.start(p_sequencer.axil_seqr);
  endtask

  task automatic do_load_case(int case_idx, int row_shift = 0);
    vj_bram_load_case_seq s;
    vj_image_case         img;

    if (case_idx < 1 || case_idx > cfg.cases.size())
      `uvm_fatal(get_type_name(), $sformatf("Nepostojeci indeks slucaja: %0d", case_idx))

    img             = cfg.cases[case_idx-1];

    // Row banke od ovog trenutka sadrze poznatu sliku - scoreboard od sada
    // provjerava algoritamske rezultate u odnosu na njene zlatne vektore.
    cfg.active_case = case_idx;

    s               = vj_bram_load_case_seq::type_id::create("load_case_seq");
    s.img           = img;
    s.row_shift     = row_shift;
    s.start(p_sequencer.bram_seqr);
  endtask

  task automatic do_markers();
    vj_bram_marker_seq s;
    // Sadrzaj banaka vise nije poznata slika
    cfg.active_case = 0;
    s = vj_bram_marker_seq::type_id::create("marker_seq");
    s.start(p_sequencer.bram_seqr);
  endtask

  task automatic do_run_mode_a(int unsigned x, int unsigned row_base = 0,
                               int unsigned width = MAX_IMG_WIDTH);
    vj_axil_run_seq s;
    s          = vj_axil_run_seq::type_id::create("run_a_seq");
    s.mode     = MODE_A_SINGLE;
    s.x_start  = x;
    s.x_last   = x;
    s.row_base = row_base;
    s.width    = width;
    s.start(p_sequencer.axil_seqr);
  endtask

  task automatic do_run_mode_b(int unsigned x_start, int unsigned x_last, int unsigned x_step,
                               int unsigned row_base = 0, int unsigned width = MAX_IMG_WIDTH);
    vj_axil_run_seq s;
    s          = vj_axil_run_seq::type_id::create("run_b_seq");
    s.mode     = MODE_B_SWEEP;
    s.x_start  = x_start;
    s.x_last   = x_last;
    s.x_step   = x_step;
    s.row_base = row_base;
    s.width    = width;
    s.start(p_sequencer.axil_seqr);
  endtask

  task automatic do_read_hits();
    vj_axil_hit_read_seq s;
    s = vj_axil_hit_read_seq::type_id::create("hit_read_seq");
    s.start(p_sequencer.axil_seqr);
  endtask


  // Korak sweep-a izveden iz zlatnih vektora: prozori u fajlu su ekvidistantni,
  // pa je razmak izmedju prva dva ujedno i shiftStep te skale.
  function int sweep_step(vj_image_case img);
    if (img.nwin < 2) return 1;
    return img.win_x[1] - img.win_x[0];
  endfunction

endclass : vj_vseq_base


// Reset scenario: hardverski reset, pa soft reset preko CTRL bita 0.
class vj_vseq_reset extends vj_vseq_base;

  `uvm_object_utils(vj_vseq_reset)

  function new(string name = "vj_vseq_reset");
    super.new(name);
  endfunction

  task body();
    vj_axil_post_reset_seq s;

    `uvm_info(get_type_name(), "=== Scenario: reset ===", UVM_LOW)

    cfg.active_case = 0;

    do_reset(10);

    // Poslije reseta svi RW registri moraju imati reset vrijednosti, a
    // read-only registri nule. Citanja generise sekvenca, provjeru radi
    // scoreboard nad svojim shadow modelom.
    s = vj_axil_post_reset_seq::type_id::create("post_reset_seq");
    s.start(p_sequencer.axil_seqr);

    // Isto mora vaziti i poslije drugog reseta, nakon sto su registri bili
    // popunjeni nekim vrijednostima.
    begin
      vj_axil_reg_seq r;
      r = vj_axil_reg_seq::type_id::create("reg_fill_seq");
      r.start(p_sequencer.axil_seqr);
    end
    do_reset(10);
    s = vj_axil_post_reset_seq::type_id::create("post_reset_seq2");
    s.start(p_sequencer.axil_seqr);
  endtask

endclass : vj_vseq_reset


// Registarski scenario: read-back svih registara i varijacije handshake-a.
// Row banke se ne diraju, pa scoreboard ne provjerava algoritamske rezultate.
class vj_vseq_regs extends vj_vseq_base;

  `uvm_object_utils(vj_vseq_regs)

  function new(string name = "vj_vseq_regs");
    super.new(name);
  endfunction

  task body();
    vj_axil_reg_seq       reg_s;
    vj_axil_handshake_seq hs_s;

    `uvm_info(get_type_name(), "=== Scenario: registarski fajl i handshake ===", UVM_LOW)

    cfg.active_case = 0;

    do_reset(10);

    reg_s = vj_axil_reg_seq::type_id::create("reg_seq");
    reg_s.start(p_sequencer.axil_seqr);

    hs_s = vj_axil_handshake_seq::type_id::create("handshake_seq");
    hs_s.start(p_sequencer.axil_seqr);
  endtask

endclass : vj_vseq_regs


// Semantika kontrolnih bitova: START je impuls, DONE je sticky i cisti se
// samo upisom jedinice, irq prati DONE, soft reset vraca jezgro u idle.
//
// Banke ovdje sadrze samo markere pa rezultat nije provjerljiv - provjerava se
// iskljucivo ponasanje kontrolne logike.
class vj_vseq_ctrl extends vj_vseq_base;

  `uvm_object_utils(vj_vseq_ctrl)

  function new(string name = "vj_vseq_ctrl");
    super.new(name);
  endfunction

  task body();
    vj_axil_ctrl_seq s;

    `uvm_info(get_type_name(), "=== Scenario: START impuls, DONE sticky, irq, soft reset ===",
              UVM_LOW)

    do_reset(10);

    // U banke upisujemo markere u svih 27 kolona nula - time se provjerava
    // i adresna putanja, a sadrzaj nije poznata slika pa scoreboard nece
    // provjeravati algoritamske rezultate.
    do_markers();

    s = vj_axil_ctrl_seq::type_id::create("ctrl_seq");
    s.start(p_sequencer.axil_seqr);
  endtask

endclass : vj_vseq_ctrl


// Mod A: svaki prozor iz zlatnih vektora se pokrece pojedinacno i RESULT se
// poredi sa referencom. Ovo je glavni funkcionalni test kaskade.
class vj_vseq_mode_a extends vj_vseq_base;

  `uvm_object_utils(vj_vseq_mode_a)

  int case_idx = 1;

  function new(string name = "vj_vseq_mode_a");
    super.new(name);
  endfunction

  task body();
    vj_image_case img;
    int w;

    `uvm_info(get_type_name(), $sformatf("=== Scenario: mod A, slucaj %0d ===", case_idx), UVM_LOW)

    do_reset(10);
    do_load_case(case_idx);

    img = cfg.cases[case_idx-1];

    for (w = 0; w < img.nwin; w++) do_run_mode_a(img.win_x[w], 0, img.width);

    `uvm_info(get_type_name(), $sformatf("Slucaj %0d: %0d prozora izvrseno u modu A", case_idx,
                                         img.nwin), UVM_LOW)
  endtask

endclass : vj_vseq_mode_a


// Mod B: jedan sweep preko cijelog reda, pa citanje hit buffera. Broj i sadrzaj
// pogodaka se porede sa istim zlatnim vektorima koje koristi mod A - dva
// nezavisna puta kroz isti algoritam moraju dati isti odgovor.
class vj_vseq_mode_b extends vj_vseq_base;

  `uvm_object_utils(vj_vseq_mode_b)

  int case_idx = 1;

  function new(string name = "vj_vseq_mode_b");
    super.new(name);
  endfunction

  task body();
    vj_image_case img;
    int step;

    `uvm_info(get_type_name(), $sformatf("=== Scenario: mod B, slucaj %0d ===", case_idx), UVM_LOW)

    do_reset(10);
    do_load_case(case_idx);

    img  = cfg.cases[case_idx-1];
    step = sweep_step(img);

    do_run_mode_b(img.win_x[0], img.win_x[img.nwin-1], step, 0, img.width);
    do_read_hits();
  endtask

endclass : vj_vseq_mode_b


// Degenerisani sweep-ovi: sweep od tacno jednog prozora, i korak koji preskace
// preko x_last. FSM mora u oba slucaja stati bez zaglavljivanja u petlji.
class vj_vseq_sweep_edge extends vj_vseq_base;

  `uvm_object_utils(vj_vseq_sweep_edge)

  int case_idx = 4;

  function new(string name = "vj_vseq_sweep_edge");
    super.new(name);
  endfunction

  task body();
    vj_image_case img;
    int step;

    `uvm_info(get_type_name(), "=== Scenario: granicni sweep-ovi ===", UVM_LOW)

    do_reset(10);
    do_load_case(case_idx);
    img  = cfg.cases[case_idx-1];
    step = sweep_step(img);

    // Sweep tacno jednog prozora: x_start = x_last
    do_run_mode_b(img.win_x[0], img.win_x[0], step, 0, img.width);
    do_read_hits();

    // Korak koji prebacuje preko x_last - posljednji izvrseni prozor mora
    // biti posljednje x koje zadovoljava x <= x_last.
    do_run_mode_b(img.win_x[0], img.win_x[2], 3 * step, 0, img.width);
    do_read_hits();

    // Dva identicna sweep-a zaredom moraju dati isti broj pogodaka.
    // ST_WIN_START je jedino stanje koje cisti hit buffer, pa buffer mora
    // prezivjeti prozore unutar jednog sweep-a, ali i biti ociscen na
    // pocetku sljedeceg.
    do_run_mode_b(img.win_x[0], img.win_x[img.nwin-1], step, 0, img.width);
    do_read_hits();
    do_run_mode_b(img.win_x[0], img.win_x[img.nwin-1], step, 0, img.width);
    do_read_hits();
  endtask

endclass : vj_vseq_sweep_edge


// Full scenario: svi slucajevi iz fajla vektora, svaki u oba rezima rada.
// Ovo je referentni test - pokriva i plitke i duboke prozore kaskade, i
// slucajeve sa i bez prihvacenih prozora.
class vj_vseq_full extends vj_vseq_base;

  `uvm_object_utils(vj_vseq_full)

  function new(string name = "vj_vseq_full");
    super.new(name);
  endfunction

  task body();
    vj_image_case img;
    int c, w, step;

    `uvm_info(get_type_name(), "=== Scenario: svi slucajevi, oba rezima ===", UVM_LOW)

    do_reset(10);

    for (c = 1; c <= cfg.cases.size(); c++) begin
      img  = cfg.cases[c-1];
      step = sweep_step(img);

      // Soft reset i upload novog slucaja
      do_reset(10);
      do_load_case(c);

      // Mod A: svaki prozor pojedinacno
      for (w = 0; w < img.nwin; w++) do_run_mode_a(img.win_x[w], 0, img.width);

      // Mod B: isti prozori kroz jedan sweep
      do_run_mode_b(img.win_x[0], img.win_x[img.nwin-1], step, 0, img.width);
      do_read_hits();

      `uvm_info(get_type_name(), $sformatf(
                "Slucaj %0d zavrsen (sirina %0d, %0d prozora, %0d ocekivanih pogodaka)",
                c,
                img.width,
                img.nwin,
                img.num_accepts()
                ), UVM_LOW)
    end
  endtask

endclass : vj_vseq_full


// Nasumicni scenario. Sluzi punjenju pokrivenosti koju direktni testovi ne
// dosegnu: nasumicni timing handshake-a, nasumicne adrese u row bankama i
// nasumicno izabrani slucaj sa nasumicnim rasponom sweep-a.
class vj_vseq_random extends vj_vseq_base;

  `uvm_object_utils(vj_vseq_random)

  rand int unsigned n_rounds;

  constraint c_rounds {n_rounds inside {[2 : 4]};}

  function new(string name = "vj_vseq_random");
    super.new(name);
  endfunction

  task body();
    vj_axil_random_seq axil_rand;
    vj_bram_random_seq bram_rand;
    vj_image_case      img;
    int c, step, lo_i, hi_i, r;

    `uvm_info(get_type_name(), "=== Scenario: nasumicni stimulus ===", UVM_LOW)

    do_reset(10);

    // Nasumicni upisi po cijelom adresnom opsegu row banaka
    cfg.active_case = 0;
    bram_rand = vj_bram_random_seq::type_id::create("bram_rand");
    if (!bram_rand.randomize())
      `uvm_error(get_type_name(), "Randomizacija BRAM sekvence nije uspjela")
    bram_rand.start(p_sequencer.bram_seqr);

    // Nasumicni registarski transferi
    axil_rand = vj_axil_random_seq::type_id::create("axil_rand");
    if (!axil_rand.randomize())
      `uvm_error(get_type_name(), "Randomizacija AXI sekvence nije uspjela")
    axil_rand.start(p_sequencer.axil_seqr);

    // Nekoliko rundi sa nasumicno izabranim slucajem i rasponom sweep-a.
    // Granice sweep-a se biraju iz liste zlatnih prozora kako bi svaki
    // izvrseni prozor imao referencu.
    for (r = 0; r < n_rounds; r++) begin
      c    = $urandom_range(1, cfg.cases.size());
      img  = cfg.cases[c-1];
      step = sweep_step(img);

      do_reset(10);
      do_load_case(c);

      lo_i = $urandom_range(0, img.nwin - 1);
      hi_i = $urandom_range(lo_i, img.nwin - 1);

      // Jedan nasumicni prozor u modu A
      do_run_mode_a(img.win_x[lo_i], 0, img.width);

      // Sweep nad nasumicnim podopsegom
      do_run_mode_b(img.win_x[lo_i], img.win_x[hi_i], step, 0, img.width);
      do_read_hits();
    end
  endtask

endclass : vj_vseq_random

`endif
