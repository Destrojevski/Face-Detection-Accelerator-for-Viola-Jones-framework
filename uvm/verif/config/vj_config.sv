`ifndef VJ_CONFIG_SV
`define VJ_CONFIG_SV


// vj_config.sv
// Centralni konfiguracioni objekat verifikacionog okruzenja. Cuva:
//   - aktivnost agenata,
//   - putanje do fajlova sa zlatnim vektorima,
//   - ucitane test slucajeve (vj_image_case),
//   - indeks slucaja koji je trenutno upisan u row banke (active_case),
//   - switcheve za pojedinacne provjere u scoreboard-u.
// Objekat se kreira u testu, upisuje u uvm_config_db i preuzimaju ga agenti,
// driveri, monitori i scoreboard.

class vj_config extends uvm_object;


  // Aktivnost agenata
  uvm_active_passive_enum axil_is_active = UVM_ACTIVE;
  uvm_active_passive_enum bram_is_active = UVM_ACTIVE;


  // Putanje. data_dir se moze prebaciti argumentom +VJ_DATA_DIR=<putanja>
  // kako bi isti izvorni kod radio i u Vivado xsim radnom direktorijumu i u
  // Xcelium radnom direktorijumu, bez odvojenih verzija fajlova.
  string data_dir = ".";
  string vector_file = "tb_vectors.txt";

  // Ucitani slucajevi. cases[0] je slucaj 1 iz fajla.
  int n_cases = 0;
  vj_image_case cases[];

  // Indeks slucaja koji je trenutno upisan u row banke (baza jedinica).
  // 0 znaci da banke ne sadrze poznatu sliku pa scoreboard ne provjerava
  // algoritamske rezultate (npr. u cistim registarskim testovima).
  int active_case = 0;

  // Koliko slucajeva test obradjuje. Ne spustati ispod 4 u punom testu:
  // prva tri slucaja nemaju nijedan prihvacen prozor, pa mod B ne bi bio
  // stvarno provjeren.
  int max_cases = 5;

  // Vektori pune slike (streaming rezim).
  string frame_file = "tb_frame.txt";
  vj_frame_case frame = null;

  // Kada je postavljeno, scoreboard algoritamske rezultate poredi sa
  // frame vektorima na y-poziciji active_y, umjesto sa cases[active_case-1].
  bit frame_mode = 1'b0;
  int active_y = 0;


  // Prekidaci provjera u scoreboard-u
  bit check_regs = 1'b1;  // read-back RW registara u odnosu na shadow model
  bit check_results = 1'b1;  // RESULT / HIT_COUNT / HIT_DATA u odnosu na zlatne vektore
  bit check_resp = 1'b1;  // BRESP / RRESP moraju biti OK
  bit check_irq = 1'b1;  // irq mora pratiti CTRL.DONE

  `uvm_object_utils_begin(vj_config)
    `uvm_field_enum(uvm_active_passive_enum, axil_is_active, UVM_DEFAULT)
    `uvm_field_enum(uvm_active_passive_enum, bram_is_active, UVM_DEFAULT)
    `uvm_field_string(data_dir, UVM_DEFAULT)
    `uvm_field_string(vector_file, UVM_DEFAULT)
    `uvm_field_int(n_cases, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(active_case, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(max_cases, UVM_DEFAULT | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "vj_config");
    super.new(name);
  endfunction


  // Preuzimanje putanje iz komandne linije. Poziva se iz bazne test klase
  // prije load_golden_vectors().
  function void get_cmdline_overrides();
    string s;
    if ($value$plusargs("VJ_DATA_DIR=%s", s)) begin
      data_dir = s;
      `uvm_info("VJ_CFG", $sformatf("data_dir preuzet iz plusarga: '%s'", data_dir), UVM_LOW)
    end
    if ($value$plusargs("VJ_VECTOR_FILE=%s", s)) begin
      vector_file = s;
      `uvm_info("VJ_CFG", $sformatf("vector_file preuzet iz plusarga: '%s'", vector_file), UVM_LOW)
    end
  endfunction


  // Puna putanja do fajla sa vektorima.
  function string vector_path();
    if (data_dir == "" || data_dir == ".") return vector_file;
    return {data_dir, "/", vector_file};
  endfunction

  // Ucitavanje zlatnih vektora. Ovo je jedini ulaz podataka u okruzenje -
  // i stimulus (redovi integralne slike) i referenca (ocekivani RESULT po
  // prozoru) dolaze iz istog fajla.
  function void load_golden_vectors();
    int fd;
    int code;
    int c, r, j;
    int v, xv, ev;
    string path;

    path = vector_path();
    fd   = $fopen(path, "r");
    if (fd == 0) begin
      `uvm_fatal(
          "VJ_CFG",
          $sformatf(
              "Ne mogu otvoriti fajl sa vektorima: '%s'. Provjeriti da li je kopiran u radni direktorijum simulacije ili postaviti +VJ_DATA_DIR=<putanja>.",
              path))
    end

    code = $fscanf(fd, "%d", n_cases);
    if (code != 1) `uvm_fatal("VJ_CFG", {"Neispravno zaglavlje fajla ", path})

    if (max_cases > 0 && max_cases < n_cases) n_cases = max_cases;

    cases = new[n_cases];

    for (c = 0; c < n_cases; c++) begin
      cases[c] = vj_image_case::type_id::create($sformatf("case_%0d", c + 1));
      cases[c].case_id = c + 1;

      code = $fscanf(fd, "%d %d", cases[c].width, cases[c].nwin);
      if (code != 2) `uvm_fatal("VJ_CFG", $sformatf("Neispravno zaglavlje slucaja %0d", c + 1))

      cases[c].allocate();

      // 25 redova integralne slike
      for (r = 0; r < INT_ROWS; r++)
      for (j = 0; j < cases[c].width; j++) begin
        code = $fscanf(fd, "%d", v);
        if (code != 1)
          `uvm_fatal("VJ_CFG", $sformatf("Fajl se zavrsio u redu %0d slucaja %0d", r, c + 1))
        cases[c].ig[r][j] = v;
      end

      // kvadrirana integralna slika, logicki red 0
      for (j = 0; j < cases[c].width; j++) begin
        code = $fscanf(fd, "%d", v);
        cases[c].sq0[j] = v;
      end

      // kvadrirana integralna slika, logicki red 23
      for (j = 0; j < cases[c].width; j++) begin
        code = $fscanf(fd, "%d", v);
        cases[c].sq23[j] = v;
      end

      // zlatni rezultati po prozoru
      for (j = 0; j < cases[c].nwin; j++) begin
        code = $fscanf(fd, "%d %d", xv, ev);
        if (code != 2)
          `uvm_fatal("VJ_CFG", $sformatf("Neispravan zlatni unos %0d u slucaju %0d", j, c + 1))
        cases[c].win_x[j]   = xv;
        cases[c].win_exp[j] = ev;
      end

      `uvm_info("VJ_CFG", cases[c].convert2string(), UVM_LOW)
    end

    $fclose(fd);
    `uvm_info("VJ_CFG", $sformatf("Ucitano %0d test slucajeva iz '%s'", n_cases, path), UVM_LOW)
  endfunction


  function string frame_path();
    if (data_dir == "" || data_dir == ".") return frame_file;
    return {data_dir, "/", frame_file};
  endfunction


  // Ucitavanje vektora pune slike. Vrijednosti integralne i kvadrirane
  // integralne slike citaju se heksadecimalno: kvadrirana integralna slika
  // pune velicine prelazi opseg 32-bitnog broja sa znakom, pa bi decimalno
  // citanje dalo negativne vrijednosti. Dizajn ih tretira kao unsigned.
  function void load_frame_vectors();
    int fd, code, r, j, y, n, i;
    int yy, xv, ev;
    bit [31:0] v;
    string tag, path;

    path = frame_path();
    fd   = $fopen(path, "r");
    if (fd == 0)
      `uvm_fatal(
          "VJ_CFG", $sformatf(
          "Ne mogu otvoriti fajl sa frame vektorima: '%s'. Vidi doc/format_frame_vektora.md.", path
          ))

    code = $fscanf(fd, "%s", tag);
    if (tag != "FRAME")
      `uvm_fatal("VJ_CFG", $sformatf("Ocekivano zaglavlje FRAME, procitano '%s'", tag))

    frame = vj_frame_case::type_id::create("frame");
    code = $fscanf(
        fd,
        "%d %d %d %d %d %d",
        frame.width,
        frame.n_int_rows,
        frame.n_y,
        frame.x_start,
        frame.x_last,
        frame.x_step
    );
    if (code != 6) `uvm_fatal("VJ_CFG", "Neispravno zaglavlje frame fajla")

    if (frame.width > MAX_IMG_WIDTH)
      `uvm_fatal("VJ_CFG", $sformatf(
                 "Sirina %0d prelazi MAX_IMG_WIDTH (%0d)", frame.width, MAX_IMG_WIDTH))
    if (frame.n_int_rows < frame.n_y + INT_ROWS - 1)
      `uvm_fatal("VJ_CFG", $sformatf(
                 "n_int_rows (%0d) je premalo za n_y (%0d): treba bar %0d",
                 frame.n_int_rows,
                 frame.n_y,
                 frame.n_y + INT_ROWS - 1
                 ))

    frame.allocate_image();

    code = $fscanf(fd, "%s", tag);
    if (tag != "INT") `uvm_fatal("VJ_CFG", $sformatf("Ocekivana sekcija INT, procitano '%s'", tag))
    for (r = 0; r < frame.n_int_rows; r++)
    for (j = 0; j < frame.width; j++) begin
      code = $fscanf(fd, "%h", v);
      if (code != 1) `uvm_fatal("VJ_CFG", $sformatf("Fajl se zavrsio u INT redu %0d", r))
      frame.ig[r][j] = v;
    end

    code = $fscanf(fd, "%s", tag);
    if (tag != "SQ") `uvm_fatal("VJ_CFG", $sformatf("Ocekivana sekcija SQ, procitano '%s'", tag))
    for (r = 0; r < frame.n_int_rows; r++)
    for (j = 0; j < frame.width; j++) begin
      code = $fscanf(fd, "%h", v);
      if (code != 1) `uvm_fatal("VJ_CFG", $sformatf("Fajl se zavrsio u SQ redu %0d", r))
      frame.sq[r][j] = v;
    end

    code = $fscanf(fd, "%s", tag);
    if (tag != "WINDOWS")
      `uvm_fatal("VJ_CFG", $sformatf("Ocekivana sekcija WINDOWS, procitano '%s'", tag))
    for (i = 0; i < frame.n_y; i++) begin
      code = $fscanf(fd, "%d %d", yy, n);
      if (code != 2) `uvm_fatal("VJ_CFG", $sformatf("Neispravno zaglavlje bloka prozora %0d", i))
      if (yy != i)
        `uvm_fatal("VJ_CFG", $sformatf(
                   "Blokovi prozora moraju ici redom: ocekivano y=%0d, procitano %0d", i, yy))
      frame.allocate_windows(yy, n);
      for (j = 0; j < n; j++) begin
        code = $fscanf(fd, "%d %d", xv, ev);
        if (code != 2) `uvm_fatal("VJ_CFG", $sformatf("Neispravan zlatni unos %0d na y=%0d", j, yy))
        frame.win_x[yy][j]   = xv;
        frame.win_exp[yy][j] = ev;
      end
    end

    $fclose(fd);
    `uvm_info("VJ_CFG", frame.convert2string(), UVM_LOW)
  endfunction


  // Slucaj koji je trenutno u row bankama, ili null ako nijedan nije.
  function vj_image_case get_active_case();
    if (active_case < 1 || active_case > cases.size()) return null;
    return cases[active_case-1];
  endfunction

endclass : vj_config

`endif
