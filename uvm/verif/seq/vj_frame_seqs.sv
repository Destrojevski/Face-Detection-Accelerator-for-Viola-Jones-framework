`ifndef VJ_FRAME_SEQS_SV
`define VJ_FRAME_SEQS_SV

// vj_frame_seqs.sv
// Streaming rezim - obrada cijele slike red po red, onako kako to radi
// bare-metal aplikacija.
// Za y-poziciju y dizajn ocekuje:
//   banke 0..24  ->  integralni redovi y .. y+24, rotirani sa ROW_BASE
//   SQ0_BANK     ->  kvadrirani integralni red y
//   SQ23_BANK    ->  kvadrirani integralni red y+23
// Prelazak sa y na y+1:
//   ROW_BASE' = (ROW_BASE + 1) mod 25
//   banka koja je drzala logicki red 0 (najstariji) prima integralni red y+25
//   oba kvadrirana reda se prepisuju u cijelosti
// Dakle po y-koraku se upisuju TRI reda, od kojih su dva kvadrirana. To je
// dominantan trosak streaminga i posljedica je toga sto se oba kvadrirana reda
// mijenjaju pri svakom pomjeranju po y, dok se od 25 integralnih mijenja samo
// jedan.


// Pocetno punjenje za y-poziciju 0: svih 25 integralnih redova plus dva
// kvadrirana.

