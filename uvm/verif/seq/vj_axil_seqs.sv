`ifndef VJ_AXIL_SEQS_SV
`define VJ_AXIL_SEQS_SV


// vj_axil_seqs.sv
// Sekvence koje se pokrecu na AXI4-Lite sekvenceru.
//   vj_axil_base_seq       zajednicke pomocne metode (upis, citanje, cekanje)
//   vj_axil_reset_seq      hardverski reset
//   vj_axil_reg_seq        write / read-back svih upisivih registara
//   vj_axil_handshake_seq  varijacije timinga AXI handshake-a
//   vj_axil_run_seq        jedno pokretanje jezgra i citanje rezultata
//   vj_axil_hit_read_seq   citanje cijelog hit buffera nakon sweep-a
//   vj_axil_random_seq     nasumicni registarski saobracaj



// Bazna sekvenca - sve ostale je nasljedjuju zbog pomocnih metoda
class vj_axil_base_seq extends uvm_sequence #(vj_axil_seq_item);

  `uvm_object_utils(vj_axil_base_seq)

  // Maksimalan broj pollova CTRL registra prije nego sto se sekvenca canceluje.
  // Najduzi realan prozor prolazi kroz svih 2913 klasifikatora, pa je ovo
  // postavljeno sa velikom rezervom, ali sprijecava beskonacnu simulaciju ako
  // se jezgro zaglavi.
  int unsigned poll_limit = 100000;

  function new(string name = "vj_axil_base_seq");
    super.new(name);
  endfunction


  // Upis u registar
  task automatic write_reg(bit [5:0] a, bit [31:0] d, int unsigned awd = 0, int unsigned wd = 0,
                           int unsigned bd = 0);
    vj_axil_seq_item item;
    item = vj_axil_seq_item::type_id::create("wr");
    start_item(item);
    item.kind        = VJ_WRITE;
    item.addr        = a;
    item.data        = d;
    item.strb        = 4'hF;
    item.aw_delay    = awd;
    item.w_delay     = wd;
    item.b_delay     = bd;
    item.r_delay     = 0;
    item.idle_cycles = 0;
    finish_item(item);
  endtask

  // Citanje registra. Driver upisuje procitanu vrijednost nazad u item.
  task automatic read_reg(bit [5:0] a, output bit [31:0] d, input int unsigned rd = 0);
    vj_axil_seq_item item;
    item = vj_axil_seq_item::type_id::create("rd");
    start_item(item);
    item.kind        = VJ_READ;
    item.addr        = a;
    item.data        = '0;
    item.aw_delay    = 0;
    item.w_delay     = 0;
    item.b_delay     = 0;
    item.r_delay     = rd;
    item.idle_cycles = 0;
    finish_item(item);
    d = item.data;
  endtask

  // Hardverski reset (puls na aresetn)
  task automatic hw_reset(int unsigned cycles = 10);
    vj_axil_seq_item item;
    item = vj_axil_seq_item::type_id::create("rst");
    start_item(item);
    item.kind        = VJ_RESET;
    item.idle_cycles = cycles;
    finish_item(item);
  endtask

  // Pauza bez magistralne aktivnosti
  task automatic idle(int unsigned cycles = 4);
    vj_axil_seq_item item;
    item = vj_axil_seq_item::type_id::create("idle");
    start_item(item);
    item.kind        = VJ_IDLE;
    item.idle_cycles = cycles;
    finish_item(item);
  endtask

  // Soft reset preko CTRL bita 0
  task automatic soft_reset();
    write_reg(REG_CTRL, CTRL_RESET);
    idle(5);
  endtask

  // Cekanje da jezgro zavrsi. DONE je sticky bit koji hardver postavlja, a
  // softver ga cisti upisom jedinice - zato se poll radi citanjem CTRL-a.
  task automatic wait_done();
    bit [31:0] d;
    int unsigned n = 0;
    forever begin
      read_reg(REG_CTRL, d);
      if (d[CTRL_BIT_DONE] === 1'b1) break;
      n++;
      if (n > poll_limit) begin
        `uvm_error("AXIL_SEQ",
                   $sformatf("Timeout: DONE nije postavljen ni nakon %0d pollova CTRL registra",
                             poll_limit))
        break;
      end
    end
  endtask

  task automatic clear_done();
    write_reg(REG_CTRL, CTRL_DONE);
  endtask

