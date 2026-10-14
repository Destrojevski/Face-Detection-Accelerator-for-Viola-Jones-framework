`ifndef VJ_DEFS_PKG_SV
`define VJ_DEFS_PKG_SV


// vj_defs_pkg.sv
//
// Zajednicke konstante verifikacionog okruzenja. Sve vrijednosti ovdje su
// direktno preslikane iz RTL-a (vj_pkg.vhd, vj_stage_pkg.vhd i zaglavlja
// vj_cascade_v1_0_S00_AXI.vhd) i predstavljaju izvor za
// registarsku mapu i geometriju dizajna unutar testbencha.


package vj_defs_pkg;

  // AXI4-Lite registarska mapa (bajt offseti u odnosu na baznu adresu IP-a)
  parameter bit [5:0] REG_CTRL = 6'h00;  // RW  b0 RESET, b1 START, b2 MODE, b4 DONE(W1tC)
  parameter bit [5:0] REG_X_START = 6'h04;  // RW  x prozora (mod A) / prvi x (mod B)
  parameter bit [5:0] REG_WIDTH = 6'h08;  // RW  sirina tekuce skale (informativno)
  parameter bit [5:0] REG_RESULT = 6'h0C;  // RO  mod A: 1 = lice, -i = odbijen na fazi i
  parameter bit [5:0] REG_X_LAST = 6'h10;  // RW  mod B: posljednji x koji se testira
  parameter bit [5:0] REG_X_STEP = 6'h14;  // RW  mod B: shiftStep
  parameter bit [5:0] REG_HIT_COUNT = 6'h18;  // RO  mod B: broj detekcija
  parameter bit [5:0] REG_HIT_DATA = 6'h1C;  // RO  mod B: x na poziciji HIT_ADDR
  parameter bit [5:0] REG_ROW_BASE = 6'h20;  // RW  rotacija 25 row banaka, 0..24
  parameter bit [5:0] REG_STATUS = 6'h24;  // RO  b0 BUSY
  parameter bit [5:0] REG_HIT_ADDR = 6'h28;  // RW  indeks u hit bufferu

  // Bit maske CTRL registra
  parameter bit [31:0] CTRL_RESET = 32'h0000_0001;  // bit 0, self-clearing
  parameter bit [31:0] CTRL_START = 32'h0000_0002;  // bit 1, self-clearing
  parameter bit [31:0] CTRL_MODE = 32'h0000_0004;  // bit 2, 0 = mod A, 1 = mod B (sweep)
  parameter bit [31:0] CTRL_DONE = 32'h0000_0010;  // bit 4, write-1-to-clear

  parameter int CTRL_BIT_RESET = 0;
  parameter int CTRL_BIT_START = 1;
  parameter int CTRL_BIT_MODE = 2;
  parameter int CTRL_BIT_DONE = 4;


  // Geometrija dizajna (iz vj_pkg.vhd)
  parameter int MAX_IMG_WIDTH = 360;  // najsira skala
  parameter int WIN_SIZE = 24;  // detekcijski prozor 24 x 24
  parameter int INT_ROWS = 25;  // redova integralne slike u kliznom baferu

  parameter int BANK_DEPTH = 512;
  parameter int BANK_AW = 9;
  parameter int BANK_DW = 32;
  parameter int N_INT_BANKS = 25;
  parameter int N_BANKS = 27;  // 25 integralna + 2 kvadrirana
  parameter int SQ0_BANK = 25;  // kvadrirana integralna, logicki red 0
  parameter int SQ23_BANK = 26;  // kvadrirana integralna, logicki red 23

  parameter int COL_W = BANK_AW;  // 9
  parameter int ROW_W = 5;
  parameter int HIT_AW = 9;
  parameter int HIT_DEPTH = 512;

  parameter int NUM_STAGES = 25;
  parameter int NUM_CLASSIFIERS = 2913;


  // AXI4-Lite parametri
  parameter int AXIL_AW = 6;
  parameter int AXIL_DW = 32;

  parameter bit [1:0] RESP_OKAY = 2'b00;


  // Tip transakcije AXI4-Lite agenta
  typedef enum bit [1:0] {
    VJ_WRITE = 2'b00,  // upis u registar
    VJ_READ  = 2'b01,  // citanje registra
    VJ_RESET = 2'b10,  // hardverski reset (aresetn puls)
    VJ_IDLE  = 2'b11   // praznih N taktova, bez magistralne aktivnosti
  } vj_axil_kind_e;


  // Rezim rada jezgra
  typedef enum bit {
    MODE_A_SINGLE = 1'b0,  // jedan prozor
    MODE_B_SWEEP  = 1'b1   // sweep po x osi sa hit bufferom
  } vj_mode_e;


  // Pomocna funkcija: bajt adresa koju AXI BRAM kontroler generise za
  // par(banka, kolona). Adresna rijec je bram_addr_a(15 downto 2), pri cemu
  // bitovi 13..9 biraju banku a 8..0 kolonu.
  function automatic bit [31:0] vj_bram_byte_addr(int bank, int col);
    return 32'((bank * BANK_DEPTH + col) * 4);
  endfunction


  // Naziv registra iz offseta - koristi se u porukama scoreboard-a.
  function automatic string vj_reg_name(bit [5:0] addr);
    case (addr)
      REG_CTRL:      return "CTRL";
      REG_X_START:   return "X_START";
      REG_WIDTH:     return "WIDTH";
      REG_RESULT:    return "RESULT";
      REG_X_LAST:    return "X_LAST";
      REG_X_STEP:    return "X_STEP";
      REG_HIT_COUNT: return "HIT_COUNT";
      REG_HIT_DATA:  return "HIT_DATA";
      REG_ROW_BASE:  return "ROW_BASE";
      REG_STATUS:    return "STATUS";
      REG_HIT_ADDR:  return "HIT_ADDR";
      default:       return $sformatf("UNMAPPED_0x%0h", addr);
    endcase
  endfunction

endpackage : vj_defs_pkg

`endif
