/*
/ Naziv fajla: bram_mem.cpp
/ Opis fajla: Implementacija BRAM modula. Ucitava staticne klasifikacione podatke iz .dat fajlova i modeluje TLM komunikaciju ka Interconnect i IP modulima.
/ Datum : 11/02/2025
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/
#include "bram_mem.hpp"
#include "vp_addr.hpp"
#include <tlm>

using namespace sc_core;
using namespace sc_dt;
using namespace std;
using namespace tlm;

/*
/ Naziv funkcije: load_bram_data
/ Parametri: nema
/ Povratna vrednost: nema
/ Opis funkcije: Ucitava sve staticne klasifikacione podatke iz .dat fajlova u BRAM memoriju. Redosled ucitavanja odgovara lokalnom rasporedu
/ definisanom u ip_consts.hpp i vp_addr.hpp. Akcija se smatra besplatnom u simulacionom vremenu.
*/
void bram_mem::load_bram_data()
{
    // Inicijalizacija cele memorije na nulu
    for(int i = 0; i < BRAM_SIZE; i++)
        mem[i] = 0;

    /* 1. rectangles_array: 34956 char vrednosti, geometrija Haarovih karakteristika (x, y, w, h za svaki pravougaonik), lokalna adresa: VP_ADDR_BRAM_RECT (= 0) */
    {
        ifstream f("../data/rectangles_array.dat");
        if(!f.is_open()) {
            SC_REPORT_ERROR("BRAM", "Nije moguce otvoriti rectangles_array.dat");
            return;
        }
        uint32_t idx = (uint32_t)VP_ADDR_BRAM_RECT;
        string line, val_str;
        while(getline(f, line)) {
            istringstream ss(line);
            while(getline(ss, val_str, ',')) {
                if(idx >= VP_ADDR_BRAM_STAGES) break;
                unsigned int v = 0;
                istringstream(val_str) >> v;
                mem[idx++] = (short int)(char)v;
            }
        }
        f.close();
        cout << "BRAM: ucitano rectangles_array (" << idx << " lokacija)\n";
    }

    /* 2. stages_array: 25 uint8 vrednosti, broj slabih klasifikatora po fazi kaskade, lokalna adresa: VP_ADDR_BRAM_STAGES */
    {
        ifstream f("../data/stages_array.dat");
        if(!f.is_open()) {
            SC_REPORT_ERROR("BRAM", "Nije moguce otvoriti stages_array.dat");
            return;
        }
        uint32_t idx = (uint32_t)VP_ADDR_BRAM_STAGES;
        string line, val_str;
        while(getline(f, line)) {
            istringstream ss(line);
            while(getline(ss, val_str, ',')) {
                if(idx >= VP_ADDR_BRAM_STAGES + BRAM_STAGES_SIZE) break;
                unsigned int v = 0;
                istringstream(val_str) >> v;
                mem[idx++] = (short int)(uint8_t)v;
            }
        }
        f.close();
        cout << "BRAM: ucitano stages_array (" << BRAM_STAGES_SIZE << " lokacija)\n";
    }

    /* 3. stages_thresh_array: 25 short int vrednosti, pragovi za odlucivanje na nivou faze, lokalna adresa: VP_ADDR_BRAM_STAGES_TH */
    {
        ifstream f("../data/stages_thresh_array.dat");
        if(!f.is_open()) {
            SC_REPORT_ERROR("BRAM", "Nije moguce otvoriti stages_thresh_array.dat");
            return;
        }
        uint32_t idx = (uint32_t)VP_ADDR_BRAM_STAGES_TH;
        string line, val_str;
        while(getline(f, line)) {
            istringstream ss(line);
            while(getline(ss, val_str, ',')) {
                if(idx >= VP_ADDR_BRAM_STAGES_TH + BRAM_STAGES_TH_SIZE) break;
                int v = 0;
                istringstream(val_str) >> v;
                mem[idx++] = (short int)v;
            }
        }
        f.close();
        cout << "BRAM: ucitano stages_thresh_array (" << BRAM_STAGES_TH_SIZE << " lokacija)\n";
    }

    /* 4. weights_array: 8739 short int vrednosti, tezine Haarovih karakteristika, lokalna adresa: VP_ADDR_BRAM_WEIGHTS */
    {
        ifstream f("../data/weights_array.dat");
        if(!f.is_open()) {
            SC_REPORT_ERROR("BRAM", "Nije moguce otvoriti weights_array.dat");
            return;
        }
        uint32_t idx = (uint32_t)VP_ADDR_BRAM_WEIGHTS;
        string line, val_str;
        while(getline(f, line)) {
            istringstream ss(line);
            while(getline(ss, val_str, ',')) {
                if(idx >= VP_ADDR_BRAM_WEIGHTS + BRAM_WEIGHTS_SIZE) break;
                int v = 0;
                istringstream(val_str) >> v;
                mem[idx++] = (short int)v;
            }
        }
        f.close();
        cout << "BRAM: ucitano weights_array (" << BRAM_WEIGHTS_SIZE << " lokacija)\n";
    }

    /* 5. alpha1_array: 2913 short int vrednosti, koeficijenti slabih klasifikatora (leva grana), lokalna adresa: VP_ADDR_BRAM_ALPHA1 */
    {
        ifstream f("../data/alpha1_array.dat");
        if(!f.is_open()) {
            SC_REPORT_ERROR("BRAM", "Nije moguce otvoriti alpha1_array.dat");
            return;
        }
        uint32_t idx = (uint32_t)VP_ADDR_BRAM_ALPHA1;
        string line, val_str;
        while(getline(f, line)) {
            istringstream ss(line);
            while(getline(ss, val_str, ',')) {
                if(idx >= VP_ADDR_BRAM_ALPHA1 + BRAM_ALPHA1_SIZE) break;
                int v = 0;
                istringstream(val_str) >> v;
                mem[idx++] = (short int)v;
            }
        }
        f.close();
        cout << "BRAM: ucitano alpha1_array (" << BRAM_ALPHA1_SIZE << " lokacija)\n";
    }

    /* 6. alpha2_array: 2913 short int vrednosti, koeficijenti slabih klasifikatora (desna grana), lokalna adresa: VP_ADDR_BRAM_ALPHA2 */
    {
        ifstream f("../data/alpha2_array.dat");
        if(!f.is_open()) {
            SC_REPORT_ERROR("BRAM", "Nije moguce otvoriti alpha2_array.dat");
            return;
        }
        uint32_t idx = (uint32_t)VP_ADDR_BRAM_ALPHA2;
        string line, val_str;
        while(getline(f, line)) {
            istringstream ss(line);
            while(getline(ss, val_str, ',')) {
                if(idx >= VP_ADDR_BRAM_ALPHA2 + BRAM_ALPHA2_SIZE) break;
                int v = 0;
                istringstream(val_str) >> v;
                mem[idx++] = (short int)v;
            }
        }
        f.close();
        cout << "BRAM: ucitano alpha2_array (" << BRAM_ALPHA2_SIZE << " lokacija)\n";
    }

    /* 7. tree_thresh_array: 2913 short int vrednosti, pragovi odlucivanja po slabom klasifikatoru, lokalna adresa: VP_ADDR_BRAM_TREE_TH */
    {
        ifstream f("../data/tree_thresh_array.dat");
        if(!f.is_open()) {
            SC_REPORT_ERROR("BRAM", "Nije moguce otvoriti tree_thresh_array.dat");
            return;
        }
        uint32_t idx = (uint32_t)VP_ADDR_BRAM_TREE_TH;
        string line, val_str;
        while(getline(f, line)) {
            istringstream ss(line);
            while(getline(ss, val_str, ',')) {
                if(idx >= VP_ADDR_BRAM_TREE_TH + BRAM_TREE_TH_SIZE) break;
                int v = 0;
                istringstream(val_str) >> v;
                mem[idx++] = (short int)v;
            }
        }
        f.close();
        cout << "BRAM: ucitano tree_thresh_array (" << BRAM_TREE_TH_SIZE << " lokacija)\n";
    }

    cout << "BRAM: svi podaci ucitani. Ukupno lokacija: " << BRAM_SIZE << "\n";
}

