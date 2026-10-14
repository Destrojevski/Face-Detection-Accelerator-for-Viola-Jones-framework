/*
/ Naziv fajla: ddr3.hpp
/ Opis fajla: Header fajl za DDR3 modul. DDR3 memorija sadrzi dinamicne podatke koji se menjaju tokom simulacije:
/   - int_img_buffer: 25 * IMAGE_WIDTH int vrednosti (integralna slika, upisuje core1 svaki y_bias korak)
/   - sq_int_buffer:  25 * IMAGE_WIDTH int vrednosti (kvadrirana integralna slika, upisuje core1 svaki y_bias korak)
/ IP ih cita direktno tokom klasifikacije prozora. core1 ih upisuje nakon svake iteracije integralne slike.
/ Ima dva TLM prikljucka:
/   - soc_ic: prima transakcije od CPU kroz Interconnect
/   - soc_ip: prima transakcije direktno od IP modula
/ Datum: 10/3/2026
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/
#ifndef _DDR3_HPP_
#define _DDR3_HPP_

#include "define.h"
#include "ip_consts.hpp"
#include <tlm>
#include <tlm_utils/simple_target_socket.h>
#include <vector>

// Velicina DDR3 memorije u int lokacijama
#define DDR3_INT_IMG_SIZE (25 * IMAGE_WIDTH) // 9000 lokacija
#define DDR3_SQ_INT_SIZE (25 * IMAGE_WIDTH) // 9000 lokacija
#define DDR3_TOTAL_SIZE (DDR3_INT_IMG_SIZE + DDR3_SQ_INT_SIZE) // 18000 uint8 lokacija = 72 KB

class ddr3_ram :public sc_core::sc_module{
public:
    ddr3_ram(sc_core::sc_module_name);

    /*
    DDR3 modul.
    Interfejs sadrzi dva jednostavna TLM prikljucka:
      - soc_ic: prikljucak ka Interconnect modulu (CPU/core1 putanja)
      - soc_ip: prikljucak direktno ka IP modulu (brza citanja)
    */
    tlm_utils::simple_target_socket<ddr3_ram> soc_ic;
    tlm_utils::simple_target_socket<ddr3_ram> soc_ip;

    // Memorijski nizovi (int vrednosti jer su integralne slike int tipa)
    // int_img_buffer: lokalne adrese 0 do DDR3_INT_IMG_SIZE-1
    // sq_int_buffer: lokalne adrese DDR3_INT_IMG_SIZE do DDR3_TOTAL_SIZE-1
    int mem[DDR3_TOTAL_SIZE];

protected:
    typedef tlm::tlm_base_protocol_types::tlm_payload_type pl_t;

    void b_transport_ic(pl_t&, sc_core::sc_time&);
    void b_transport_ip(pl_t&, sc_core::sc_time&);
    void b_transport_common(pl_t&, sc_core::sc_time&);
};

#endif
