`ifndef VJ_BRAM_SEQS_SV
`define VJ_BRAM_SEQS_SV


// vj_bram_seqs.sv
// Sekvence koje se pokrecu na BRAM sekvenceru.
//   vj_bram_base_seq       pomocna metoda za jedan upis
//   vj_bram_load_case_seq  upload cijelog test slucaja u row banke
//   vj_bram_marker_seq     marker u nultu kolonu svake od 27 banaka
//   vj_bram_random_seq     nasumicni upisi po cijelom adresnom opsegu

class vj_bram_base_seq extends uvm_sequence #(vj_bram_seq_item);

  `uvm_object_utils(vj_bram_base_seq)

  function new(string name = "vj_bram_base_seq");
    super.new(name);
  endfunction

  task automatic write_word(int bank, int col, int val);
    vj_bram_seq_item item;
    item = vj_bram_seq_item::type_id::create("bram_wr");
    start_item(item);
    item.bank = bank[4:0];
    item.col  = col[8:0];
    item.data = val;
    item.we   = 4'hF;
    item.en   = 1'b1;
    finish_item(item);
  endtask

endclass : vj_bram_base_seq

// Upload jednog test slucaja: 25 redova integralne slike u banke 0..24, zatim
// dva reda kvadrirane integralne slike u banke 25 i 26.
// Ovo je jedini prenos velikog obima u sistemu - za detekciju cijele slike
// oko 1.06 M rijeci - zbog cega dizajn i ima poseban BRAM port umjesto da sve
// ide kroz AXI4-Lite.

class vj_bram_load_case_seq extends vj_bram_base_seq;

  `uvm_object_utils(vj_bram_load_case_seq)

  vj_image_case img;  // postavlja virtuelnu sekvencu prije start()

  // Rotacija row banaka. Softver logicki red r upisuje u fizicku banku
  // (r + row_shift) mod 25, a u ROW_BASE registar upisuje istu vrijednost
  // row_shift. Jezgro tada preko rot_bank() pronalazi red na pravom mjestu.
  // Za row_shift = 0 upload je identican nerotiranom slucaju.
  int row_shift = 0;

  function new(string name = "vj_bram_load_case_seq");
    super.new(name);
  endfunction

  task body();
    int r, j, phys;

    if (img == null)
      `uvm_fatal(get_type_name(),
                 "Handle na test slucaj (img) nije postavljen prije pokretanja sekvence")

    `uvm_info(
        get_type_name(),
        $sformatf(
            "Upload slucaja %0d u row banke: %0d kolona x %0d redova + 2 kvadrirana reda, rotacija %0d",
            img.case_id, img.width, INT_ROWS, row_shift), UVM_LOW)

    for (r = 0; r < INT_ROWS; r++) begin
      // Ista formula koju jezgro koristi u rot_bank()
      phys = (r + row_shift) % N_INT_BANKS;
      for (j = 0; j < img.width; j++) write_word(phys, j, img.ig[r][j]);
    end

    // Banke kvadrirane integralne slike imaju fiksne indekse i ne rotiraju se
    for (j = 0; j < img.width; j++) write_word(SQ0_BANK, j, img.sq0[j]);

    for (j = 0; j < img.width; j++) write_word(SQ23_BANK, j, img.sq23[j]);

    `uvm_info(get_type_name(), $sformatf("Upload slucaja %0d zavrsen (%0d rijeci)", img.case_id,
                                         INT_ROWS * img.width + 2 * img.width), UVM_LOW)
  endtask

endclass : vj_bram_load_case_seq

// Marker u karakteristicne kolone svake banke.
// Ova sekvenca ne nosi sliku - ona dokazuje da je cijeli adresni opseg dostupan
// u svakoj banci. To je bitno iz dva razloga:
//  1. Gornja banka (26) zahtijeva bit 15 bajt adrese, pa uzi dekoder ne bi
//     mogao da je adresira.
//  2. Sirina testnih slika zavisi od skale i ne mora dosezati MAX_IMG_WIDTH.
//     Kada su u vektor fajlu samo uze skale, najvise kolone se nikada ne
//     upisuju podacima slike, pa crossbanka x kolona ostaje nepokriven iako je
//     adresna putanja ispravna. Upis markera u prvu, srednju i posljednju
//     kolonu svake banke pokriva taj opseg nezavisno od izabranih vektora.
class vj_bram_marker_seq extends vj_bram_base_seq;

  `uvm_object_utils(vj_bram_marker_seq)

  function new(string name = "vj_bram_marker_seq");
    super.new(name);
  endfunction

  task body();
    int b;
    int cols[3];

    cols[0] = 0;
    cols[1] = MAX_IMG_WIDTH / 2;
    cols[2] = MAX_IMG_WIDTH - 1;

    `uvm_info(get_type_name(), $sformatf("Upis markera u kolone 0, %0d i %0d svih %0d banaka",
                                         cols[1], cols[2], N_BANKS), UVM_MEDIUM)

    for (b = 0; b < N_BANKS; b++) foreach (cols[c]) write_word(b, cols[c], 1000 + b * 4 + c);
  endtask

endclass : vj_bram_marker_seq


// Nasumicni upisi. Sluzi za punjenje pokrivenosti adresne putanje - naročito
// cross banka x kolona, gdje direktni testovi gadjaju samo kolone do sirine
// tekuceg slucaja.
class vj_bram_random_seq extends vj_bram_base_seq;

  `uvm_object_utils(vj_bram_random_seq)

  rand int unsigned n_items;

  constraint c_n {n_items inside {[50 : 200]};}

  function new(string name = "vj_bram_random_seq");
    super.new(name);
  endfunction

  task body();
    vj_bram_seq_item item;
    int unsigned i;

    for (i = 0; i < n_items; i++) begin
      item = vj_bram_seq_item::type_id::create($sformatf("rand_bram_%0d", i));
      start_item(item);
      if (!item.randomize() with {
            en == 1'b1;
            we == 4'hF;
          })
        `uvm_error(get_type_name(), "Randomizacija BRAM transakcije nije uspjela")
      finish_item(item);
    end
  endtask

endclass : vj_bram_random_seq

`endif
