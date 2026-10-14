/*
/ Naziv fajla: vp.hpp
/ Opis fajla: Header fajl za Virtual Platform modul.
/   Sadrzi i povezuje sve hardverske module:
/     - interconnect (ic_module)
/     - IP akcelerator (ip_module)
/     - BRAM memorija (bram_module)
/     - DDR3 memorija (ddr3_module)
/
/   Interfejs prema testbenchu:
/     - soc_cpu: prima TLM transakcije od CPU (testbench)
/     - interrupt: salje 2-bitni prekidni signal ka testbenchu, bit 0 = IP prekid
/ Datum: 12/3/2026
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/
#ifndef _VP_HPP_
#define _VP_HPP_

#include "define.h"
#include <tlm_utils/simple_target_socket.h>
#include <tlm_utils/simple_initiator_socket.h>
#include "ic.hpp"
#include "ip.hpp"
#include "bram_mem.hpp"
#include "ddr3.hpp"

class vp : sc_core::sc_module{
public:
    vp(sc_core::sc_module_name);

    /*
    Klasa koja modeluje virtuelnu platformu.
    Sastoji se iz IP, BRAM, DDR3 i Interconnect modula.
    Interfejs sadrzi:
      - soc_cpu:  TLM prikljucak ka testbench modulu
      - interrupt: izlazni 2-bitni prekidni signal
                   bit 0 = IP prekid (ip_interrupt_signal)
    */
    tlm_utils::simple_target_socket<vp> soc_cpu;
    sc_core::sc_out<sc_dt::sc_uint<2>> interrupt;

protected:
    // Interni signali za kombinovanje prekida
    sc_core::sc_signal<bool> ip_interrupt_signal;

    // Interni initiator socket - premoscuje soc_cpu ka IC
    tlm_utils::simple_initiator_socket<vp> s_bus;

    // Submoduli
    interconnect ic_module;
    ip ip_module;
    bram_mem bram_module;
    ddr3_ram ddr3_module;

    typedef tlm::tlm_base_protocol_types::tlm_payload_type pl_t;

    // Prosledjuje transakcije od testbench ka IC-u
    void b_transport_cpu(pl_t&, sc_core::sc_time&);

    // Kombinuje interni ip_interrupt_signal u 2-bitni interrupt
    void concat();
};

#endif