// Konstruktor
bram_mem::bram_mem(sc_module_name name): sc_module(name), soc_ic("bram_soc_ic"), soc_ip("bram_soc_ip"){
    soc_ic.register_b_transport(this, &bram_mem::b_transport_ic);
    soc_ip.register_b_transport(this, &bram_mem::b_transport_ip);

    // Ucitavanje klasifikacionih podataka pri inicijalizaciji (smatra se da akcija ne trosi simulaciono vreme)
    load_bram_data();
}

/*
/ Naziv funkcije: b_transport_common
/ Parametri: TLM payload, vremenski ofset, dozvola za upis
/ Povratna vrednost: nema
/ Opis funkcije: Zajednicki handler za oba TLM prikljucka. BRAM sadrzi iskljucivo staticne podatke - IP nikad ne upisuje u BRAM (allow_write = false za soc_ip).
/ CPU (IC putanja) takodje ne upisuje u BRAM nakon starta (svi podaci su ucitani u konstruktoru). 
/ Citanje je dozvoljeno sa oba prikljucka bez ogranicenja.
*/
void bram_mem::b_transport_common(pl_t& pl, sc_time& offset, bool allow_write)
{
    tlm_command cmd = pl.get_command();
    uint64 adr = pl.get_address();
    unsigned char* buf = pl.get_data_ptr();
    uint32_t len = pl.get_data_length();

    if(adr >= BRAM_SIZE)
    {
        SC_REPORT_ERROR("BRAM", "Nevazeca adresa!");
        pl.set_response_status(TLM_COMMAND_ERROR_RESPONSE);
        offset += sc_time(5, SC_NS);
        return;
    }

    switch(cmd)
    {
        case TLM_READ_COMMAND:
        {
            // Citanje len bajtova pocev od lokacije adr
            // Kopira direktno iz mem[] u TLM bafer
            std::memcpy(buf, &mem[adr], len);
            pl.set_response_status(TLM_OK_RESPONSE);
            break;
        }
        case TLM_WRITE_COMMAND:
        {
            if(!allow_write)
            {
                // IP ne sme pisati u BRAM - svi podaci su read-only
                SC_REPORT_ERROR("BRAM", "IP pokusaj upisa u read-only BRAM!");
                pl.set_response_status(TLM_COMMAND_ERROR_RESPONSE);
            }
            else
            {
                // CPU putanja (ne koristi se tokom simulacije - podaci su vec ucitani u konstruktoru)
                std::memcpy(&mem[adr], buf, len);
                pl.set_response_status(TLM_OK_RESPONSE);
            }
            break;
        }
        default:
            pl.set_response_status(TLM_COMMAND_ERROR_RESPONSE);
            SC_REPORT_ERROR("BRAM", "Nepoznata TLM komanda");
    }

    // BRAM ima manje kasnjenje od DDR3 u ovom modelu jer je pristup lokalan
    offset += sc_time(5, SC_NS);
}

/*
/ Naziv funkcije: b_transport_ic
/ Opis: TLM handler za Interconnect prikljucak (CPU putanja). Dozvoljava citanje i upis (upis se ne koristi u praksi).
*/
void bram_mem::b_transport_ic(pl_t& pl, sc_time& offset){
    b_transport_common(pl, offset, true);
}

/*
/ Naziv funkcije: b_transport_ip
/ Opis: TLM handler za direktni IP prikljucak. Dozvoljava samo citanje - IP nikad ne upisuje u BRAM.
*/
void bram_mem::b_transport_ip(pl_t& pl, sc_time& offset){
    b_transport_common(pl, offset, false);
}
