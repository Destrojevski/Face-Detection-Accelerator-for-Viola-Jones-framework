/*
/ Naziv fajla: ddr3.cpp
/ Opis fajla: Implementacija DDR3 modula. Modeluje TLM komunikaciju za dinamicne integralne slike koje core1 upisuje a IP cita.
/ Datum: 10/3/2026
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/
#include "ddr3.hpp"

using namespace sc_core;
using namespace sc_dt;
using namespace std;
using namespace tlm;

// Konstruktor
ddr3_ram::ddr3_ram(sc_module_name name): sc_module(name), soc_ic("ddr3_soc_ic"), soc_ip("ddr3_soc_ip"){
    soc_ic.register_b_transport(this, &ddr3_ram::b_transport_ic);
    soc_ip.register_b_transport(this, &ddr3_ram::b_transport_ip);

    // Inicijalizacija memorije na nulu
    for(int i = 0; i < DDR3_TOTAL_SIZE; i++)
        mem[i] = 0;

    SC_REPORT_INFO("DDR3", "DDR3 memorija inicijalizovana.");
}

/*
/ Naziv funkcije: b_transport_common
/ Parametri: TLM payload i vremenski ofset
/ Povratna vrednost: nema
/ Opis funkcije: Zajednicki handler za oba TLM prikljucka.Lokalna adresa 0..8999 = int_img_buffer,a lokalna adresa 9000..17999 = sq_int_buffer. 
/ Podrzava citanje i upis int vrednosti. Korsiti vece kasnjenje (10 ns) jer DDR3 je sporiji od BRAM-a.
*/
void ddr3_ram::b_transport_common(pl_t& pl, sc_time& offset)
{
    tlm_command cmd = pl.get_command();
    uint64 adr = pl.get_address();
    unsigned char* buf = pl.get_data_ptr();
    uint32_t len = pl.get_data_length();

    if(adr >= DDR3_TOTAL_SIZE)
    {
        SC_REPORT_ERROR("DDR3", "Nevazeca adresa!");
        pl.set_response_status(TLM_COMMAND_ERROR_RESPONSE);
        offset += sc_time(10, SC_NS);
        return;
    }

    switch(cmd)
    {
        case TLM_WRITE_COMMAND:
        {
            // Upis int vrednosti na adresu adr
            // core1 upisuje nakon svake iteracije integralne slike
            int val;
            std::memcpy(&val, buf, sizeof(int));
            mem[adr] = val;
            pl.set_response_status(TLM_OK_RESPONSE);
            break;
        }
        case TLM_READ_COMMAND:
        {
            // Citanje int vrednosti sa adrese adr
            // IP cita tokom evalWeakClassifier i updatePvalue
            int val = mem[adr];
            std::memcpy(buf, &val, sizeof(int));
            pl.set_response_status(TLM_OK_RESPONSE);
            break;
        }
        default:
            pl.set_response_status(TLM_COMMAND_ERROR_RESPONSE);
            SC_REPORT_ERROR("DDR3", "Nepoznata TLM komanda");
    }

    // DDR3 ima vece kasnjenje od BRAM-a (off-chip memorija)
    offset += sc_time(10, SC_NS);
}

/*
/ Naziv funkcije: b_transport_ic
/ Opis: TLM handler za Interconnect prikljucak (core1 putanja). core1 upisuje int_img i sq_int svaki y_bias korak.
*/
void ddr3_ram::b_transport_ic(pl_t& pl, sc_time& offset){
    b_transport_common(pl, offset);
}

/*
/ Naziv funkcije: b_transport_ip
/ Opis: TLM handler za direktni IP prikljucak. IP cita int_img i sq_int tokom klasifikacije prozora.
*/
void ddr3_ram::b_transport_ip(pl_t& pl, sc_time& offset){
    b_transport_common(pl, offset);
}