endclass : vj_axil_base_seq

// Hardverski reset kao samostalna sekvenca
class vj_axil_reset_seq extends vj_axil_base_seq;

  `uvm_object_utils(vj_axil_reset_seq)

  int unsigned reset_cycles = 10;

  function new(string name = "vj_axil_reset_seq");
    super.new(name);
  endfunction

  task body();
    `uvm_info(get_type_name(), "Hardverski reset dizajna", UVM_MEDIUM)
    hw_reset(reset_cycles);
  endtask

endclass : vj_axil_reset_seq

// Citanje svih registara neposredno poslije reseta. Scoreboard nad svojim
// shadow modelom provjerava da su RW registri na reset vrijednostima, a
// read-only registri na nuli.
class vj_axil_post_reset_seq extends vj_axil_base_seq;

  `uvm_object_utils(vj_axil_post_reset_seq)

  function new(string name = "vj_axil_post_reset_seq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] d;
    `uvm_info(get_type_name(), "Citanje reset vrijednosti svih registara", UVM_MEDIUM)
    read_reg(REG_CTRL, d);
    read_reg(REG_X_START, d);
    read_reg(REG_X_LAST, d);
    read_reg(REG_X_STEP, d);
    read_reg(REG_WIDTH, d);
    read_reg(REG_ROW_BASE, d);
    read_reg(REG_HIT_ADDR, d);
    read_reg(REG_STATUS, d);
    read_reg(REG_RESULT, d);
    read_reg(REG_HIT_COUNT, d);
    read_reg(REG_HIT_DATA, d);
  endtask

endclass : vj_axil_post_reset_seq

