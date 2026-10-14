`ifndef VJ_AXIL_MONITOR_SV
`define VJ_AXIL_MONITOR_SV


// vj_axil_monitor.sv
// Pasivna komponenta. Rekonstruise upise i citanja sa AXI4-Lite magistrale i
// salje ih scoreboard-u, i skuplja funkcionalnu pokrivenost registarskog i
// protokolarnog dijela dizajna.
//
// Tri nezavisne niti:
//   - collect_writes : hvata trenutak kada slave prihvati adresu i podatak
//                      (AWREADY & AWVALID & WREADY & WVALID), zatim ceka
//                      BVALID/BREADY handshake da bi pokupio BRESP
//   - collect_reads  : hvata ARVALID/ARREADY, pa RVALID/RREADY sa RDATA
//   - watch_reset    : detektuje pad aresetn i o tome obavjestava scoreboard
//
// Konvencija za sampling: sve komponente citaju signale interfejsa odmah nakon
// @(posedge clk), sto zbog neblokirajucih dodjela u DUT-u i driveru daje
// vrijednosti kakve su bile neposredno prije te ivice.


class vj_axil_monitor extends uvm_monitor;

  `uvm_component_utils(vj_axil_monitor)

  virtual vj_if vif;
  vj_config cfg;

  uvm_analysis_port #(vj_axil_seq_item) ap;

  // Promjenljive koje covergroup-e sampluju. Postavljaju se neposredno prije
  // poziva sample() - ovaj pristup je portabilan izmedju xsim-a i Xcelium-a.
  bit [AXIL_AW-1:0] cov_addr;
  bit [AXIL_DW-1:0] cov_data;
  int cov_sdata;  // isti podatak interpretiran kao signed
  bit [1:0] cov_resp;
  int cov_order;  // 0 = adresa prva, 1 = istovremeno, 2 = podatak prvi
  int cov_bdelayed;  // 1 ako je BREADY kasnio za BVALID
  int cov_rdelayed;  // 1 ako je RREADY kasnio za RVALID

  // Pokrivenost upisa u registre
  covergroup cg_axil_write;
    option.per_instance = 1;
    option.name = "cg_axil_write";

    cp_waddr: coverpoint cov_addr {
      bins ctrl = {REG_CTRL};
      bins x_start = {REG_X_START};
      bins width = {REG_WIDTH};
      bins x_last = {REG_X_LAST};
      bins x_step = {REG_X_STEP};
      bins row_base = {REG_ROW_BASE};
      bins hit_addr = {REG_HIT_ADDR};
      // upisi u read-only registre moraju biti bez efekta
      bins ro_write = {REG_RESULT, REG_HIT_COUNT, REG_HIT_DATA, REG_STATUS};
    }

    // Redoslijed podizanja AWVALID i WVALID. Slave podize READY tek kada su
    // oba visoka, pa sva tri slucaja moraju biti provjerena.
    cp_order: coverpoint cov_order {
      bins addr_first = {0}; bins together = {1}; bins data_first = {2};
    }

    // Slave mora zadrzati BVALID dok master ne podigne BREADY.
    cp_bready: coverpoint cov_bdelayed {
      bins immediate = {0}; bins delayed = {1};
    }

    cp_bresp: coverpoint cov_resp {
      bins okay = {2'b00}; illegal_bins not_okay = {2'b01, 2'b10, 2'b11};
    }

    x_waddr_order : cross cp_waddr, cp_order;
  endgroup

  // Pokrivenost sadrzaja CTRL registra - sampluje se samo pri upisu u CTRL
  covergroup cg_ctrl_write;
    option.per_instance = 1;
    option.name = "cg_ctrl_write";

    cp_reset: coverpoint cov_data[CTRL_BIT_RESET] {bins no = {0}; bins yes = {1};}
    cp_start: coverpoint cov_data[CTRL_BIT_START] {bins no = {0}; bins yes = {1};}
    cp_mode: coverpoint cov_data[CTRL_BIT_MODE] {bins mode_a = {0}; bins mode_b = {1};}
    cp_done_clr: coverpoint cov_data[CTRL_BIT_DONE] {bins no = {0}; bins yes = {1};}
    // Pokretanje u oba rezima rada mora biti pokriveno
    x_start_mode : cross cp_start, cp_mode{
      bins run_mode_a = binsof (cp_start.yes) && binsof (cp_mode.mode_a);
      bins run_mode_b = binsof (cp_start.yes) && binsof (cp_mode.mode_b);
    }
  endgroup


  // Pokrivenost vrijednosti upisanih u parametarske registre
  covergroup cg_params_write;
    option.per_instance = 1;
    option.name = "cg_params_write";

    // ROW_BASE je 5-bitni u jezgru; vrijednost preko 24 mora biti odsjecena
    cp_row_base: coverpoint cov_data[31:0] iff (cov_addr == REG_ROW_BASE) {
      bins zero = {0};
      bins low = {[1 : 11]};
      bins high = {[12 : 24]};
      bins over_range = {[25 : 32'hFFFF_FFFF]};
    }

    cp_x_step: coverpoint cov_data[31:0] iff (cov_addr == REG_X_STEP) {
      bins one = {1};
      bins step_small = {[2 : 3]};
      bins step_medium = {[4 : 23]};
      bins step_window = {WIN_SIZE};
      bins step_large = {[WIN_SIZE + 1 : 32'hFFFF_FFFF]};
    }

    cp_x_start: coverpoint cov_data[31:0] iff (cov_addr == REG_X_START) {
      bins zero = {0}; bins low = {[1 : 63]}; bins mid = {[64 : 199]}; bins high = {[200 : 511]};
    }
  endgroup


  // Pokrivenost citanja

  covergroup cg_axil_read;
    option.per_instance = 1;
    option.name = "cg_axil_read";

    cp_raddr: coverpoint cov_addr {
      bins ctrl = {REG_CTRL};
      bins x_start = {REG_X_START};
      bins width = {REG_WIDTH};
      bins result = {REG_RESULT};
      bins x_last = {REG_X_LAST};
      bins x_step = {REG_X_STEP};
      bins hit_count = {REG_HIT_COUNT};
      bins hit_data = {REG_HIT_DATA};
      bins row_base = {REG_ROW_BASE};
      bins status = {REG_STATUS};
      bins hit_addr = {REG_HIT_ADDR};
    }

    // Slave mora zadrzati RDATA dok master ne podigne RREADY.
    cp_rready: coverpoint cov_rdelayed {
      bins immediate = {0}; bins delayed = {1};
    }

    cp_rresp: coverpoint cov_resp {
      bins okay = {2'b00}; illegal_bins not_okay = {2'b01, 2'b10, 2'b11};
    }
  endgroup


  // Pokrivenost rezultata koje dizajn vraca. Ovo je funkcionalna pokrivenost
  // samog algoritma, ne magistrale: da li smo vidjeli prihvacen prozor, i u
  // kojim se sve fazama kaskade prozori odbacuju.
  covergroup cg_result;
    option.per_instance = 1;
    option.name = "cg_result";

    cp_result: coverpoint cov_sdata iff (cov_addr == REG_RESULT) {
      bins accept = {1};
      bins reject_st0 = {0};
      bins reject_early = {[-4 : -1]};
      bins reject_mid = {[-12 : -5]};
      bins reject_late = {[-24 : -13]};
    }

    cp_hit_count: coverpoint cov_sdata iff (cov_addr == REG_HIT_COUNT) {
      bins none = {0};
      bins one = {1};
      bins few = {[2 : 4]};
      bins many = {[5 : 32]};
      bins lots = {[33 : HIT_DEPTH]};
    }

    cp_busy: coverpoint cov_data[0] iff (cov_addr == REG_STATUS) {bins idle = {0}; bins busy = {1};}

    cp_done: coverpoint cov_data[CTRL_BIT_DONE] iff (cov_addr == REG_CTRL) {
      bins clear = {0}; bins set = {1};
    }

    cp_mode_rb: coverpoint cov_data[CTRL_BIT_MODE] iff (cov_addr == REG_CTRL) {
      bins mode_a = {0}; bins mode_b = {1};
    }
  endgroup

  function new(string name = "vj_axil_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap              = new("ap", this);
    cg_axil_write   = new();
    cg_ctrl_write   = new();
    cg_params_write = new();
    cg_axil_read    = new();
    cg_result       = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual vj_if)::get(this, "", "vj_if", vif))
      `uvm_fatal("NOVIF", {"Virtuelni interfejs mora biti postavljen za ", get_full_name(), ".vif"})
    if (!uvm_config_db#(vj_config)::get(this, "", "vj_config", cfg))
      `uvm_fatal("NOCFG", {"Config objekat mora biti postavljen za ", get_full_name(), ".cfg"})
  endfunction

  task run_phase(uvm_phase phase);
    fork
      collect_writes();
      collect_reads();
      watch_reset();
    join
  endtask

  // Upisi
  task automatic collect_writes();
    vj_axil_seq_item item;
    int order;
    int bdelayed;

    forever begin
      // Cekamo pocetak neke write transakcije
      do @(posedge vif.clk); while (!(vif.awvalid === 1'b1 || vif.wvalid === 1'b1));

      // Klasifikacija redoslijeda kanala
      if (vif.awvalid === 1'b1 && vif.wvalid === 1'b1) order = 1;  // istovremeno
      else if (vif.awvalid === 1'b1) order = 0;  // adresa prva
      else order = 2;  // podatak prvi

      item = vj_axil_seq_item::type_id::create("axil_wr_item");
      item.kind = VJ_WRITE;

      // Cekamo takt u kome slave prihvata i adresu i podatak
      while (!(vif.awvalid === 1'b1 && vif.awready === 1'b1 &&
                     vif.wvalid  === 1'b1 && vif.wready  === 1'b1)) begin
        @(posedge vif.clk);
      end

      item.addr = vif.awaddr;
      item.data = vif.wdata;
      item.strb = vif.wstrb;

      // BVALID/BREADY handshake, uz biljezenje da li je BREADY kasnio
      bdelayed  = 0;
      @(posedge vif.clk);
      while (!(vif.bvalid === 1'b1 && vif.bready === 1'b1)) begin
        if (vif.bvalid === 1'b1 && vif.bready !== 1'b1) bdelayed = 1;
        @(posedge vif.clk);
      end
      item.resp    = vif.bresp;

      // Pokrivenost
      cov_addr     = item.addr;
      cov_data     = item.data;
      cov_sdata    = $signed(item.data);
      cov_resp     = item.resp;
      cov_order    = order;
      cov_bdelayed = bdelayed;

      cg_axil_write.sample();
      cg_params_write.sample();
      if (item.addr == REG_CTRL) cg_ctrl_write.sample();

      `uvm_info("AXIL_MON", item.convert2string(), UVM_HIGH)
      ap.write(item);
    end
  endtask

  // Citanja
  task automatic collect_reads();
    vj_axil_seq_item item;
    bit [AXIL_AW-1:0] captured_addr;
    int rdelayed;

    forever begin
      // ARVALID/ARREADY handshake
      do @(posedge vif.clk); while (!(vif.arvalid === 1'b1 && vif.arready === 1'b1));

      captured_addr = vif.araddr;

      item = vj_axil_seq_item::type_id::create("axil_rd_item");
      item.kind = VJ_READ;
      item.addr = captured_addr;

      // RVALID/RREADY handshake
      rdelayed = 0;
      @(posedge vif.clk);
      while (!(vif.rvalid === 1'b1 && vif.rready === 1'b1)) begin
        if (vif.rvalid === 1'b1 && vif.rready !== 1'b1) rdelayed = 1;
        @(posedge vif.clk);
      end

      item.data        = vif.rdata;
      item.resp        = vif.rresp;

      // irq linija je direktno spojena na CTRL.DONE u dizajnu, pa je
      // samplujemo uz svaku transakciju i saljemo scoreboard-u.
      item.idle_cycles = (vif.irq === 1'b1) ? 1 : 0;

      cov_addr         = item.addr;
      cov_data         = item.data;
      cov_sdata        = $signed(item.data);
      cov_resp         = item.resp;
      cov_rdelayed     = rdelayed;

      cg_axil_read.sample();
      cg_result.sample();

      `uvm_info("AXIL_MON", item.convert2string(), UVM_HIGH)
      ap.write(item);
    end
  endtask


  // Reset. Scoreboard na osnovu ovoga vraca shadow model registara na
  // reset vrijednosti.

  task automatic watch_reset();
    vj_axil_seq_item item;
    bit prev;

    prev = 1'b1;
    forever begin
      @(posedge vif.clk);
      if (prev === 1'b1 && vif.aresetn === 1'b0) begin
        item = vj_axil_seq_item::type_id::create("axil_rst_item");
        item.kind = VJ_RESET;
        `uvm_info("AXIL_MON", "Detektovan pad aresetn", UVM_MEDIUM)
        ap.write(item);
      end
      prev = vif.aresetn;
    end
  endtask

endclass : vj_axil_monitor

`endif
