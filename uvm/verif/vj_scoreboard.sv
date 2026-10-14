`ifndef VJ_SCOREBOARD_SV
`define VJ_SCOREBOARD_SV


// vj_scoreboard.sv
// Jedino mjesto u okruzenju gdje se donosi sud o ispravnosti dizajna.
// Scoreboard prima transakcije sa oba monitora i radi cetiri grupe provjera:
//  1. Shadow model registarskog fajla
//     Za svaki upis se azurira softverska kopija registra, uz odsijecanje na
//     stvarnu sirinu polja u jezgru (X_START/X_LAST/X_STEP i HIT_ADDR su
//     9-bitni, ROW_BASE 5-bitni). Svako citanje se poredi sa tom kopijom.
//     Registar koji je u wrapperu siri nego u jezgru propagirao bi nevalidnu
//     vrijednost dalje u dizajn, a read-back bi to sakrio - zato se maske
//     provjeravaju eksplicitno.
//  2. Zlatni vektori
//     RESULT (mod A), HIT_COUNT i HIT_DATA (mod B) se porede sa referentnim
//     vrijednostima iz tb_vectors.txt.
//  3. Semantika kontrolne logike
//     START je impuls (jezgro se ne smije samo restartovati), DONE je sticky
//     i cisti se iskljucivo upisom jedinice, irq prati DONE, a BUSY mora biti
//     nula kada nijedan run nije u toku.
//  4. Protokol i pravila koriscenja
//     BRESP i RRESP moraju biti OK, a u row banke se ne smije pisati dok je
//     jezgro zauzeto - port A je dijeljen izmedju te upisne putanje i col0
//     citanja jezgra.

`uvm_analysis_imp_decl(_axil)
`uvm_analysis_imp_decl(_bram)

