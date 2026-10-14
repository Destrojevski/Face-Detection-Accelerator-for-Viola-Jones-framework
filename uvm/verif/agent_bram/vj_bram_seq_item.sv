`ifndef VJ_BRAM_SEQ_ITEM_SV
`define VJ_BRAM_SEQ_ITEM_SV

//
// vj_bram_seq_item.sv
//
// Jedan upis rijeci u row banke kroz BRAM_PORTA. U realnom sistemu ovim
// portom upravlja AXI BRAM kontroler, koji generise BYTE adresu; dizajn iz nje
// dekoduje adresnu rijec bram_addr_a(15 downto 2), gdje bitovi 13..9 biraju
// banku (0..24 integralna slika, 25 = kvadrirana red 0, 26 = kvadrirana red
// 23), a bitovi 8..0 biraju kolonu.
//
// Item cuva banku i kolonu odvojeno, a driver racuna byte adresu. Time je
// adresna putanja koju verifikujemo eksplicitno vidljiva u transakciji, pa
// monitor i scoreboard mogu provjeriti da li rijec zaista stize u banku i
// kolonu koje su trazene.
//

class vj_bram_seq_item extends uvm_sequence_item;

  rand bit [ 4:0] bank;  // 0..26
  rand bit [ 8:0] col;  // 0..511
  rand bit [31:0] data;
  rand bit [ 3:0] we;
  rand bit        en;

  // Popunjava driver / monitor: byte adresa koja je zaista bila na magistrali
  bit      [31:0] byte_addr;

  `uvm_object_utils_begin(vj_bram_seq_item)
    `uvm_field_int(bank, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(col, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(data, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(we, UVM_DEFAULT | UVM_BIN)
    `uvm_field_int(en, UVM_DEFAULT | UVM_BIN)
    `uvm_field_int(byte_addr, UVM_DEFAULT | UVM_HEX)
  `uvm_object_utils_end

  function new(string name = "vj_bram_seq_item");
    super.new(name);
  endfunction

  constraint c_bank_legal {bank < N_BANKS;}
  constraint c_col_legal {col < MAX_IMG_WIDTH;}
  constraint c_write {
    soft en == 1'b1;
    soft we == 4'hF;
  }

  function string convert2string();
    return $sformatf(
        "BRAM WRITE bank=%0d col=%0d data=%0d (0x%08h) @byte 0x%05h",
        bank,
        col,
        $signed(
            data
        ),
        data,
        byte_addr
    );
  endfunction

endclass : vj_bram_seq_item

`endif
