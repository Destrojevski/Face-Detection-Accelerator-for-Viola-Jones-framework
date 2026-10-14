/*
/ Naziv fajla: ic.hpp
/ Opis fajla: Header fajl za Interconnect modul. Memorijski mapira DDR3, BRAM i IP module. Prima transakcije od CPU (testbench) i rutira ih prema odgovarajucem modulu
/ na osnovu adrese.
/ Autori: Sandić Vojislav, Jović Radivoje, Glišević Sara
/ Datum: 6.3.2026.
*/
#ifndef _IC_HPP_
#define _IC_HPP_

#include "define.h"
#include <tlm>
#include <tlm_utils/simple_target_socket.h>
#include <tlm_utils/simple_initiator_socket.h>

class interconnect : public sc_core::sc_module{
public:
    interconnect(sc_core::sc_module_name);

    /*
    Interconnect modul memorijski mapira DDR3, BRAM i IP module.
    Interfejs sadrzi jednostavne TLM prikljucke:
      - soc_cpu  : prima transakcije od CPU (testbench)
      - isoc_ddr3: prosledjuje transakcije DDR3 modulu
      - isoc_bram: prosledjuje transakcije BRAM modulu
      - isoc_ip  : prosledjuje transakcije IP modulu
    */
    tlm_utils::simple_target_socket<interconnect> soc_cpu;
    tlm_utils::simple_initiator_socket<interconnect> isoc_ddr3;
    tlm_utils::simple_initiator_socket<interconnect> isoc_bram;
    tlm_utils::simple_initiator_socket<interconnect> isoc_ip;

protected:
    typedef tlm::tlm_base_protocol_types::tlm_payload_type pl_t;
    void b_transport_cpu(pl_t&, sc_core::sc_time&);
};

#endif
