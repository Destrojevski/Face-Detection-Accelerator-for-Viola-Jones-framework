/*
/ Naziv fajla: bram_mem.hpp
/ Opis fajla: Header fajl za BRAM modul. Sadrzi staticne klasifikacione podatke koji se ucitavaju jednom pri startu i nikad ne menjaju tokom simulacije:
/   - rectangles_array (geometrija Haarovih karakteristika)
/   - stages_array (broj klasifikatora po fazi)
/   - stages_thresh_array (pragovi faza)
/   - weights_array (tezine karakteristika)
/   - alpha1_array (koeficijenti slabih klasifikatora)
/   - alpha2_array (koeficijenti slabih klasifikatora)
/   - tree_thresh_array (pragovi klasifikatora)
/ Ima dva TLM prikljucka:
/   - soc_ic: prima transakcije od CPU kroz Interconnect
/   - soc_ip: prima transakcije direktno od IP modula
/ Datum : 11/02/2025
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/
#ifndef _BRAM_MEM_HPP_
#define _BRAM_MEM_HPP_

#include "define.h"
#include "ip_consts.hpp"
#include <tlm>
#include <tlm_utils/simple_target_socket.h>

class bram_mem: public sc_core::sc_module{
public:
    bram_mem(sc_core::sc_module_name);

    /*
    BRAM modul.
    Interfejs sadrzi dva jednostavna TLM prikljucka:
      - soc_ic: prikljucak ka Interconnect modulu (CPU putanja)
      - soc_ip: prikljucak direktno ka IP modulu (brza putanja)
    */
    tlm_utils::simple_target_socket<bram_mem> soc_ic;
    tlm_utils::simple_target_socket<bram_mem> soc_ip;

protected:
    typedef tlm::tlm_base_protocol_types::tlm_payload_type pl_t;

    // Ucitavanje svih klasifikacionih podataka iz .dat fajlova
    void load_bram_data();

    // b_transport handleri
    void b_transport_ic(pl_t&, sc_core::sc_time&);
    void b_transport_ip(pl_t&, sc_core::sc_time&);

    // Zajednicki handler (i IC i IP koriste isti memorijski prostor, samo sa razlicitim dozvolama pristupa)
    void b_transport_common(pl_t&, sc_core::sc_time&, bool allow_write);

    // Memorijski niz (short int za uniformno adresiranje svih tipova), ukupno BRAM_SIZE lokacija = 52484 short int = ~104 KB
    short int mem[BRAM_SIZE];
};

#endif
