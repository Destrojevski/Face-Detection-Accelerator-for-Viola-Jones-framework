`ifndef VJ_BRAM_MONITOR_SV
`define VJ_BRAM_MONITOR_SV

//
// vj_bram_monitor.sv
//
// Posmatra BRAM_PORTA i rekonstruise (banka, kolona, podatak) iz byte adrese
// koja je zaista bila na magistrali. To je bitno jer je adresna putanja jedno
// od mjesta gdje dizajn moze tiho otkazati: banka 26 zahtijeva bit 15 bajt
// adrese, pa dekoder koji je uzi od potrebnog ne bi mogao adresirati gornje
// banke, a simulacija bi i dalje "radila".
//
// Monitor takodje provjerava da se u row banke ne pise dok je jezgro zauzeto -
// port A je dijeljen izmedju ove upisne putanje i col0 citanja jezgra, pa je
// preklapanje kvarenje podataka koje se tesko uocava u talasnim oblicima.
//

class vj_bram_monitor extends uvm_monitor;

  `uvm_component_utils(vj_bram_monitor)

  virtual vj_if                         vif;
  vj_config                             cfg;

  uvm_analysis_port #(vj_bram_seq_item) ap;

  // Promjenljive koje covergroup sampluje
  int                                   cov_bank;
  int                                   cov_col;
  int                                   cov_we;

  // Broj upisa i broj upisa koji su se desili dok je jezgro bilo zauzeto
  int unsigned                          n_writes         = 0;
  int unsigned                          n_writes_in_busy = 0;


  // Pokrivenost adresne putanje

  covergroup cg_bram_write;
    option.per_instance = 1;
    option.name = "cg_bram_write";

    // Sve tri klase banaka moraju biti pogodjene, ukljucujuci obje banke
    // kvadrirane integralne slike koje su fizicki na vrhu adresnog opsega.
    cp_bank: coverpoint cov_bank {
      bins int_row[] = {[0 : N_INT_BANKS - 1]};
      bins sq_row0 = {SQ0_BANK};
      bins sq_row23 = {SQ23_BANK};
    }

    // Kolone: pokrivamo pocetak, sredinu i kraj najsire skale.
    cp_col: coverpoint cov_col {
      bins first = {0};
      bins low = {[1 : 88]};
      bins mid = {[89 : 230]};
      bins high = {[231 : MAX_IMG_WIDTH - 2]};
      bins last = {MAX_IMG_WIDTH - 1};
    }

    cp_we: coverpoint cov_we {bins full_word = {4'hF};}

    // cross-confirm da smo u svakoj klasi banaka dosli i do visokih
    // kolona, tj. da adresni dekoder radi na cijelom opsegu.
    x_bank_col : cross cp_bank, cp_col;
  endgroup

  function new(string name = "vj_bram_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
    cg_bram_write = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual vj_if)::get(this, "", "vj_if", vif))
      `uvm_fatal("NOVIF", {"Virtuelni interfejs mora biti postavljen za ", get_full_name(), ".vif"})
    if (!uvm_config_db#(vj_config)::get(this, "", "vj_config", cfg))
      `uvm_fatal("NOCFG", {"Config objekat mora biti postavljen za ", get_full_name(), ".cfg"})
  endfunction

  task run_phase(uvm_phase phase);
    vj_bram_seq_item item;
    bit [13:0] word_addr;

    forever begin
      @(posedge vif.clk);

      if (vif.bram_en === 1'b1 && vif.bram_we !== 4'h0) begin

        item           = vj_bram_seq_item::type_id::create("bram_item");

        // Dekodovanje identicno onome u dizajnu:
        //   adresna rijec = bram_addr_a(15 downto 2)
        //   banka         = adresna rijec (13 downto 9)
        //   kolona        = adresna rijec (8 downto 0)
        word_addr      = vif.bram_addr[15:2];
        item.byte_addr = vif.bram_addr;
        item.bank      = word_addr[13:9];
        item.col       = word_addr[8:0];
        item.data      = vif.bram_wrdata;
        item.we        = vif.bram_we;
        item.en        = vif.bram_en;

        n_writes++;

        cov_bank = item.bank;
        cov_col  = item.col;
        cov_we   = item.we;
        cg_bram_write.sample();

        `uvm_info("BRAM_MON", item.convert2string(), UVM_FULL)
        ap.write(item);
      end
    end
  endtask


  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("BRAM_MON", $sformatf("Ukupno upisa u row banke: %0d", n_writes), UVM_LOW)
  endfunction

endclass : vj_bram_monitor

`endif
