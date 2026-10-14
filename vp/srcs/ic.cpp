/*
/ Naziv fajla: ic.cpp
/ Opis fajla: Implementacija Interconnect modula. Rutira TLM transakcije prema DDR3, BRAM ili IP modulu na osnovu globalne adrese.
/ Autori: Sandić Vojislav, Jović Radivoje, Glišević Sara
/ Datum: 6.3.2026.
*/
#include "ic.hpp"
#include "vp_addr.hpp"

using namespace std;
using namespace tlm;
using namespace sc_core;
using namespace sc_dt;

interconnect::interconnect(sc_module_name name) : sc_module(name), soc_cpu("ic_soc_cpu"), isoc_ddr3("ic_isoc_ddr3"), isoc_bram("ic_isoc_bram"), isoc_ip("ic_isoc_ip")
{
    soc_cpu.register_b_transport(this, &interconnect::b_transport_cpu);
}

/*
/ Naziv funkcije: b_transport_cpu
/ Parametri: TLM payload i vremenski ofset
/ Povratna vrednost: nema
/ Opis funkcije: Rutira transakciju od CPU prema odgovarajucem modulu. Dekodira globalnu adresu, preracunava u lokalnu i prosledjuje transakciju.
*/
void interconnect::b_transport_cpu(pl_t& pl, sc_time& offset)
{
    uint64 addr  = pl.get_address();
    uint64 taddr = 0;

    offset += sc_time(2, SC_NS);

    // DDR3: adrese 0x00000000 do VP_ADDR_DDR3_H
    if(addr >= VP_ADDR_DDR3 && addr <= VP_ADDR_DDR3_H)
    {
        // DDR3 koristi ravnu adresaciju - lokalna adresa = globalna adresa
        taddr = addr;
        pl.set_address(taddr);
        isoc_ddr3->b_transport(pl, offset);
    }
    // BRAM: adrese VP_ADDR_BRAM do VP_ADDR_BRAM_H
    else if(addr >= VP_ADDR_BRAM && addr < VP_ADDR_BRAM_H)
    {
        // Stripovanje bazne adrese - sve lokalne BRAM adrese staju u 16 bita
        taddr = addr & 0x0000FFFF;
        pl.set_address(taddr);
        isoc_bram->b_transport(pl, offset);
    }
    // IP: adrese VP_ADDR_IP do VP_ADDR_IP_H
    else if(addr >= VP_ADDR_IP && addr < VP_ADDR_IP_H)
    {
        // Stripovanje bazne adrese - lokalne IP adrese staju u 8 bita
        taddr = addr & 0x000000FF;
        pl.set_address(taddr);
        isoc_ip->b_transport(pl, offset);
    }
    else
    {
        SC_REPORT_ERROR("INTERCONNECT", "Nevazeca adresa!");
        pl.set_response_status(TLM_COMMAND_ERROR_RESPONSE);
        return;
    }

    // Restauracija originalne globalne adrese za pozivaoca
    pl.set_address(addr);
}
