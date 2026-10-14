/*
/ Naziv fajla: vj_core.h
/ Opis fajla: Header fajl za Viola-Jones HLS IP jezgro.
/ Definise klasu VJCore koja cuva stanje IP-a izmedju poziva i deklarise top_function koja se sintetizuje u RTL.
/ Datum: 23/3/2026
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/
#ifndef _VJ_CORE_H_
#define _VJ_CORE_H_

#include "ap_int.h"
// Dimenzije elemenata BRAM memorije
#define BRAM_RECT_SIZE 34956
#define BRAM_STAGES_SIZE 25
#define BRAM_STAGES_TH_SIZE 25
#define BRAM_WEIGHTS_SIZE 8739
#define BRAM_ALPHA1_SIZE 2913
#define BRAM_ALPHA2_SIZE 2913
#define BRAM_TREE_TH_SIZE 2913
#define BRAM_SIZE 52484
// Lokalne BRAM adrese (indeksi u bram[] nizu)
#define VP_ADDR_BRAM_RECT 0
#define VP_ADDR_BRAM_STAGES (VP_ADDR_BRAM_RECT + BRAM_RECT_SIZE)
#define VP_ADDR_BRAM_STAGES_TH (VP_ADDR_BRAM_STAGES + BRAM_STAGES_SIZE)
#define VP_ADDR_BRAM_WEIGHTS (VP_ADDR_BRAM_STAGES_TH + BRAM_STAGES_TH_SIZE)
#define VP_ADDR_BRAM_ALPHA1 (VP_ADDR_BRAM_WEIGHTS + BRAM_WEIGHTS_SIZE)
#define VP_ADDR_BRAM_ALPHA2 (VP_ADDR_BRAM_ALPHA1 + BRAM_ALPHA1_SIZE)
#define VP_ADDR_BRAM_TREE_TH (VP_ADDR_BRAM_ALPHA2 + BRAM_ALPHA2_SIZE)
// Dimenzije DDR3 memorije
#define DDR3_INT_IMG_SIZE 9000// int_img_buffer: indeksi 0..8999
#define DDR3_SQ_INT_OFFSET 9000// sq_int_buffer pocinje ovdje
#define DDR3_TOTAL_SIZE 18000// ukupno int lokacija
// Algoritamske konstante
#define NUM_STAGES 25
#define ORIG_WIN_WIDTH 24
#define ORIG_WIN_HEIGHT 24
#define INV_WINDOW_AREA 576 // 24 * 24
// Bitovi konfiguracionog registra
#define IP_RESET_BIT 0 // bit 0: CPU setuje za reset
#define IP_START_BIT 1 // bit 1: CPU setuje za pokretanje jednog prozora
#define IP_DONE_BIT 4 // bit 4: IP setuje kada je result_reg spreman
// Stanja IP modula
enum ip_state_t { IDLE, RESET, START };
/* VJCore klasa
// Cuva stanje IP-a izmedju poziva top funkcije.
// Instancira se kao staticka lokalna varijabla unutar top_function tako da njeni clanovi postaju registri u sintetizovanom RTL-u.
*/
class VJCore{
public:
// IP registri
ap_uint<8> cfg_reg;// bit0=RESET, bit1=START, bit4=DONE
ap_uint<32> p_offset_reg;// x pozicija prozora
ap_uint<32> width_reg;// sz.width tekuce skale
ap_int<32> result_reg;// 1=lice, -i=odbijen na fazi i
bool ip_interrupt;
ip_state_t state;
// Interni registri datapath-a (vrijednosti coskova integralnih slika iz DDR3)
ap_int<32> p[4];// cetiri coska iz int_img_buffer
ap_int<32> pq[4];// cetiri coska iz sq_int_buffer
VJCore();
};
/* top_function - ovo se sintetizuje u RTL
// Argumenti postaju dijelovi / portovi IP bloka:
//   cfg_val: R/W registar (cfg_reg)
//   p_offset: W registar (x pozicija klasifikacionog prozora)
//   width: W registar (sz.width)
//   bram: BRAM port (svi staticni klasifikacioni podaci)
//   ddr3 : DDR3/DMA port (baferi integralne slike)
//   ip_interrupt: izlazni bool prekidni signal
//   result: R registar (rezultat klasifikacije)
*/
void top_function(ap_uint<8> *cfg_val,ap_uint<32> p_offset,ap_uint<32> width,ap_int<16> bram[BRAM_SIZE],ap_int<32> ddr3[DDR3_TOTAL_SIZE],bool *ip_interrupt,ap_int<32> *result);
#endif
