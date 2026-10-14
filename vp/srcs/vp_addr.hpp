/*
/ Naziv fajla: vp_addr.hpp
/ Opis fajla: Globalna memorijska mapa virtuelne platforme. Sadrzi bazne adrese svih modula i adrese svih registara.
/ Datum: 11/3/2026
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/
#ifndef _VP_ADDR_HPP_
#define _VP_ADDR_HPP_

#include "ip_consts.hpp"

using namespace sc_dt;

// Bazne adrese modula
const uint64 VP_ADDR_DDR3 = 0x00000000; // DDR3 memorija
const uint64 VP_ADDR_BRAM = 0x20000000; // BRAM memorija
const uint64 VP_ADDR_IP = 0x40000000; // IP modul (evalWeakClassifier akcelerator)

// Gornje granice modula (prva slobodna adresa iznad modula)
const uint64 VP_ADDR_DDR3_H = 0x1FFFFFFF; // kraj DDR3 opsega
const uint64 VP_ADDR_BRAM_H = 0x2000D600; // kraj BRAM opsega (lokalna adresa 0xD600 = 54784, prva slobodna iza svih statickih podataka)
const uint64 VP_ADDR_IP_H = 0x40000010; // kraj IP registarskog opsega

// DDR3 raspored memorije
// Citaju: core1 (upisuje int_img i sq_int), IP (cita int_img i sq_int)

// int_img_buffer: 25 * IMAGE_WIDTH int vrednosti (9000 ints), core1 upisuje, IP cita direktno
const uint64 VP_ADDR_DDR3_INT_IMG = VP_ADDR_DDR3 + 0;

// sq_int_buffer: 25 * IMAGE_WIDTH int vrednosti (9000 ints), core1 upisuje, IP cita direktno
const uint64 VP_ADDR_DDR3_SQ_INT = VP_ADDR_DDR3 + 9000;

// BRAM raspored memorije - svi staticni klasifikacioni podaci, Ucitavaju se jednom pri startu, IP ih cita tokom klasifikacije 
// Adrese su LOKALNE (nakon stripovanja bazne adrese od strane IC-a)

// rectangles_array: 34956 char vrednosti (x,y,w,h za svaki pravougaonik)
const uint64 VP_ADDR_BRAM_RECT = 0;

// stages_array: 25 uint8 vrednosti (broj klasifikatora po fazi)
const uint64 VP_ADDR_BRAM_STAGES = VP_ADDR_BRAM_RECT + BRAM_RECT_SIZE;

// stages_thresh_array: 25 short int vrednosti (prag po fazi)
const uint64 VP_ADDR_BRAM_STAGES_TH = VP_ADDR_BRAM_STAGES + BRAM_STAGES_SIZE;

// weights_array: 8739 short int vrednosti
const uint64 VP_ADDR_BRAM_WEIGHTS = VP_ADDR_BRAM_STAGES_TH + BRAM_STAGES_TH_SIZE;

// alpha1_array: 2913 short int vrednosti
const uint64 VP_ADDR_BRAM_ALPHA1 = VP_ADDR_BRAM_WEIGHTS + BRAM_WEIGHTS_SIZE;

// alpha2_array: 2913 short int vrednosti
const uint64 VP_ADDR_BRAM_ALPHA2 = VP_ADDR_BRAM_ALPHA1 + BRAM_ALPHA1_SIZE;

// tree_thresh_array: 2913 short int vrednosti
const uint64 VP_ADDR_BRAM_TREE_TH = VP_ADDR_BRAM_ALPHA2 + BRAM_ALPHA2_SIZE;

// IP registri - lokalne adrese (nakon stripovanja od strane IC-a)
const uint64 VP_ADDR_IP_CFG_REG = VP_ADDR_IP + IP_CFG_REG_OFFSET;
const uint64 VP_ADDR_IP_P_OFFSET_REG = VP_ADDR_IP + IP_P_OFFSET_REG_OFFSET;
const uint64 VP_ADDR_IP_WIDTH_REG = VP_ADDR_IP + IP_WIDTH_REG_OFFSET;
const uint64 VP_ADDR_IP_RESULT_REG = VP_ADDR_IP + IP_RESULT_REG_OFFSET;
#endif
