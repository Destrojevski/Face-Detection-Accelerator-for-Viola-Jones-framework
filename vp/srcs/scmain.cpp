/*
/ Naziv fajla: scmain.cpp
/ Opis fajla: Ulazna tacka SystemC simulacije. Instancira Virtual Platform i Testbench module, povezuje ih i pokrece simulaciju.
/ Datum: 5/3/2026
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/

// SC_INCLUDE_FX mora biti definisano PRE prvog ukljucivanja systemc.h
// kako bi se kompajlirale sc_ufixed/sc_fixed klase.
// define.h garantuje ispravan redosled - ne treba ukljucivati <systemc> direktno.
#include "tb_vp.hpp"
#include "vp.hpp"

using namespace sc_core;

int sc_main(int argc, char* argv[])
{
    // Instanciranje modula
    vp vp_platform("vp");
    tb_vp testbench("tb");

    // Signal za prekide: VP ka Testbench-u bit 0 = IP prekid
    sc_core::sc_signal<sc_dt::sc_uint<2>> interrupt_signal;

    // Povezivanje modula
    testbench.isoc.bind(vp_platform.soc_cpu);
    vp_platform.interrupt.bind(interrupt_signal);
    testbench.IRQ_F2P.bind(interrupt_signal);

    // Postavljanje globalnog TLM kvantuma
    tlm::tlm_global_quantum::instance().set(sc_time(10, SC_NS));

    // Pokretanje simulacije
    sc_start();

    std::cout << "\nSimulacija zavrsena u: " << sc_time_stamp() << std::endl;

    return 0;
}
