/*
/ Naziv fajla : vp.cpp
/ Opis fajla  : Implementacija Virtual Platform modula. Konstruktor instancira i povezuje sve hardverske module.
/ Datum: 12/3/2026
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/
#include "vp.hpp"
#include <iostream>

using namespace sc_core;
using namespace sc_dt;
using namespace std;

SC_HAS_PROCESS(vp);

/*
/ Naziv funkcije: vp (konstruktor)
/ Opis: Instancira sve hardverske module i uspostavlja sve TLM i signal veze izmedju njih.
*/
vp::vp(sc_module_name name) :sc_module(name), ic_module("ic_module"), ip_module("ip_module"), bram_module("bram_module"), ddr3_module("ddr3_module") {
    // SC_METHOD za kombinovanje prekidnih signala u 2-bitni izlaz
    SC_METHOD(concat);
    dont_initialize();
    sensitive << ip_interrupt_signal;

    // Registrovanje b_transport handlera za CPU prikljucak
    soc_cpu.register_b_transport(this, &vp::b_transport_cpu);

    // CPU putanja: od testbench-a do IC-a
    s_bus.bind(ic_module.soc_cpu);

    // od IC-a do periferija (CPU/core1 putanje kroz magistralu)
    ic_module.isoc_ddr3.bind(ddr3_module.soc_ic);
    ic_module.isoc_bram.bind(bram_module.soc_ic);
    ic_module.isoc_ip.bind(ip_module.soc_ic);

    // IP direktne putanje (zaobilaze IC)
    ip_module.isoc_bram.bind(bram_module.soc_ip);
    ip_module.isoc_ddr3.bind(ddr3_module.soc_ip);

    // Prekidni signali: od IP-a ka interrupt izlazu
    ip_module.ip_interrupt.bind(ip_interrupt_signal);

    SC_REPORT_INFO("VP", "Platforma je konstruisana.");
}

/*
/ Naziv funkcije: b_transport_cpu
/ Opis: Prosledjuje TLM transakcije od testbench ka internom initiator socketu koji vodi do IC modula.
*/
void vp::b_transport_cpu(pl_t& pl, sc_time& delay)
{
    s_bus->b_transport(pl, delay);
}

/*
/ Naziv funkcije: concat
/ Opis: SC_METHOD koji se okida na promenu ip_interrupt_signal. Pakuje interne 1-bitne signale u 2-bitni izlazni interrupt signal prema testbenchu.
/   bit 0 = IP prekid
/   bit 1 = rezervisano (nema DMA u ovom dizajnu)
*/
void vp::concat()
{
    sc_uint<2> intr;
    intr[0] = ip_interrupt_signal.read(); // IP prekid
    intr[1] = 0; // rezervisano (nema DMA)

    //SC_REPORT_INFO("VP", "Prekid registrovan!");
    //cout << endl << intr[1] << intr[0] << endl;

    interrupt.write(intr);
}
