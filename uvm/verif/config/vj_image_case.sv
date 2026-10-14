`ifndef VJ_IMAGE_CASE_SV
`define VJ_IMAGE_CASE_SV


// vj_image_case.sv
// Jedan test slucaj iz fajla zlatnih vektora (tb_vectors.txt/tb_vectors_small.txt).Sadrzi ulazne
// podatke koje treba upisati u row banke i zlatne (ocekivane) rezultate koje
// scoreboard koristi za automatsku provjeru.
// Format fajla:
//
//   <n_cases>
//   za svaki slucaj:
//     <width> <nwin>
//     25 * width linija   - redovi integralne slike, red po red
//     width linija        - kvadrirana integralna slika, logicki red 0
//     width linija        - kvadrirana integralna slika, logicki red 23
//     nwin linija: "<x> <expected>"
//
// Kodovanje ocekivanog rezultata je isto kao u RESULT registru:
//     1  - prozor prihvacen (lice)
//     0  - odbijen na fazi 0
//    -i  - odbijen na fazi i


class vj_image_case extends uvm_object;

  int unsigned case_id;  // redni broj slucaja, baza 1
  int width;  // sirina skale (broj kolona koje se pune)
  int nwin;  // broj prozora sa zlatnim rezultatom

  // Ulazni podaci
  int ig[][];  // [red 0..24][kolona 0..width-1] integralna slika
  int sq0[];  // kvadrirana integralna, logicki red 0
  int sq23[];  // kvadrirana integralna, logicki red 23

  // Zlatni vektori
  int win_x[];  // x koordinata prozora
  int win_exp[];  // ocekivana vrijednost RESULT registra

  `uvm_object_utils(vj_image_case)

  function new(string name = "vj_image_case");
    super.new(name);
  endfunction


  // Alokacija nizova nakon sto su width i nwin poznati.
  function void allocate();
    ig = new[INT_ROWS];
    foreach (ig[r]) ig[r] = new[width];
    sq0     = new[width];
    sq23    = new[width];
    win_x   = new[nwin];
    win_exp = new[nwin];
  endfunction


  // Ocekivani RESULT za prozor na koordinati x.
  // Vraca 1 ako u zlatnim vektorima postoji unos za taj x, inace 0.
  function bit expected_for_x(int x, output int exp_result);
    foreach (win_x[i]) begin
      if (win_x[i] == x) begin
        exp_result = win_exp[i];
        return 1'b1;
      end
    end
    exp_result = 0;
    return 1'b0;
  endfunction

  // Ocekivani sadrzaj hit buffera za sweep od x_start do x_last korakom
  // x_step. Vraca broj pogodaka, a listu x koordinata upisuje u hits.
  // Sweep koji dodje do x koji nema zlatni unos se preskace - takav sweep
  // scoreboard ne provjerava (pogledati vj_scoreboard.sv).

  function int expected_hits(int x_start, int x_last, int x_step, output int hits[$],
                             output bit complete);
    int x;
    int e;
    hits.delete();
    complete = 1'b1;
    if (x_step == 0) begin
      complete = 1'b0;
      return 0;
    end
    for (x = x_start; x <= x_last; x += x_step) begin
      if (!expected_for_x(x, e)) begin
        complete = 1'b0;  // nemamo zlatni podatak za ovaj prozor
        continue;
      end
      if (e == 1) hits.push_back(x);
    end
    return hits.size();
  endfunction


  // Broj prozora koje zlatni vektori proglasavaju licem.
  function int num_accepts();
    num_accepts = 0;
    foreach (win_exp[i]) if (win_exp[i] == 1) num_accepts++;
  endfunction

  function string convert2string();
    return
        $sformatf("case %0d: width=%0d nwin=%0d accepts=%0d", case_id, width, nwin, num_accepts());
  endfunction

endclass : vj_image_case

`endif
