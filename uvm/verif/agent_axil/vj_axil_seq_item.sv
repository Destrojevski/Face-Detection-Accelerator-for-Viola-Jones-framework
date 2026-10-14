`ifndef VJ_AXIL_SEQ_ITEM_SV
`define VJ_AXIL_SEQ_ITEM_SV


// vj_axil_seq_item.sv
//
// Atomska transakcija na AXI4-Lite magistrali. Jedan item je jedan upis, jedno
// citanje, jedan reset puls ili pauza od N taktova.
//
// Polja kasnjenja (aw_delay, w_delay, b_delay, r_delay) postoje zato sto slave
// u dizajnu podize AWREADY tek kada su AWVALID i WVALID istovremeno visoki, i
// zato sto BVALID/RVALID moraju ostati postavljeni dok ih master ne prihvati.
// Randomizacijom ovih kasnjenja provjerava se da slave ne pretpostavlja da
// adresa i podaci uvijek stizu zajedno niti da su BREADY/RREADY stalno visoki.


class vj_axil_seq_item extends uvm_sequence_item;


  // Ono sto se implementira

  rand vj_axil_kind_e               kind;


  // Adresa i podaci. Kod citanja driver upisuje procitanu vrijednost nazad u
  // polje data, pa je sekvenca vidi poslije finish_item().
  rand bit            [AXIL_AW-1:0] addr;
  rand bit            [AXIL_DW-1:0] data;
  rand bit            [        3:0] strb;

  // Timing varijacije handshake-a (u taktovima)
  rand int unsigned                 aw_delay;  // koliko poslije starta se podize AWVALID
  rand int unsigned                 w_delay;  // koliko poslije starta se podize WVALID
  rand int unsigned                 b_delay;  // koliko se ceka prije podizanja BREADY
  rand int unsigned                 r_delay;  // koliko se ceka prije podizanja RREADY

  // Broj praznih taktova za kind == VJ_IDLE, odnosno trajanje reset pulsa
  // za kind == VJ_RESET
  rand int unsigned                 idle_cycles;

  // Odgovor koji je slave vratio (popunjava driver / monitor)
  bit                 [        1:0] resp;

  `uvm_object_utils_begin(vj_axil_seq_item)
    `uvm_field_enum(vj_axil_kind_e, kind, UVM_DEFAULT)
    `uvm_field_int(addr, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(data, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(strb, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(aw_delay, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(w_delay, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(b_delay, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(r_delay, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(idle_cycles, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(resp, UVM_DEFAULT | UVM_HEX)
  `uvm_object_utils_end

  function new(string name = "vj_axil_seq_item");
    super.new(name);
  endfunction

  // Podrazumijevano se generisu samo upisi i citanja - reset i pauza se
  // ubacuju eksplicitno iz sekvenci.
  constraint c_kind_default {soft kind inside {VJ_WRITE, VJ_READ};}

  // Randomizovani pristupi gadjaju samo implementirane registre. Adresa mora
  // biti poravnata na 4 bajta jer slave dekoduje awaddr(5 downto 2).
  constraint c_addr_legal {
    soft addr inside {REG_CTRL, REG_X_START, REG_WIDTH, REG_RESULT,
                          REG_X_LAST, REG_X_STEP, REG_HIT_COUNT, REG_HIT_DATA,
                          REG_ROW_BASE, REG_STATUS, REG_HIT_ADDR};
    addr[1:0] == 2'b00;
  }

  // Kasnjenja drzimo dovoljno malim da simulacija ostane upotrebljivo brza, ali
  // dovoljno velikim da pokrije sve smjerove handshake-a.
  constraint c_delays {
    aw_delay inside {[0 : 4]};
    w_delay inside {[0 : 4]};
    b_delay inside {[0 : 4]};
    r_delay inside {[0 : 4]};
    // bar jedan kanal krece odmah, inace samo gubimo taktove
    (aw_delay == 0) || (w_delay == 0);
  }

  constraint c_idle {idle_cycles inside {[1 : 8]};}

  constraint c_strb {soft strb == 4'hF;}

  function string convert2string();
    case (kind)
      VJ_WRITE:
      return $sformatf(
          "WRITE %-9s (0x%02h) <= 0x%08h  [aw=%0d w=%0d b=%0d]",
          vj_reg_name(
              addr
          ),
          addr,
          data,
          aw_delay,
          w_delay,
          b_delay
      );
      VJ_READ:
      return $sformatf(
          "READ  %-9s (0x%02h) => 0x%08h  [r=%0d]", vj_reg_name(addr), addr, data, r_delay
      );
      VJ_RESET: return $sformatf("RESET puls, %0d taktova", idle_cycles);
      VJ_IDLE: return $sformatf("IDLE %0d taktova", idle_cycles);
      default: return "UNKNOWN";
    endcase
  endfunction

endclass : vj_axil_seq_item

`endif
