`ifndef VJ_FRAME_CASE_SV
`define VJ_FRAME_CASE_SV

// vj_frame_case.sv
// Kontejner za vektore pune slike (tb_frame.txt). 
// Ovdje se cuva cijela integralna i kvadrirana integralna slika, pa testbench
// za svaku y-poziciju bira redove koje treba upisati.
// Preslikavanje logickih redova na redove slike, izvedeno iz addr_mux procesa
// u vj_datapath.vhd:
//   za y-poziciju y:
//     banke 0..24  <- integralni redovi y .. y+24
//     SQ0_BANK     <- kvadrirani integralni red y
//     SQ23_BANK    <- kvadrirani integralni red y+23


class vj_frame_case extends uvm_object;

  int width;  // broj kolona skale
  int n_int_rows;  // broj redova u fajlu, mora biti >= n_y + 24
  int n_y;  // broj y-pozicija
  int x_start;
  int x_last;
  int x_step;

  // Integralna i kvadrirana integralna slika: [red][kolona]
  bit [31:0] ig[][];
  bit [31:0] sq[][];

  // Zlatni rezultati po y-poziciji
  int win_x[][];  // [y][indeks prozora]
  int win_exp[][];
  int nwin[];  // broj prozora po y-poziciji

  `uvm_object_utils(vj_frame_case)

  function new(string name = "vj_frame_case");
    super.new(name);
  endfunction

  function void allocate_image();
    ig = new[n_int_rows];
    sq = new[n_int_rows];
    foreach (ig[r]) begin
      ig[r] = new[width];
      sq[r] = new[width];
    end
    win_x   = new[n_y];
    win_exp = new[n_y];
    nwin    = new[n_y];
  endfunction

  function void allocate_windows(int y, int n);
    nwin[y]    = n;
    win_x[y]   = new[n];
    win_exp[y] = new[n];
  endfunction


  // Ocekivani RESULT za prozor (y, x). Vraca 1 ako zlatni unos postoji.
  function bit expected_for(int y, int x, output int exp_result);
    exp_result = 0;
    if (y < 0 || y >= n_y) return 1'b0;
    for (int i = 0; i < win_x[y].size(); i++) begin
      if (win_x[y][i] == x) begin
        exp_result = win_exp[y][i];
        return 1'b1;
      end
    end
    return 1'b0;
  endfunction

  // Ocekivani sadrzaj hit buffera za sweep na y-poziciji y.
  function int expected_hits(int y, output int hits[$], output bit complete);
    int x, e;
    hits.delete();
    complete = 1'b1;
    if (x_step == 0 || y < 0 || y >= n_y) begin
      complete = 1'b0;
      return 0;
    end
    for (x = x_start; x <= x_last; x += x_step) begin
      if (!expected_for(y, x, e)) begin
        complete = 1'b0;
        continue;
      end
      if (e == 1) hits.push_back(x);
    end
    return hits.size();
  endfunction

  // Ukupan broj prihvacenih prozora u cijeloj slici.
  function int total_accepts();
    total_accepts = 0;
    for (int y = 0; y < n_y; y++)
    for (int i = 0; i < win_exp[y].size(); i++) if (win_exp[y][i] == 1) total_accepts++;
  endfunction

  function string convert2string();
    return $sformatf(
        "frame: width=%0d int_rows=%0d n_y=%0d sweep x=%0d..%0d korak %0d, ukupno prihvacenih %0d",
        width,
        n_int_rows,
        n_y,
        x_start,
        x_last,
        x_step,
        total_accepts()
    );
  endfunction

endclass : vj_frame_case

`endif
