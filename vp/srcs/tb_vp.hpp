/*
/ Naziv fajla: tb_vp.hpp
/ Opis fajla: Header fajl za testbench modul koji implementira dva CPU jezgra i GIC kontroler.
/   core0 - ucitavanje slike i prijavljivanje rezultata
/   core1 - koordinacija algoritma detekcije lica
/ Datum: 28/12/2024
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/

#ifndef _TB_VP_HPP_
#define _TB_VP_HPP_

#include "define.h"
#include "image.h"
#include "image_ops.h"
#include "vp_addr.hpp"

#include <iostream>
#include <fstream>
#include <cstdio>
#include <vector>

#include <tlm>
#include <tlm_utils/simple_initiator_socket.h>
#include <tlm_utils/tlm_quantumkeeper.h>

class tb_vp : public sc_core::sc_module{
public:
    tb_vp(sc_core::sc_module_name);
    /*
    Testbench modul implementira dva CPU jezgra i GIC kontroler.
    Njegov interfejs prema virtuelnoj platformi podrazumeva:
    - signal: IRQ_F2P - prima prekidni signal od VP-a (bit 0 = IP interrupt)
    - TLM jednostavan prikljucak: isoc - salje TLM transakcije ka VP-u
    */
    tlm_utils::simple_initiator_socket<tb_vp> isoc;
    sc_core::sc_in<sc_dt::sc_uint<2>> IRQ_F2P;
protected:
    typedef tlm::tlm_base_protocol_types::tlm_payload_type pl_t;

    // Događaji za sinhronizaciju izmedju core0 i core1
    sc_core::sc_event new_image_ready; // core0 ka core1: slika ucitana, parametri upisani
    sc_core::sc_event detection_done; // core1 ka core0: detekcija gotova, rezultat upisan
    sc_core::sc_event end_of_simulation; // core0 exit_simulation događaj

    // Događaji za sinhronizaciju GIC i core1 koristeći IP prekidnu rutinu (IP_ISR) 
    sc_core::sc_event ip_interrupt_event; // GIC notifikuje IP_ISR
    sc_core::sc_event ip_done_event; // IP_ISR notifikuje core1 (DONE bit potvrđen)

    // Procesi
    void core0(); // SC_THREAD: ucitavanje slike, parametara, ispis rezultata
    void core1(); // SC_THREAD: algoritam detekcije, koordinacija IP-a
    void gic(); // SC_METHOD: demultipleksuje IRQ_F2P signal
    void IP_ISR(); // SC_THREAD: prekidna rutina za IP
    void exit_simulation(); // SC_METHOD: poziva sc_stop()

    MyImage imageObj; // raw piksel podaci ucitani od strane core0
	float shared_scale_factor;
	uint8_t shared_shift_step;
	uint8_t shared_face_count;
    // Veliki radni baferi - moraju biti clanovi klase (heap), ne lokalne promenljive u SC_THREAD (podrazumevani SystemC stack je samo 64KB).
    sc_dt::sc_uint<8> in_img_buffer[IMAGE_HEIGHT][IMAGE_WIDTH];
    int int_img_buffer[25 * IMAGE_WIDTH];
    int sq_int_buffer[25 * IMAGE_WIDTH];
    sc_dt::sc_uint<OUT_BW> face_coordinate[MAX_NUM_FACE][4];
    sc_dt::sc_uint<8> face_number;

    // Pomocne metode za core1

    // Upisuje int_img_buffer i sq_int_buffer u DDR3 memoriju
    void write_integral_buffers_to_ddr3( int* int_img, int* sq_int, uint32_t width, pl_t& pl, unsigned char* data, tlm_utils::tlm_quantumkeeper& qk, sc_core::sc_time& offset);

    // Pomocna inline TLM write metoda
    void tlm_write(uint64_t addr, void* src, uint32_t len, pl_t& pl, unsigned char* data, tlm_utils::tlm_quantumkeeper& qk, sc_core::sc_time& offset);

    // Pomocna inline TLM read metoda
    void tlm_read(uint64_t addr, void* dst, uint32_t len, pl_t& pl, unsigned char* data, tlm_utils::tlm_quantumkeeper& qk, sc_core::sc_time& offset);

    // SW implementacije algoritamskih funkcija (izvrsavaju se na core1)
    inline int myRound(sc_dt::sc_ufixed<16,12,SC_RND,SC_SAT> value){
        return (int)(value + (sc_dt::sc_ufixed<16,12,SC_RND,SC_SAT>)0.5);
    }

    void integralImages_fused(sc_dt::sc_uint<8> in_img[IMAGE_HEIGHT][IMAGE_WIDTH], int* sumData, int* sqsumData, int width, int height, sc_dt::sc_ufixed<10,5,SC_RND,SC_SAT> factor, int y_bias);

    void integralmages_lastrow_fused(sc_dt::sc_uint<8> in_img[IMAGE_HEIGHT][IMAGE_WIDTH], int* sumData, int* sqsumData, int width, int sz_height, sc_dt::sc_ufixed<10,5,SC_RND,SC_SAT> factor, int y_bias);

    void groupRectangles(sc_dt::sc_uint<OUT_BW> face_coordinate[][4], sc_dt::sc_uint<8>& face_number, int groupThreshold, sc_dt::sc_ufixed<8,1,SC_RND,SC_SAT> eps);

    int partition(sc_dt::sc_uint<OUT_BW> face_coordinate[][4], int face_number, int* labels, sc_dt::sc_ufixed<8,1,SC_RND,SC_SAT> eps);

    int predicate(sc_dt::sc_ufixed<8,1,SC_RND,SC_SAT> eps, sc_dt::sc_uint<OUT_BW> r1[4], sc_dt::sc_uint<OUT_BW> r2[4]);

    int myAbs(int n) { return (n >= 0) ? n : -n; }
};

#endif
