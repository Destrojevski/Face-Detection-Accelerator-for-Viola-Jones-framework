/*
/Naziv fajla: vj_testbench.cpp
/Opis fajla: HLS testbench za Viola-Jones IP jezgro.
/Cita tri fajla koji predstavljaju fajlove sa vrijednostima za testiranje ispravnog rada IP bloka
/bram_file.txt - 52484 BRAM vrijednosti
/ddr3_snapshots.txt  - "snimci" DDR3 sadrzaja za svaki y_bias korak
/test_vectors.txt - format: snapshot_id p_offset width result
/Datum: 23/3/2026
/Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/
#include <iostream>
#include <fstream>
#include <vector>
#include "ap_int.h"
#include "vj_core.h"
using namespace std;
#define HW_COSIM
// Globalni podaci
ap_int<16> bram[BRAM_SIZE];

// Svaki snimak: width vrijednosti int_img + width vrijednosti sq_int
// Cuva se kao struktura (vektor vektora) za lak pristup po snapshot_id
struct DDR3Snapshot{
int width;
int count;// 25 * width
vector<int> int_img;
vector<int> sq_int;
};
vector<DDR3Snapshot> snapshots;

// load_bram (ucitavanje podataka u bram)
void load_bram(const string& filename){
ifstream file(filename);
if(!file){ 
cerr << "Ne mogu otvoriti: " << filename << endl;
return;
}
int value;
for(int i = 0; i < BRAM_SIZE; i++){
    file >> value;
    bram[i] = (ap_int<16>)value;
    if(file.peek() == ',') file.ignore();
    }
    file.close();
    cout << "BRAM ucitan: " << BRAM_SIZE << " lokacija." << endl;
}
/*
/load_snapshots
/Ucitava DDR3 snimke iz ddr3_snapshots.txt u memoriju.
/Fajl je relativno mali (oko 100 MB) pa se moze ucitati odjednom.
*/
void load_snapshots(const string& filename)
{
ifstream file(filename);
if(!file){
	cerr << "Ne mogu otvoriti: " << filename << endl;
	return;
    }
while(file.peek() != EOF){
    DDR3Snapshot snap;
    if(!(file >> snap.width >> snap.count)) break;
    snap.int_img.resize(snap.count);
    snap.sq_int.resize(snap.count);
    for(int k = 0; k < snap.count; k++) file >> snap.int_img[k];
    for(int k = 0; k < snap.count; k++) file >> snap.sq_int[k];
    snapshots.push_back(snap);
    }
    file.close();
    cout << "DDR3 snimci ucitani: " << snapshots.size() << " snimaka." << endl;
}
// build_ddr3_for_snapshot
// Popunjava ddr3[] niz za dati snapshot_id.
// Vrijednosti izvan zadatog counta se postavljaju na 0.
void build_ddr3_for_snapshot(int snap_id, ap_int<32> ddr3[DDR3_TOTAL_SIZE]){
    // Nuliranje cijelog niza
    for(int k = 0; k < DDR3_TOTAL_SIZE; k++) ddr3[k] = 0;
    if(snap_id < 0 || snap_id >= (int)snapshots.size()) return;
    const DDR3Snapshot& snap = snapshots[snap_id];
    for(int k = 0; k < snap.count; k++)
    ddr3[k] = (ap_int<32>)snap.int_img[k];
    for(int k = 0; k < snap.count; k++)
    ddr3[9000 + k] = (ap_int<32>)snap.sq_int[k];
}
// main
int main(int argc, char** argv){
    load_bram("bram_file.txt");
    load_snapshots("ddr3_snapshots.txt");
    ifstream vec_file("test_vectors.txt");
    if(!vec_file) {
	cerr << "Ne mogu otvoriti test_vectors.txt" << endl;
	return 1;
	}
    ap_uint<8> cfg_val= ap_uint<8>(0);
    bool ip_interrupt = false;
    ap_int<32> result = 0;
    int err_cnt = 0;
    int win = 0;
    // Reset IP-a
    {
    ap_int<32> dummy[DDR3_TOTAL_SIZE];
    for(int i = 0; i < DDR3_TOTAL_SIZE; i++) dummy[i] = 0;
    cfg_val = ap_uint<8>(0);
    cfg_val.set(IP_RESET_BIT, 1);
    #ifdef HW_COSIM
    top_function(&cfg_val, 0, 0, bram, dummy, &ip_interrupt, &result);
    #endif
    }
    cfg_val = ap_uint<8>(0);
    cout << "Reset gotov. Pocinjem testiranje..." << endl;
    int snap_id, p_off, w, exp_res;
    int prev_snap_id = -1;
    ap_int<32> ddr3[DDR3_TOTAL_SIZE];
    while(vec_file >> snap_id >> p_off >> w >> exp_res){
    // Popuni DDR3 samo kada se snapshot promijeni
    // (svi prozori iste y_bias iteracije dijele isti snimak)
    if(snap_id != prev_snap_id){
        build_ddr3_for_snapshot(snap_id, ddr3);
        prev_snap_id = snap_id;
        }
        cfg_val = ap_uint<8>(0);
        cfg_val.set(IP_START_BIT, 1);
        #ifdef HW_COSIM
        top_function(&cfg_val, (ap_uint<32>)p_off, (ap_uint<32>)w,bram, ddr3, &ip_interrupt, &result);
        #endif
        if(ip_interrupt && cfg_val[IP_DONE_BIT])
        {
        if(result.to_int() != exp_res){
                cout << "GRESKA prozor " << win
                     << " snap=" << snap_id
                     << " p_off=" << p_off << " w=" << w
                     << " dobijeno=" << result.to_int()
                     << " ocekivano=" << exp_res << endl;
                err_cnt++;
        }
            cfg_val.set(IP_DONE_BIT, 0);
            cfg_val.set(IP_START_BIT, 0);
        }
        else {
            cerr << "UPOZORENJE: prozor " << win << " nije vratio DONE!" << endl;
            err_cnt++;
        }
        win++;
        if(win % 1000 == 0) cout << "Testirano " << win << " prozora..." << endl;
    }
    vec_file.close();
    cout << "\n-- Testiranje zavrseno --" << endl;
    cout << "Ukupno prozora: " << win << endl;
    if(err_cnt)
        cout << "GRESKA: " << err_cnt << " neslaganja!" << endl;
    else
        cout << "Test prosao. Nema neslaganja." << endl;

    return err_cnt;
}
