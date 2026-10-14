/*
/ Naziv fajla: ip_consts.hpp
/ Opis fajla: Konstante koje opisuju lokalni registarski prostor IP modula i raspored podataka u BRAM memoriji.
/ Datum: 6/3/2026
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/
#ifndef _IP_CONSTS_HPP_
#define _IP_CONSTS_HPP_

#include <stdint.h>

// IP registarski ofset od bazne adrese IP modula
// cfg_reg bit mapa:
//   bit 0 - IP_RESET_BIT, CPU setuje za reset
//   bit 1 - IP_START_BIT, CPU setuje za pokretanje jednog prozora
//   bit 4 - IP_DONE_BIT, IP setuje kada je rezultat spreman
const uint32_t IP_CFG_REG_OFFSET = 0; // uint8
const uint32_t IP_P_OFFSET_REG_OFFSET = 1; // uint32 - x pozicija prozora
const uint32_t IP_WIDTH_REG_OFFSET = 5; // uint32 - sz.width tekuce skale
const uint32_t IP_RESULT_REG_OFFSET = 9; // int32 - 1=lice, -i=odbijen na fazi i

// BRAM raspored - broj lokacija po nizu
const uint32_t BRAM_RECT_SIZE = 34956; // rectangles_array (char x 34956)
const uint32_t BRAM_STAGES_SIZE = 25; // stages_array (uint8 x 25)
const uint32_t BRAM_STAGES_TH_SIZE = 25; // stages_thresh_array (short int x 25)
const uint32_t BRAM_WEIGHTS_SIZE = 8739; // weights_array (short int x 8739)
const uint32_t BRAM_ALPHA1_SIZE = 2913; // alpha1_array (short int x 2913)
const uint32_t BRAM_ALPHA2_SIZE = 2913; // alpha2_array (short int x 2913)
const uint32_t BRAM_TREE_TH_SIZE = 2913; // tree_thresh_array (short int x 2913)

// Ukupno BRAM lokacija (sve short int adresiranje osim rect koji je char)
// rect: 34956
// stages: 25
// stages_th: 25
// weights: 8739
// alpha1: 2913
// alpha2: 2913
// tree_th: 2913
// UKUPNO: 52484 short int lokacija = ~104 KB
const uint32_t BRAM_SIZE = 52484;

// Broj faza kaskade i velicina prozora (konstante algoritma)
const int NUM_STAGES = 25;
const int ORIG_WIN_WIDTH = 24;
const int ORIG_WIN_HEIGHT = 24;
const int INV_WINDOW_AREA = ORIG_WIN_WIDTH * ORIG_WIN_HEIGHT; // 576

#endif