class vj_bram_frame_init_seq extends vj_bram_base_seq;

  `uvm_object_utils(vj_bram_frame_init_seq)

  vj_frame_case frame;
  int           row_base = 0;  // rotacija na startu, obicno 0

  function new(string name = "vj_bram_frame_init_seq");
    super.new(name);
  endfunction

  task body();
    int k, j, phys;

    if (frame == null) `uvm_fatal(get_type_name(), "Handle na frame (frame) nije postavljen")

    `uvm_info(
        get_type_name(),
        $sformatf(
            "Pocetno punjenje za y=0: %0d integralnih redova + 2 kvadrirana, sirina %0d, ROW_BASE=%0d",
            INT_ROWS, frame.width, row_base), UVM_LOW)

    // Logicki red k - integralni red k, fizicka banka (k + row_base) mod 25
    for (k = 0; k < INT_ROWS; k++) begin
      phys = (k + row_base) % N_INT_BANKS;
      for (j = 0; j < frame.width; j++) write_word(phys, j, frame.ig[k][j]);
    end

    // Kvadrirani redovi 0 i 23 - banke sa fiksnim indeksima, ne rotiraju se
    for (j = 0; j < frame.width; j++) write_word(SQ0_BANK, j, frame.sq[0][j]);
    for (j = 0; j < frame.width; j++) write_word(SQ23_BANK, j, frame.sq[WIN_SIZE-1][j]);
  endtask

endclass : vj_bram_frame_init_seq


// Jedan korak po y osi: novi integralni red u banku najstarijeg reda, pa oba
// kvadrirana reda.
// Poziva se za prelazak na y-poziciju y_next, uz row_base koji ce vaziti na toj
// poziciji: row_base_next = y_next mod 25.

class vj_bram_frame_step_seq extends vj_bram_base_seq;

  `uvm_object_utils(vj_bram_frame_step_seq)

  vj_frame_case frame;
  int           y_next;  // y-pozicija na koju prelazimo

  function new(string name = "vj_bram_frame_step_seq");
    super.new(name);
  endfunction

  task body();
    int j, phys, new_row, rb;

    if (frame == null) `uvm_fatal(get_type_name(), "Handle na frame (frame) nije postavljen")

    rb = y_next % N_INT_BANKS;

    // Na poziciji y_next, logicki red 24 je integralni red y_next + 24.
    // Njegova fizicka banka je (24 + rb) mod 25 - upravo ona koja je na
    // prethodnoj poziciji drzala logicki red 0, tj. najstariji red.
    new_row = y_next + INT_ROWS - 1;
    phys    = (INT_ROWS - 1 + rb) % N_INT_BANKS;

    if (new_row >= frame.n_int_rows)
      `uvm_fatal(get_type_name(), $sformatf(
                 "Integralni red %0d ne postoji u fajlu (ima ih %0d)", new_row, frame.n_int_rows))

    for (j = 0; j < frame.width; j++) write_word(phys, j, frame.ig[new_row][j]);

    // Oba kvadrirana reda se mijenjaju
    for (j = 0; j < frame.width; j++) write_word(SQ0_BANK, j, frame.sq[y_next][j]);
    for (j = 0; j < frame.width; j++) write_word(SQ23_BANK, j, frame.sq[y_next+WIN_SIZE-1][j]);

    `uvm_info(
        get_type_name(),
        $sformatf(
            "y=%0d: integralni red %0d -> banka %0d, ROW_BASE=%0d, kvadrirani redovi %0d i %0d",
            y_next, new_row, phys, rb, y_next, y_next + WIN_SIZE - 1), UVM_HIGH)
  endtask

endclass : vj_bram_frame_step_seq


// Virtuelna sekvenca: obrada cijele slike.
// Ovo je jedini test koji vjerno reprodukuje redoslijed pristupa iz bare-metal
// aplikacije. Verifikuje ono sto nijedan drugi test ne dodiruje: da dizajn
// ispravno radi kada se izmedju dva sweep-a promijeni samo jedan red od 25, a
// ROW_BASE se pomjeri za jedan.
class vj_vseq_frame extends vj_vseq_base;

  `uvm_object_utils(vj_vseq_frame)

  // Ogranicavanje broja y-pozicija radi krace simulacije. 0 znaci sve.
  int max_y = 0;

  function new(string name = "vj_vseq_frame");
    super.new(name);
  endfunction

  task body();
    vj_bram_frame_init_seq init_s;
    vj_bram_frame_step_seq step_s;
    vj_frame_case          fr;
    int y, y_limit, rb;

    `uvm_info(get_type_name(), "=== Scenario: obrada cijele slike (streaming) ===", UVM_LOW)

    fr = cfg.frame;
    if (fr == null) `uvm_fatal(get_type_name(), "Frame vektori nisu ucitani")

    y_limit = (max_y > 0 && max_y < fr.n_y) ? max_y : fr.n_y;

    // Scoreboard od sada koristi frame referencu umjesto cases[]
    cfg.frame_mode = 1'b1;
    cfg.active_case = 0;

    do_reset(10);

    // Pocetno punjenje za y = 0
    cfg.active_y = 0;
    init_s = vj_bram_frame_init_seq::type_id::create("frame_init");
    init_s.frame    = fr;
    init_s.row_base = 0;
    init_s.start(p_sequencer.bram_seqr);

    for (y = 0; y < y_limit; y++) begin

      if (y > 0) begin
        // Streaming korak - jedan novi integralni red + oba kvadrirana
        cfg.active_y = y;
        step_s = vj_bram_frame_step_seq::type_id::create($sformatf("frame_step_%0d", y));
        step_s.frame = fr;
        step_s.y_next = y;
        step_s.start(p_sequencer.bram_seqr);
      end

      rb = y % N_INT_BANKS;

      // Sweep na tekucoj y-poziciji
      do_run_mode_b(fr.x_start, fr.x_last, fr.x_step, rb, fr.width);
      do_read_hits();

      if ((y % 10) == 0)
        `uvm_info(get_type_name(), $sformatf("Obradjeno %0d / %0d y-pozicija", y + 1, y_limit),
                  UVM_LOW)
    end

    `uvm_info(get_type_name(), $sformatf("Streaming zavrsen: %0d y-pozicija, sirina %0d", y_limit,
                                         fr.width), UVM_LOW)
  endtask

endclass : vj_vseq_frame

`endif