class vj_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(vj_scoreboard)

  uvm_analysis_imp_axil #(vj_axil_seq_item, vj_scoreboard) axil_imp;
  uvm_analysis_imp_bram #(vj_bram_seq_item, vj_scoreboard) bram_imp;

  vj_config cfg;


  // Shadow model registara. Vrijednosti su vec odsjecene na sirinu polja,
  // tacno onako kako ih dizajn cuva.
  bit [8:0] sh_x_start;
  bit [8:0] sh_x_last;
  bit [8:0] sh_x_step;
  bit [31:0] sh_width;
  bit [4:0] sh_row_base;
  bit [8:0] sh_hit_addr;
  bit sh_mode;

  // Stanje kontrolne logike
  bit run_started;  // upisan je START, a DONE jos nije clearovan
  bit done_seen;  // procitali smo DONE = 1 od zadnjeg cleara


  // Run parametri koje trenutno provjeravamo
  bit run_mode;  // 0 = mod A, 1 = mod B
  int run_x_start;
  int run_x_last;
  int run_x_step;
  int run_case;  // indeks slucaja u bankama u trenutku runa
  bit run_frame;  // run se provjerava u odnosu na frame vektore
  int run_y;  // y-pozicija u streaming rezimu

  int exp_hits[$];  // ocekivani sadrzaj hit buffera za mod B
  bit exp_hits_valid;  // zlatna referenca postoji za cijeli sweep


  // Statistika
  int unsigned n_checks = 0;
  int unsigned n_errors = 0;
  int unsigned n_reg_checks = 0;
  int unsigned n_result_checks = 0;
  int unsigned n_hit_checks = 0;
  int unsigned n_runs_a = 0;
  int unsigned n_runs_b = 0;
  int unsigned n_skipped = 0;  // citanja bez zlatne reference
  int unsigned n_bram_writes = 0;


  // Pokrivenost rezultata koji su stvarno provjereni u odnosu na referencu.
  // Za razliku od pokrivenosti u monitoru, ovdje se sampluju samo transakcije
  // za koje postoji zlatni vektor, pa ovaj covergroup mjeri koliko je
  // algoritma zaista verifikovano, a ne samo koliko je magistrale odradjeno.

  int cov_case;
  int cov_result;
  int cov_mode;
  int cov_hits;

  covergroup cg_checked_results;
    option.per_instance = 1;
    option.name = "cg_checked_results";

    cp_case: coverpoint cov_case {bins c[] = {[1 : 5]};}

    cp_result: coverpoint cov_result {
      bins accept = {1};
      bins reject_st0 = {0};
      bins reject_early = {[-4 : -1]};
      bins reject_mid = {[-12 : -5]};
      bins reject_late = {[-24 : -13]};
    }

    cp_mode: coverpoint cov_mode {bins mode_a = {0}; bins mode_b = {1};}

    // Svaki slucaj mora biti provjeren u oba rezima rada
    x_case_mode : cross cp_case, cp_mode;
  endgroup

  covergroup cg_checked_hits;
    option.per_instance = 1;
    option.name = "cg_checked_hits";

    cp_hits: coverpoint cov_hits {
      bins none = {0}; bins one = {1}; bins few = {[2 : 4]}; bins many = {[5 : HIT_DEPTH]};
    }
  endgroup


  function new(string name = "vj_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    axil_imp = new("axil_imp", this);
    bram_imp = new("bram_imp", this);
    cg_checked_results = new();
    cg_checked_hits    = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(vj_config)::get(this, "", "vj_config", cfg))
      `uvm_fatal("NOCFG", {"Config objekat mora biti postavljen za ", get_full_name(), ".cfg"})
    apply_reset();
  endfunction


  // Reset vrijednosti su preuzete iz reg_write procesa u
  // vj_cascade_v1_0_S00_AXI.vhd. X_STEP je jedini registar cija reset
  // vrijednost nije nula.
  function void apply_reset();
    sh_x_start  = '0;
    sh_x_last   = '0;
    sh_x_step   = 9'd1;
    sh_width    = '0;
    sh_row_base = '0;
    sh_hit_addr = '0;
    sh_mode     = 1'b0;

    run_started = 1'b0;
    done_seen   = 1'b0;
    run_mode    = 1'b0;
    run_x_start = 0;
    run_x_last  = 0;
    run_x_step  = 1;
    run_case    = 0;
    run_frame   = 1'b0;
    run_y       = 0;
    exp_hits.delete();
    exp_hits_valid = 1'b0;
  endfunction


  // Prijava greske na jednom mjestu, da bi brojac i poruka uvijek isli zajedno
  function void fail(string ctx, string msg);
    n_errors++;
    `uvm_error("VJ_SB", {ctx, ": ", msg})
  endfunction

  function void check_eq(string ctx, int got, int exp);
    n_checks++;
    if (got !== exp) fail(ctx, $sformatf("ocekivano %0d, dobijeno %0d", exp, got));
  endfunction


  // AXI4-Lite transakcije
  function void write_axil(vj_axil_seq_item item);
    case (item.kind)
      VJ_RESET: begin
        `uvm_info("VJ_SB", "Reset - shadow model vracen na reset vrijednosti", UVM_MEDIUM)
        apply_reset();
      end
      VJ_WRITE: handle_write(item);
      VJ_READ:  handle_read(item);
      default:  ;  // VJ_IDLE nema efekta
    endcase
  endfunction


  // Upis: azuriranje shadow modela uz odsijecanje na sirinu polja
  function void handle_write(vj_axil_seq_item item);

    if (cfg.check_resp) begin
      n_checks++;
      if (item.resp !== RESP_OKAY)
        fail($sformatf("upis u %s", vj_reg_name(item.addr)), $sformatf(
             "BRESP = %b, ocekivano OKAY", item.resp));
    end

    case (item.addr)

      REG_CTRL: begin
        // MODE je jedini bit CTRL-a koji se pamti
        sh_mode = item.data[CTRL_BIT_MODE];

        // Upis jedinice cisti DONE
        if (item.data[CTRL_BIT_DONE]) begin
          done_seen   = 1'b0;
          run_started = 1'b0;
        end

        // Soft reset prekida tekuce izvrsavanje
        if (item.data[CTRL_BIT_RESET]) begin
          run_started    = 1'b0;
          exp_hits_valid = 1'b0;
          `uvm_info("VJ_SB", "Soft reset jezgra", UVM_HIGH)
        end

        // START pokrece novo izvrsavanje - snimamo parametre
        if (item.data[CTRL_BIT_START] && !item.data[CTRL_BIT_RESET]) begin
          run_started = 1'b1;
          done_seen   = 1'b0;
          run_mode    = item.data[CTRL_BIT_MODE];
          run_x_start = int'(sh_x_start);
          run_x_last  = int'(sh_x_last);
          run_x_step  = int'(sh_x_step);
          run_case    = cfg.active_case;
          run_frame   = cfg.frame_mode;
          run_y       = cfg.active_y;
          predict_hits();

          if (run_mode == 1'b0) n_runs_a++;
          else n_runs_b++;

          `uvm_info("VJ_SB", $sformatf(
                                 "START: mod %s, x_start=%0d x_last=%0d x_step=%0d, slucaj=%0d",
                                 run_mode ? "B" : "A", run_x_start, run_x_last, run_x_step,
                                 run_case), UVM_HIGH)
        end
      end

      REG_X_START:  sh_x_start = item.data[8:0];
      REG_X_LAST:   sh_x_last = item.data[8:0];
      REG_X_STEP:   sh_x_step = item.data[8:0];
      REG_WIDTH:    sh_width = item.data;
      REG_ROW_BASE: sh_row_base = item.data[4:0];
      REG_HIT_ADDR: sh_hit_addr = item.data[8:0];

      // Upis u read-only registre mora ostati bez ikakvog efekta -
      // shadow se namjerno ne dira, pa ce sljedeci read-back to potvrditi
      REG_RESULT, REG_HIT_COUNT, REG_HIT_DATA, REG_STATUS: begin
        `uvm_info("VJ_SB", $sformatf(
                  "Upis u read-only registar %s ignorisan (ocekivano)", vj_reg_name(item.addr)),
                  UVM_HIGH)
      end

      default: begin
        `uvm_info("VJ_SB", $sformatf("Upis na nemapiranu adresu 0x%02h", item.addr), UVM_HIGH)
      end
    endcase
  endfunction


  // Ocekivani sadrzaj hit buffera za sweep koji upravo krece
  function void predict_hits();
    vj_image_case img;
    int hits[$];
    bit complete;

    exp_hits.delete();
    exp_hits_valid = 1'b0;

    if (run_mode != 1'b1) return;  // samo mod B

    if (run_frame) begin
      if (cfg.frame == null) return;
      void'(cfg.frame.expected_hits(run_y, hits, complete));
    end else begin
      if (run_case < 1) return;  // banke ne sadrze poznatu sliku
      img = cfg.cases[run_case-1];
      void'(img.expected_hits(run_x_start, run_x_last, run_x_step, hits, complete));
    end

    if (!complete) begin
      `uvm_info("VJ_SB",
                "Sweep obuhvata prozore bez zlatne reference - hit buffer se ne provjerava",
                UVM_MEDIUM)
      return;
    end

    exp_hits       = hits;
    exp_hits_valid = 1'b1;

    `uvm_info("VJ_SB", $sformatf(
              "Ocekivano %0d pogodaka u sweep-u x=%0d..%0d korak %0d%s",
              exp_hits.size(),
              run_x_start,
              run_x_last,
              run_x_step,
              run_frame ? $sformatf(
                  ", y=%0d", run_y
              ) : ""
              ), UVM_HIGH)
  endfunction


  // Citanje: poredjenje sa shadow modelom i zlatnim vektorima
  function void handle_read(vj_axil_seq_item item);
    int    got_signed;
    string ctx;

    got_signed = $signed(item.data);
    ctx        = $sformatf("citanje %s", vj_reg_name(item.addr));

    if (cfg.check_resp) begin
      n_checks++;
      if (item.resp !== RESP_OKAY) fail(ctx, $sformatf("RRESP = %b, ocekivano OKAY", item.resp));
    end

    case (item.addr)

      // CTRL: vracaju se samo MODE (bit 2) i DONE (bit 4)
      REG_CTRL: begin
        if (cfg.check_regs) begin
          n_reg_checks++;
          n_checks++;
          if (item.data[CTRL_BIT_MODE] !== sh_mode)
            fail(ctx, $sformatf("CTRL.MODE = %b, ocekivano %b", item.data[CTRL_BIT_MODE], sh_mode));

          // Svi ostali bitovi osim MODE i DONE moraju biti nula
          n_checks++;
          if ((item.data & ~(CTRL_MODE | CTRL_DONE)) !== 32'h0)
            fail(ctx, $sformatf("neispravni bitovi u CTRL: 0x%08h", item.data));
        end

        check_done_semantics(item, ctx);
      end

      // RW registri - poredjenje sa shadow modelom
      REG_X_START:  check_reg_readback(ctx, item.data, int'(sh_x_start));
      REG_X_LAST:   check_reg_readback(ctx, item.data, int'(sh_x_last));
      REG_X_STEP:   check_reg_readback(ctx, item.data, int'(sh_x_step));
      REG_WIDTH:    check_reg_readback(ctx, item.data, int'(sh_width));
      REG_ROW_BASE: check_reg_readback(ctx, item.data, int'(sh_row_base));
      REG_HIT_ADDR: check_reg_readback(ctx, item.data, int'(sh_hit_addr));


      // STATUS: bit 0 je BUSY, ostalo nule
      REG_STATUS: begin
        n_checks++;
        if ((item.data & 32'hFFFF_FFFE) !== 32'h0)
          fail(ctx, $sformatf("neispravni bitovi u STATUS: 0x%08h", item.data));

        // Ako nijedan run nije u toku, jezgro mora biti idle.
        // Ovo je provjera koja pada ako wrapper tretira START kao nivo
        // umjesto kao impuls - jezgro bi se samo restartovalo.
        if (!run_started && !done_seen) begin
          n_checks++;
          if (item.data[0] !== 1'b0)
            fail(ctx, "BUSY = 1 iako nijedno pokretanje nije u toku (START se ponasa kao nivo?)");
        end
      end


      // RESULT: zlatni vektor za prozor koji je upravo obradjen
      REG_RESULT: check_result(item, got_signed, ctx);


      // HIT_COUNT / HIT_DATA: zlatni vektori za sweep
      REG_HIT_COUNT: check_hit_count(item, ctx);
      REG_HIT_DATA:  check_hit_data(item, ctx);

      default: ;
    endcase

    // irq je u dizajnu direktno spojen na CTRL.DONE
    if (cfg.check_irq && item.addr == REG_CTRL && item.data[CTRL_BIT_DONE] === 1'b1) begin
      n_checks++;
      if (item.idle_cycles != 1) fail(ctx, "CTRL.DONE = 1 ali irq linija nije aktivna");
    end
  endfunction

  function void check_reg_readback(string ctx, bit [31:0] got, int exp);
    if (!cfg.check_regs) return;
    n_reg_checks++;
    n_checks++;
    if (int'(got) !== exp)
      fail(ctx, $sformatf("read-back 0x%08h, ocekivano 0x%08h (shadow model)", got, exp));
  endfunction


  // DONE mora biti sticky: jednom postavljen ostaje postavljen dok se ne
  // upise jedinica. I ne smije se pojaviti bez prethodnog START-a
  function void check_done_semantics(vj_axil_seq_item item, string ctx);
    bit d;
    d = item.data[CTRL_BIT_DONE];

    if (d === 1'b1) begin
      n_checks++;
      if (!run_started && !done_seen)
        fail(ctx, "DONE = 1 iako nijedan START nije upisan od zadnjeg cistenja");
      done_seen = 1'b1;
    end else begin
      // Ako smo DONE vec vidjeli, a nije ocisten upisom jedinice,
      // mora i dalje biti postavljen
      n_checks++;
      if (done_seen) fail(ctx, "DONE je pao na 0 bez upisa jedinice - nije sticky");
    end
  endfunction


  // Poredjenje RESULT registra sa zlatnim vektorom
  function void check_result(vj_axil_seq_item item, int got, string ctx);
    vj_image_case img;
    int exp;

    if (!cfg.check_results) return;

    // RESULT je smislen samo poslije pokretanja u modu A
    if (run_mode != 1'b0) return;

    if (run_frame) begin
      if (cfg.frame == null || !cfg.frame.expected_for(run_y, run_x_start, exp)) begin
        n_skipped++;
        return;
      end
      n_result_checks++;
      n_checks++;
      if (got !== exp)
        fail(ctx, $sformatf(
             "y=%0d, prozor x=%0d: ocekivano %0d, dobijeno %0d", run_y, run_x_start, exp, got));
      cov_case   = 1;
      cov_result = got;
      cov_mode   = 0;
      cg_checked_results.sample();
      return;
    end

    if (run_case < 1) begin
      n_skipped++;
      `uvm_info("VJ_SB", {ctx, ": banke ne sadrze poznatu sliku, rezultat se ne provjerava"},
                UVM_HIGH)
      return;
    end

    img = cfg.cases[run_case-1];

    if (!img.expected_for_x(run_x_start, exp)) begin
      n_skipped++;
      `uvm_info("VJ_SB", $sformatf("%s: nema zlatne reference za x=%0d u slucaju %0d", ctx,
                                   run_x_start, run_case), UVM_HIGH)
      return;
    end

    n_result_checks++;
    n_checks++;
    if (got !== exp) begin
      fail(ctx, $sformatf(
           "slucaj %0d, prozor x=%0d: ocekivano %0d, dobijeno %0d", run_case, run_x_start, exp, got
           ));
    end else begin
      `uvm_info("VJ_SB", $sformatf("OK slucaj %0d, x=%0d, RESULT = %0d", run_case, run_x_start, got
                ), UVM_HIGH)
    end

    cov_case   = run_case;
    cov_result = got;
    cov_mode   = 0;
    cg_checked_results.sample();
  endfunction


  function void check_hit_count(vj_axil_seq_item item, string ctx);
    int got;

    if (!cfg.check_results) return;
    if (run_mode != 1'b1) return;  // HIT_COUNT je smislen samo u modu B

    got = int'(item.data[HIT_AW:0]);

    // Gornji bitovi moraju biti nula - hit_count je 10-bitni signal
    n_checks++;
    if ((item.data >> (HIT_AW + 1)) !== 32'h0)
      fail(ctx, $sformatf("neispravni gornji bitovi u HIT_COUNT: 0x%08h", item.data));

    if (!exp_hits_valid) begin
      n_skipped++;
      `uvm_info("VJ_SB", {ctx, ": nema potpune zlatne reference za sweep"}, UVM_HIGH)
      return;
    end

    n_hit_checks++;
    n_checks++;
    if (got !== exp_hits.size())
      fail(ctx, $sformatf(
           "%s, sweep x=%0d..%0d korak %0d: ocekivano %0d pogodaka, dobijeno %0d",
           run_frame ? $sformatf(
               "y=%0d", run_y
           ) : $sformatf(
               "slucaj %0d", run_case
           ),
           run_x_start,
           run_x_last,
           run_x_step,
           exp_hits.size(),
           got
           ));

    cov_hits = got;
    cg_checked_hits.sample();

    cov_case   = run_frame ? 1 : run_case;
    cov_result = (exp_hits.size() > 0) ? 1 : 0;
    cov_mode   = 1;
    cg_checked_results.sample();
  endfunction

  function void check_hit_data(vj_axil_seq_item item, string ctx);
    int got;
    int idx;

    if (!cfg.check_results) return;
    if (run_mode != 1'b1) return;
    if (!exp_hits_valid) begin
      n_skipped++;
      return;
    end

    got = int'(item.data[COL_W-1:0]);
    idx = int'(sh_hit_addr);

    n_checks++;
    if ((item.data >> COL_W) !== 32'h0)
      fail(ctx, $sformatf("neispravni gornji bitovi u HIT_DATA: 0x%08h", item.data));

    if (idx >= exp_hits.size()) begin
      // Citanje iznad broja pogodaka - sadrzaj nije definisan, preskacemo
      n_skipped++;
      return;
    end

    n_hit_checks++;
    n_checks++;
    if (got !== exp_hits[idx])
      fail(ctx, $sformatf("pogodak %0d: ocekivano x=%0d, dobijeno x=%0d", idx, exp_hits[idx], got));
  endfunction


  // BRAM transakcije
  function void write_bram(vj_bram_seq_item item);

    n_bram_writes++;

    // Port A row banaka je dijeljen izmedju ove upisne putanje i col0
    // citanja jezgra, uz pretpostavku da se nikada ne preklapaju. Redovi
    // se smiju uploadovati samo dok je jezgro u idle stanju
    if (run_started && !done_seen) begin
      fail("BRAM upis", $sformatf(
           "upis u banku %0d, kolonu %0d dok je jezgro zauzeto - port A je dijeljen sa col0 citanjem jezgra",
           item.bank,
           item.col
           ));
    end

    // Adresna putanja: banka i kolona rekonstruisane iz bajt adrese moraju
    // odgovarati onome sto je driver kodovao
    n_checks++;
    if (item.byte_addr !== vj_bram_byte_addr(item.bank, item.col))
      fail("BRAM upis", $sformatf(
           "byte adresa 0x%05h ne odgovara banci %0d i koloni %0d",
           item.byte_addr,
           item.bank,
           item.col
           ));

    n_checks++;
    if (item.bank >= N_BANKS)
      fail("BRAM upis", $sformatf("banka %0d je izvan opsega 0..%0d", item.bank, N_BANKS - 1));
  endfunction


  // Krajnji izvjestaj
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);

    `uvm_info("VJ_SB", "===============================================", UVM_NONE)
    `uvm_info("VJ_SB", "        VIOLA-JONES SCOREBOARD REPORT          ", UVM_NONE)
    `uvm_info("VJ_SB", "===============================================", UVM_NONE)
    `uvm_info("VJ_SB", $sformatf("Ukupno provjera            : %0d", n_checks), UVM_NONE)
    `uvm_info("VJ_SB", $sformatf("  registarskih read-backova   : %0d", n_reg_checks), UVM_NONE)
    `uvm_info("VJ_SB", $sformatf("  RESULT vs zlatni vektor  : %0d", n_result_checks), UVM_NONE)
    `uvm_info("VJ_SB", $sformatf("  hit buffer vs referenca  : %0d", n_hit_checks), UVM_NONE)
    `uvm_info("VJ_SB", $sformatf("Pokretanja jezgra, mod A   : %0d", n_runs_a), UVM_NONE)
    `uvm_info("VJ_SB", $sformatf("Pokretanja jezgra, mod B   : %0d", n_runs_b), UVM_NONE)
    `uvm_info("VJ_SB", $sformatf("Upisa u row banke          : %0d", n_bram_writes), UVM_NONE)
    `uvm_info("VJ_SB", $sformatf("Citanja bez reference      : %0d", n_skipped), UVM_NONE)
    `uvm_info("VJ_SB", $sformatf("Neslaganja                 : %0d", n_errors), UVM_NONE)
    `uvm_info("VJ_SB", "-----------------------------------------------", UVM_NONE)

    if (n_errors == 0 && n_checks > 0) `uvm_info("VJ_SB", "REZULTAT: PASS", UVM_NONE)
    else if (n_checks == 0) `uvm_warning("VJ_SB", "REZULTAT: nijedna provjera nije izvrsena")
    else `uvm_error("VJ_SB", $sformatf("REZULTAT: FAIL - %0d neslaganja", n_errors))

    `uvm_info("VJ_SB", "===============================================", UVM_NONE)
  endfunction

endclass : vj_scoreboard

`endif
