`ifndef VJ_AXIL_DRIVER_SV
`define VJ_AXIL_DRIVER_SV


// vj_axil_driver.sv
// Jedina komponenta koja aktivno mijenja signale AXI4-Lite magistrale.
// Protokol slave-a diktira dvije stvari koje driver mora postovati:
//
//  1. AWREADY i WREADY se podizu tek kada su AWVALID i WVALID istovremeno
//     visoki (vidjeti write_ch proces u vj_cascade_v1_0_S00_AXI.vhd). Driver zato
//     drzi oba kanala podignuta dok ih slave pojedinacno ne prihvati, umjesto
//     da ceka jedan pa drugi.
//
//  2. Citanje ima jedan ciklus kasnjenja: ARREADY se podigne jedan takt nakon
//     ARVALID, adresa se tada latchuje, a RVALID stize takt kasnije. Driver
//     spusta ARVALID tek kada vidi ARREADY visok, jer slave u tom istom taktu
//     evaluira rd_en = ARREADY and ARVALID.


class vj_axil_driver extends uvm_driver #(vj_axil_seq_item);

  `uvm_component_utils(vj_axil_driver)

  virtual vj_if vif;
  vj_config     cfg;

  // Gornja granica cekanja na bilo koji AXI handshake. Bez nje se greska u
  // protokolu ispoljava kao simulacija koja tiho stoji dok je ne prekine
  // watchdog u top modulu - bez ijedne poruke o uzroku. Sa njom driver
  // odmah prijavi koji handshake nije zavrsen i na kojem registru.
  localparam int unsigned BUS_TIMEOUT = 1000;

  function new(string name = "vj_axil_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual vj_if)::get(this, "", "vj_if", vif))
      `uvm_fatal("NOVIF", {"Virtuelni interfejs mora biti postavljen za ", get_full_name(), ".vif"})
    if (!uvm_config_db#(vj_config)::get(this, "", "vj_config", cfg))
      `uvm_fatal("NOCFG", {"Config objekat mora biti postavljen za ", get_full_name(), ".cfg"})
  endfunction

  // Sve linije kojima upravlja master idu u neaktivno stanje.
  task automatic drive_idle();
    vif.awaddr  <= '0;
    vif.awprot  <= '0;
    vif.awvalid <= 1'b0;
    vif.wdata   <= '0;
    vif.wstrb   <= '0;
    vif.wvalid  <= 1'b0;
    vif.bready  <= 1'b0;
    vif.araddr  <= '0;
    vif.arprot  <= '0;
    vif.arvalid <= 1'b0;
    vif.rready  <= 1'b0;
  endtask

  task run_phase(uvm_phase phase);
    vj_axil_seq_item item;

    // Driver je jedini vlasnik aresetn linije. Reset se drzi aktivnim od
    // pocetka simulacije, a svaki test kao prvi korak pokrece reset
    // sekvencu koja ga podigne.
    vif.aresetn <= 1'b0;
    drive_idle();

    forever begin
      seq_item_port.get_next_item(item);

      case (item.kind)
        VJ_WRITE: do_write(item);
        VJ_READ: do_read(item);
        VJ_RESET: do_reset(item);
        VJ_IDLE: do_idle(item);
        default: `uvm_error("AXIL_DRV", $sformatf("Nepoznat tip transakcije: %s", item.kind.name()))
      endcase

      seq_item_port.item_done();
    end
  endtask


  // AXI4-Lite upis

  task automatic do_write(vj_axil_seq_item item);
    int unsigned max_delay;
    int unsigned i;
    int unsigned wait_cnt;

    @(posedge vif.clk);

    // Kanali koji ne kasne krecu odmah
    if (item.aw_delay == 0) begin
      vif.awaddr  <= item.addr;
      vif.awvalid <= 1'b1;
    end
    if (item.w_delay == 0) begin
      vif.wdata  <= item.data;
      vif.wstrb  <= item.strb;
      vif.wvalid <= 1'b1;
    end

    // Kanali koji kasne se podizu na svom taktu
    max_delay = (item.aw_delay > item.w_delay) ? item.aw_delay : item.w_delay;
    for (i = 1; i <= max_delay; i++) begin
      @(posedge vif.clk);
      if (i == item.aw_delay) begin
        vif.awaddr  <= item.addr;
        vif.awvalid <= 1'b1;
      end
      if (i == item.w_delay) begin
        vif.wdata  <= item.data;
        vif.wstrb  <= item.strb;
        vif.wvalid <= 1'b1;
      end
    end

    // Cekamo takt u kome slave prihvata i adresu i podatak.
    //
    // BREADY se podize U ISTOM taktu u kome se desi prihvatanje, a ne
    // ranije. Razlog je u slave-u:
    //     IF wr_en = '1' THEN bvalid_r <= '1';
    //     ELSIF S_AXI_BREADY = '1' AND bvalid_r = '1' THEN bvalid_r <= '0';
    //
    // Ako je BREADY visok vec prije prihvatanja, slave postavi BVALID na
    // jedan takt i odmah ga u sljedecem taktu obori, pa master koji ga
    // trazi takt kasnije nikada ne vidi odgovor. Podizanjem BREADY-ja tacno
    // na ivici prihvatanja dobija se handshake u sljedecem taktu, sto
    // pokriva bin cp_bready::immediate bez gubitka odgovora.
    wait_cnt = 0;
    forever begin
      @(posedge vif.clk);
      if (vif.awready === 1'b1 && vif.awvalid === 1'b1 &&
                vif.wready  === 1'b1 && vif.wvalid  === 1'b1) begin
        vif.awvalid <= 1'b0;
        vif.wvalid  <= 1'b0;
        if (item.b_delay == 0) vif.bready <= 1'b1;
        break;
      end
      if (++wait_cnt > BUS_TIMEOUT) begin
        `uvm_error(
            "AXIL_DRV",
            $sformatf(
                "Timeout: slave nije prihvatio upis u %s ni nakon %0d taktova (AWREADY/WREADY se ne podizu)",
                vj_reg_name(item.addr), BUS_TIMEOUT))
        drive_idle();
        return;
      end
    end

    item.addr = item.addr;  // adresa i podatak su vec postavljeni

    if (item.b_delay != 0) begin
      // Namjerno kasnjenje - slave mora zadrzati BVALID sve dok master
      // ne bude spreman.
      repeat (item.b_delay) @(posedge vif.clk);
      vif.bready <= 1'b1;
    end

    wait_cnt = 0;
    forever begin
      @(posedge vif.clk);
      if (vif.bvalid === 1'b1) break;
      if (++wait_cnt > BUS_TIMEOUT) begin
        `uvm_error("AXIL_DRV",
                   $sformatf("Timeout: nema BVALID odgovora na upis u %s ni nakon %0d taktova",
                             vj_reg_name(item.addr), BUS_TIMEOUT))
        drive_idle();
        return;
      end
    end
    item.resp = vif.bresp;

    @(posedge vif.clk);
    vif.bready <= 1'b0;

    `uvm_info("AXIL_DRV", item.convert2string(), UVM_HIGH)
  endtask


  // AXI4-Lite citanje
  task automatic do_read(vj_axil_seq_item item);
    int unsigned wait_cnt;

    @(posedge vif.clk);
    vif.araddr  <= item.addr;
    vif.arvalid <= 1'b1;

    wait_cnt = 0;
    forever begin
      @(posedge vif.clk);
      if (vif.arready === 1'b1) break;
      if (++wait_cnt > BUS_TIMEOUT) begin
        `uvm_error("AXIL_DRV",
                   $sformatf("Timeout: ARREADY se ne podize pri citanju %s ni nakon %0d taktova",
                             vj_reg_name(item.addr), BUS_TIMEOUT))
        drive_idle();
        return;
      end
    end
    vif.arvalid <= 1'b0;

    // Namjerno kasnjenje RREADY-ja - slave mora zadrzati RDATA
    repeat (item.r_delay) @(posedge vif.clk);

    vif.rready <= 1'b1;
    wait_cnt = 0;
    forever begin
      @(posedge vif.clk);
      if (vif.rvalid === 1'b1) break;
      if (++wait_cnt > BUS_TIMEOUT) begin
        `uvm_error("AXIL_DRV",
                   $sformatf("Timeout: nema RVALID odgovora na citanje %s ni nakon %0d taktova",
                             vj_reg_name(item.addr), BUS_TIMEOUT))
        drive_idle();
        return;
      end
    end

    // Podatak se vraca u item kako bi ga sekvenca vidjela poslije
    // finish_item() - tako sekvence mogu pollovati CTRL.DONE.
    item.data = vif.rdata;
    item.resp = vif.rresp;

    @(posedge vif.clk);
    vif.rready <= 1'b0;

    `uvm_info("AXIL_DRV", item.convert2string(), UVM_HIGH)
  endtask


  // Hardverski reset. Ovo je jedina tacka u okruzenju koja spusta aresetn,
  // pa monitor moze pouzdano detektovati reset i obavijestiti scoreboard.
  task automatic do_reset(vj_axil_seq_item item);
    int unsigned n;
    n = (item.idle_cycles == 0) ? 10 : item.idle_cycles;

    @(posedge vif.clk);
    vif.aresetn <= 1'b0;
    drive_idle();
    repeat (n) @(posedge vif.clk);
    vif.aresetn <= 1'b1;
    repeat (5) @(posedge vif.clk);

    `uvm_info("AXIL_DRV", item.convert2string(), UVM_MEDIUM)
  endtask


  // Pauza bez magistralne aktivnosti
  task automatic do_idle(vj_axil_seq_item item);
    repeat (item.idle_cycles) @(posedge vif.clk);
  endtask

endclass : vj_axil_driver

`endif
