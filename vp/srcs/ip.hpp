/*
/ Naziv fajla: ip.hpp
/ Opis fajla: Header fajl za IP akcelerator modul. IP implementira runCascadeClassifier funkciju za jedan prozor slike.
/
/   Za svaki poziv (jedan prozor):
/     1. Cita 8 vrednosti iz DDR3 (updatePvalue)
/     2. Racuna variance_norm_factor
/     3. Za svaku od 25 faza:
/       a. Cita stages_array[i] iz BRAM
/       b. Za svaki slab klasifikator:
/       - cita tree_thresh iz BRAM
/       - cita 4 char vrednosti (x,y,w,h) iz BRAM za svaki pravougaonik
/       - racuna linearne ofset indekse (zamena za scaled_rectangles iz specifikacionog koda)
/       - cita int_img vrednosti iz DDR3
/       - cita weight iz BRAM
/       - akumulira stage_sum
/       c. Cita stages_thresh iz BRAM
/       d. Poredi stage_sum sa pragom (early exit)
/     4. Upisuje result_reg, setuje DONE bit, podiže ip_interrupt
/   Interfejs:
/     - soc_ic: prima reg. pristupe od CPU kroz Interconnect
/     - isoc_bram: cita staticne klasifikacione podatke iz BRAM
/     - isoc_ddr3: cita int_img i sq_int iz DDR3
/     - ip_interrupt: podiže signal kada je rezultat spreman
/ Datum : 25/12/2024
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/
#ifndef _IP_HPP_
#define _IP_HPP_

#include "define.h"
#include "ip_consts.hpp"
#include "vp_addr.hpp"
#include <systemc>
#include <tlm>
#include <tlm_utils/simple_initiator_socket.h>
#include <tlm_utils/simple_target_socket.h>
#include <tlm_utils/tlm_quantumkeeper.h>

class ip :
    public sc_core::sc_module
{
public:
    ip(sc_core::sc_module_name);

    /*
    IP modul implementira runCascadeClassifier za jedan prozor slike.
    Interfejs:
      - soc_ic:prima konfiguraciju od CPU (core1 upisuje registre)
      - isoc_bram:direktno cita staticne klasifikacione podatke iz BRAM
      - isoc_ddr3:direktno cita int_img_buffer i sq_int_buffer iz DDR3
      - ip_interrupt:izlazni bool signal - setuje se kada je DONE bit spreman
    */
    tlm_utils::simple_target_socket<ip> soc_ic;
    tlm_utils::simple_initiator_socket<ip> isoc_bram;
    tlm_utils::simple_initiator_socket<ip> isoc_ddr3;
    sc_core::sc_out<bool> ip_interrupt;

protected:
    typedef tlm::tlm_base_protocol_types::tlm_payload_type pl_t;

    // Dogadjaj koji budi ip_thread kada CPU upise u cfg_reg
    sc_core::sc_event register_state_updated;

    // Stanje IP modula
    typedef enum { RESET, START, IDLE } ip_state_t;
    ip_state_t state;

    // Registri (lokalne adrese IP bazne adrese)
    uint8_t cfg_reg; // offset 0:  bit0=RESET, bit1=START, bit4=DONE
    uint32_t p_offset_reg; // offset 1:  x pozicija prozora (x iz ScaleImage_Invoker)
    uint32_t width_reg; // offset 5:  sz.width tekuce skale
    int32_t result_reg; // offset 9:  1=lice detektovano, -i=odbijen na fazi i

    // TLM handler za CPU prikljucak
    void b_transport_ic(pl_t&, sc_core::sc_time&);

    // Glavna nit IP-a
    void ip_thread();

    // Pomocne funkcije (algoritamska jezgra)

    // Implementacija runCascadeClassifier - vraca 1 ili -i
    int run_cascade_classifier(uint32_t p_offset, uint32_t width, pl_t& pl, unsigned char* data, tlm_utils::tlm_quantumkeeper& qk, sc_core::sc_time& offset);

    // Implementacija evalWeakClassifier za jedan slab klasifikator
    int eval_weak_classifier(int variance_norm_factor, int p_offset,int tree_index, int w_index, int r_index,uint32_t width,pl_t& pl, unsigned char* data,tlm_utils::tlm_quantumkeeper& qk,sc_core::sc_time& offset);

    // Pomocna: cita 8 corner vrednosti i racuna p[] i pq[]
    void update_pvalue(int p_offset, uint32_t width,pl_t& pl, unsigned char* data,tlm_utils::tlm_quantumkeeper& qk,sc_core::sc_time& offset);

    // Pomocna: celobrojna kvadratna korena
    unsigned int int_sqrt(unsigned int value);

    // Pomocna: TLM citanje iz BRAM (lokalna adresa)
    void bram_read(uint64_t local_addr, void* dst, uint32_t len,pl_t& pl, unsigned char* data,tlm_utils::tlm_quantumkeeper& qk,sc_core::sc_time& offset);

    // Pomocna: TLM citanje iz DDR3 (lokalna adresa)
    void ddr3_read(uint64_t local_addr, void* dst, uint32_t len,pl_t& pl, unsigned char* data,tlm_utils::tlm_quantumkeeper& qk,sc_core::sc_time& offset);

    // Privremene promenljive za updatePvalue (interni registri)
    int p[4]; // p0..p3 iz int_img_buffer
    int pq[4];  // pq0..pq3 iz sq_int_buffer
};

#endif