// Semantika kontrolnih bitova. Sekvenca generise tacno onaj redoslijed
// pristupa koji razdvaja ispravnu implementaciju od uobicajenih gresaka:
//   - START tretiran kao nivo umjesto kao impuls: jezgro bi se restartovalo
//     samo od sebe, pa bi BUSY poslije mirovanja opet bio visok
//   - DONE koji se cisti pri citanju umjesto upisom jedinice: drugo citanje
//     CTRL-a vratilo bi nulu
//   - DONE koji se gubi pri upisu u bilo koji drugi registar
// Provjere radi scoreboard.
class vj_axil_ctrl_seq extends vj_axil_base_seq;

  `uvm_object_utils(vj_axil_ctrl_seq)

  function new(string name = "vj_axil_ctrl_seq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] d;

    // DONE mora biti cist prije pokretanja
    clear_done();
    read_reg(REG_CTRL, d);

    // Jedno pokretanje, jedan prozor
    write_reg(REG_X_START, 0);
    write_reg(REG_X_LAST, 0);
    write_reg(REG_CTRL, CTRL_START);
    wait_done();

    // DONE mora prezivjeti citanje
    read_reg(REG_CTRL, d);
    // i upis u drugi registar
    write_reg(REG_X_START, 0);
    read_reg(REG_CTRL, d);

    //a cisti se iskljucivo upisom jedinice
    clear_done();
    read_reg(REG_CTRL, d);

    // START je impuls: poslije jednog pokretanja jezgro ostaje idle
    idle(20);
    read_reg(REG_STATUS, d);
    read_reg(REG_CTRL, d);

    // Soft reset vraca jezgro u idle stanje
    soft_reset();
    read_reg(REG_STATUS, d);

    // Pokretanje u modu B pa soft reset u toku rada takodje mora ostaviti
    // jezgro u idle stanju.
    write_reg(REG_X_START, 0);
    write_reg(REG_X_LAST, 96);
    write_reg(REG_X_STEP, WIN_SIZE);
    write_reg(REG_CTRL, CTRL_START | CTRL_MODE);
    idle(50);
    soft_reset();
    read_reg(REG_STATUS, d);
    clear_done();
  endtask

endclass : vj_axil_ctrl_seq

// Provjera registarskog fajla: upis pa read-back svakog upisivog registra,
// ukljucujuci i vrijednosti koje moraju biti odsjecene na sirinu registra.
// Same provjere radi scoreboard - sekvenca samo generise transfere.
class vj_axil_reg_seq extends vj_axil_base_seq;

  `uvm_object_utils(vj_axil_reg_seq)

  function new(string name = "vj_axil_reg_seq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] d;

    `uvm_info(get_type_name(), "Write / read-back svih upisivih registara", UVM_MEDIUM)

    write_reg(REG_X_START, 123);
    read_reg(REG_X_START, d);
    write_reg(REG_X_LAST, 200);
    read_reg(REG_X_LAST, d);
    write_reg(REG_X_STEP, 3);
    read_reg(REG_X_STEP, d);
    write_reg(REG_ROW_BASE, 7);
    read_reg(REG_ROW_BASE, d);
    write_reg(REG_WIDTH, 360);
    read_reg(REG_WIDTH, d);
    write_reg(REG_HIT_ADDR, 5);
    read_reg(REG_HIT_ADDR, d);

    // Granicne vrijednosti sirine polja.
    // ROW_BASE je 5-bitan u jezgru: 33 se mora vratiti kao 1. Registar
    // siri u wrapperu nego u jezgru propagirao bi nevalidnu rotaciju u
    // bank array.
    write_reg(REG_ROW_BASE, 33);
    read_reg(REG_ROW_BASE, d);
    write_reg(REG_ROW_BASE, 24);
    read_reg(REG_ROW_BASE, d);
    write_reg(REG_ROW_BASE, 0);
    read_reg(REG_ROW_BASE, d);

    // X_START / X_LAST / X_STEP su 9-bitni
    write_reg(REG_X_START, 32'h0000_02FF);
    read_reg(REG_X_START, d);
    write_reg(REG_X_START, 32'h0000_0300);
    read_reg(REG_X_START, d);
    write_reg(REG_X_LAST, 32'h0000_01FF);
    read_reg(REG_X_LAST, d);
    write_reg(REG_X_STEP, WIN_SIZE);
    read_reg(REG_X_STEP, d);

    // HIT_ADDR je 9-bitan
    write_reg(REG_HIT_ADDR, 32'h0000_01FF);
    read_reg(REG_HIT_ADDR, d);
    write_reg(REG_HIT_ADDR, 32'h0000_0200);
    read_reg(REG_HIT_ADDR, d);
    write_reg(REG_HIT_ADDR, 0);
    read_reg(REG_HIT_ADDR, d);

    // WIDTH je 32-bitni registar
    write_reg(REG_WIDTH, 32'hDEAD_BEEF);
    read_reg(REG_WIDTH, d);
    write_reg(REG_WIDTH, MAX_IMG_WIDTH);
    read_reg(REG_WIDTH, d);

    // CTRL.MODE mora ostati zapamcen
    write_reg(REG_CTRL, CTRL_MODE);
    read_reg(REG_CTRL, d);
    write_reg(REG_CTRL, 32'h0);
    read_reg(REG_CTRL, d);

    // Read-only registri se citaju da bi bili pokriveni, a upis u njih
    // mora ostati bez efekta.
    read_reg(REG_RESULT, d);
    read_reg(REG_HIT_COUNT, d);
    read_reg(REG_HIT_DATA, d);
    read_reg(REG_STATUS, d);

    write_reg(REG_RESULT, 32'hFFFF_FFFF);
    write_reg(REG_STATUS, 32'hFFFF_FFFF);
    read_reg(REG_STATUS, d);
  endtask

endclass : vj_axil_reg_seq


// Varijacije timinga handshake-a. Slave koji pretpostavlja da AWVALID i WVALID
// uvijek stizu zajedno, ili da su BREADY i RREADY zakucani na jedinicu, ovdje
// mora pasti.

class vj_axil_handshake_seq extends vj_axil_base_seq;

  `uvm_object_utils(vj_axil_handshake_seq)

  function new(string name = "vj_axil_handshake_seq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] d;

    `uvm_info(get_type_name(), "Varijacije timinga AXI4-Lite handshake-a", UVM_MEDIUM)

    // adresa prva, podaci 3 takta kasnije
    write_reg(REG_X_START, 11, 0, 3, 0);
    read_reg(REG_X_START, d);

    // podaci prvi, adresa 3 takta kasnije
    write_reg(REG_X_START, 22, 3, 0, 0);
    read_reg(REG_X_START, d);

    // BREADY kasni 4 takta - BVALID mora biti zadrzan
    write_reg(REG_X_START, 33, 0, 0, 4);
    read_reg(REG_X_START, d);

    // RREADY kasni 4 takta - RDATA mora biti zadrzan
    write_reg(REG_X_START, 44);
    read_reg(REG_X_START, d, 4);

    // kombinacija svega
    write_reg(REG_X_LAST, 55, 2, 4, 3);
    read_reg(REG_X_LAST, d, 2);

    write_reg(REG_X_STEP, 7, 4, 0, 1);
    read_reg(REG_X_STEP, d, 3);

    // CTRL se u ostatku okruzenja uvijek upisuje sa podrazumijevanim
    // timingom, pa cross cp_waddr x cp_order ostaje nepokriven za taj
    // registar. Ovdje se upisuje bezopasna vrijednost (samo MODE bit, bez
    // START-a) sa razlicitim redoslijedom kanala.
    write_reg(REG_CTRL, CTRL_MODE, 0, 3, 0);  // adresa prva
    read_reg(REG_CTRL, d);
    write_reg(REG_CTRL, 32'h0, 3, 0, 0);  // podaci prvi
    read_reg(REG_CTRL, d);
    write_reg(REG_CTRL, CTRL_MODE, 2, 4, 2);  // kombinacija
    read_reg(REG_CTRL, d, 3);
    write_reg(REG_CTRL, 32'h0);
  endtask

endclass : vj_axil_handshake_seq


// Jedno pokretanje jezgra. Parametri se postavljaju spolja, iz virtuelne
// sekvence, prije poziva start().
class vj_axil_run_seq extends vj_axil_base_seq;

  `uvm_object_utils(vj_axil_run_seq)

  vj_mode_e           mode         = MODE_A_SINGLE;
  int unsigned        x_start      = 0;
  int unsigned        x_last       = 0;
  int unsigned        x_step       = 1;
  int unsigned        row_base     = 0;
  int unsigned        width        = MAX_IMG_WIDTH;
  bit                 set_width    = 1'b1;

  // Popunjava sekvenca nakon izvrsavanja
  bit          [31:0] last_result;

  function new(string name = "vj_axil_run_seq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] d;
    bit [31:0] ctrl_val;

    // Zaostali DONE iz prethodnog pokretanja mora biti ociscen prije nego
    // krenemo, inace bi wait_done odmah prosao.
    clear_done();

    write_reg(REG_ROW_BASE, row_base);
    if (set_width) write_reg(REG_WIDTH, width);
    write_reg(REG_X_START, x_start);
    write_reg(REG_X_LAST, x_last);
    if (mode == MODE_B_SWEEP) write_reg(REG_X_STEP, x_step);

    ctrl_val = CTRL_START | ((mode == MODE_B_SWEEP) ? CTRL_MODE : 32'h0);
    write_reg(REG_CTRL, ctrl_val);

    // Citanje STATUS-a dok je obrada u toku. Bez ovoga se BUSY nikada ne
    // vidi u visokom stanju - svi ostali pristupi STATUS registru desavaju
    // se tek poslije DONE, pa bi dizajn koji BUSY nikada ne podigne prosao
    // neprimjeceno.
    read_reg(REG_STATUS, d);

    wait_done();
    clear_done();

    if (mode == MODE_A_SINGLE) begin
      read_reg(REG_RESULT, d);
      last_result = d;
    end

    // Poslije zavrsetka jezgro mora biti u idle stanju. START je impuls,
    // pa se izvrsavanje ne smije samo od sebe ponovo pokrenuti.
    read_reg(REG_STATUS, d);
  endtask

endclass : vj_axil_run_seq


// Citanje hit buffera poslije sweep-a u modu B.
class vj_axil_hit_read_seq extends vj_axil_base_seq;

  `uvm_object_utils(vj_axil_hit_read_seq)

  // Ako je 0, sekvenca prvo procita HIT_COUNT pa cita tacno toliko unosa.
  int unsigned n_entries = 0;

  function new(string name = "vj_axil_hit_read_seq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] d;
    int unsigned cnt;
    int unsigned i;

    read_reg(REG_HIT_COUNT, d);
    cnt = (n_entries != 0) ? n_entries : d[HIT_AW:0];

    if (cnt > HIT_DEPTH) begin
      `uvm_error(get_type_name(), $sformatf("HIT_COUNT = %0d prelazi dubinu hit buffera (%0d)",
                                            cnt, HIT_DEPTH))
      cnt = HIT_DEPTH;
    end

    for (i = 0; i < cnt; i++) begin
      write_reg(REG_HIT_ADDR, i);
      read_reg(REG_HIT_DATA, d);
    end
  endtask

endclass : vj_axil_hit_read_seq

// Probing hazarda: pokrece sweep sa potencijalno opasnim parametrima i, umjesto
// da ceka DONE, poslije zadatog broja taktova provjerava da li je jezgro jos
// uvijek zauzeto. Time probing ne moze blokirati simulaciju bez obzira na ishod,
// a rezultat je jednoznacan: BUSY = 1 poslije toliko taktova znaci da se
// izvrsavanje ne zavrsava.
// Na kraju se jezgro uvijek vraca u idle soft resetom, pa naredne sekvence
// mogu normalno raditi.
class vj_axil_hazard_probe_seq extends vj_axil_base_seq;

  `uvm_object_utils(vj_axil_hazard_probe_seq)

  string       probe_name  = "hazard";
  int unsigned x_start     = 0;
  int unsigned x_last      = 0;
  int unsigned x_step      = 1;
  int unsigned wait_cycles = 100000;

  // Rezultat probinga - test ga moze procitati poslije start()
  bit          core_hung   = 1'b0;

  function new(string name = "vj_axil_hazard_probe_seq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] d;
    int unsigned waited;
    int unsigned chunk;

    clear_done();
    write_reg(REG_X_START, x_start);
    write_reg(REG_X_LAST, x_last);
    write_reg(REG_X_STEP, x_step);
    write_reg(REG_CTRL, CTRL_START | CTRL_MODE);

    // Cekanje u chunkovima vremena, uz povremenu provjeru DONE bita
    waited = 0;
    chunk  = 2000;
    while (waited < wait_cycles) begin
      idle(chunk);
      waited += chunk;
      read_reg(REG_CTRL, d);
      if (d[CTRL_BIT_DONE] === 1'b1) break;
    end

    read_reg(REG_CTRL, d);
    if (d[CTRL_BIT_DONE] === 1'b1) begin
      core_hung = 1'b0;
      `uvm_info(
          get_type_name(),
          $sformatf(
              "PROBA [%s]: izvrsavanje se zavrsilo (DONE postavljen) - hipoteza NIJE potvrdjena",
              probe_name), UVM_LOW)
    end else begin
      read_reg(REG_STATUS, d);
      core_hung = d[0];
      if (core_hung)
        `uvm_error(get_type_name(), $sformatf(
                   "PROBA [%s]: jezgro je jos uvijek zauzeto (BUSY = 1) poslije %0d taktova, a DONE nije postavljen - izvrsavanje se ne zavrsava",
                   probe_name,
                   wait_cycles
                   ))
      else
        `uvm_error(get_type_name(), $sformatf(
                   "PROBA [%s]: jezgro je u idle stanju ali DONE nije postavljen - izvrsavanje je zavrseno bez signalizacije",
                   probe_name
                   ))
    end

    // Oporavak: soft reset vraca jezgro u idle bez obzira na ishod
    soft_reset();
    clear_done();
    write_reg(REG_X_STEP, 1);
    read_reg(REG_STATUS, d);
    if (d[0] !== 1'b0)
      `uvm_error(get_type_name(), $sformatf(
                 "PROBA [%s]: soft reset nije vratio jezgro u idle stanje", probe_name))
  endtask

endclass : vj_axil_hazard_probe_seq


// Dva START upisa: drugi stize dok je jezgro zauzeto. Tekuce izvrsavanje mora
// se uredno zavrsiti, a drugi START ne smije ni prekinuti ni produziti obradu.
class vj_axil_double_start_seq extends vj_axil_base_seq;

  `uvm_object_utils(vj_axil_double_start_seq)

  int unsigned x_start = 0;
  int unsigned x_last  = 0;
  int unsigned x_step  = 1;

  function new(string name = "vj_axil_double_start_seq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] d;

    clear_done();
    write_reg(REG_X_START, x_start);
    write_reg(REG_X_LAST, x_last);
    write_reg(REG_X_STEP, x_step);
    write_reg(REG_CTRL, CTRL_START | CTRL_MODE);

    // Potvrda da je izvrsavanje zaista u toku prije drugog START-a
    idle(20);
    read_reg(REG_STATUS, d);
    if (d[0] !== 1'b1)
      `uvm_info(get_type_name(),
                "Jezgro je vec zavrsilo prije drugog START-a - proba nije mjerodavna, povecati duzinu sweep-a",
                UVM_LOW)

    // Drugi START dok je jezgro zauzeto
    write_reg(REG_CTRL, CTRL_START | CTRL_MODE);
    `uvm_info(get_type_name(), "Drugi START upisan dok je jezgro zauzeto", UVM_LOW)

    // Izvrsavanje se mora uredno zavrsiti
    wait_done();
    clear_done();

    read_reg(REG_STATUS, d);
    if (d[0] !== 1'b0)
      `uvm_error(get_type_name(),
                 "Jezgro je zauzeto poslije zavrsetka - drugi START je pokrenuo novo izvrsavanje")

    // Hit buffer mora odgovarati jednom sweep-u, ne dva puta ponovljenom
    read_reg(REG_HIT_COUNT, d);
    `uvm_info(get_type_name(), $sformatf("HIT_COUNT poslije dvostrukog START-a: %0d", d[HIT_AW:0]),
              UVM_LOW)
  endtask

endclass : vj_axil_double_start_seq


// Nasumicni registarski transferi. Provjerava da dizajn ne reaguje lose na
// kombinacije upisa i citanja koje direktni testovi ne pokrivaju, i puni
// pokrivenost timinga handshake-a.
// Iz randomizacije je namjerno iskljucen CTRL registar: nasumicno postavljanje
// START bita pokrenulo bi jezgro dok scoreboard nema zlatnu referencu za taj
// prozor, a nasumicni RESET bi ponistio ostatak scenarija. CTRL se u ovoj
// sekvenci gadja samo kontrolisano, na kraju.
class vj_axil_random_seq extends vj_axil_base_seq;

  `uvm_object_utils(vj_axil_random_seq)

  rand int unsigned n_items;

  constraint c_n_items {n_items inside {[20 : 60]};}

  function new(string name = "vj_axil_random_seq");
    super.new(name);
  endfunction

  task body();
    vj_axil_seq_item item;
    int unsigned i;

    `uvm_info(get_type_name(), $sformatf("Nasumicni registarski saobracaj, %0d transakcija",
                                         n_items), UVM_MEDIUM)

    for (i = 0; i < n_items; i++) begin
      item = vj_axil_seq_item::type_id::create($sformatf("rand_item_%0d", i));
      start_item(item);
      if (!item.randomize() with {
            kind inside {VJ_WRITE, VJ_READ};
            addr != REG_CTRL;
          })
        `uvm_error(get_type_name(), "Randomizacija transakcije nije uspjela")
      finish_item(item);
    end

    // Kontrolisano vracanje registara u poznato stanje
    write_reg(REG_ROW_BASE, 0);
    write_reg(REG_X_STEP, 1);
    clear_done();
  endtask

endclass : vj_axil_random_seq

`endif
