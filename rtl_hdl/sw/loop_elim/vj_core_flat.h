
#ifndef VJ_CORE_FLAT_H
#define VJ_CORE_FLAT_H

#include <stdint.h>

/*konstante*/
#define NUM_STAGES 25
#define NUM_CLASSIFIERS 2913
#define ORIG_WIN_WIDTH 24
#define ORIG_WIN_HEIGHT 24
#define INV_WINDOW_AREA 576

/*konstante banke*/
#define N_INT_ROWS 25
#define N_SQ_ROWS 2
#define ROW_LEN 512
#define HIT_LIST_LEN 512
#define WEIGHT_SHIFT 12

/*cfg_reg bits*/
#define IP_RESET_BIT 0
#define IP_START_BIT 1
#define IP_MODE_BIT 2 /*0 = window, 1 = sweep*/
#define IP_DONE_BIT 4

typedef struct {
  uint64_t lo, hi;
} cls_word_t; /* 112 bits */
typedef struct {
  uint8_t rx, ry, rw, rh;
} haar_rect_t;

/* Stanja*/
typedef enum {
  S_IDLE,          /* case IDLE:*/
  S_WINDOW_INIT,   /* run_cascade_classifier :101-103*/
  S_PV_ADDR,       /* update_pvalue: corners[]*/
  S_PV_FETCH,      /* update_pvalue: stara citanja iz ddr3*/
  S_PV_LATCH,      /* update_pvalue: p[] i pq[]*/
  S_VNF_SUMS,      /* mean32, pq_sum32*/
  S_VNF_MUL,       /* *INV_WINDOW_AREA, mean32*mean32*/
  S_VNF_SUB,       /* vnf32 -= mean_sq32*/
  S_VNF_SQRT,      /* int_sqrt*/
  S_STAGE_ENTER,   /* zaglavlje i petlje*/
  S_CLS_FETCH,     /* zaglavlje j petlje,citanje klasifikatora*/
  S_RECT_0,        /* k = 0*/
  S_RECT_1,        /* k = 1*/
  S_RECT_2,        /* k = 2*/
  S_CLS_FLUSH,     /* stanje za planirani pipeline*/
  S_STAGE_TEST,    /* test faze*/
  S_RETURN_REJECT, /* return -i*/
  S_RETURN_ACCEPT, /* return 1*/
  S_WINDOW_END,    /* x sweep*/
  S_DONE           /* cfg_reg DONE, interrupt*/
} ip_state_t;

typedef struct {
  ip_state_t state;

  /*memorijski mapirani registri*/
  uint8_t cfg_reg;
  uint32_t p_offset_reg;
  uint32_t width_reg; /*ne koristi se zbog promjene adresiranja*/
  int32_t result_reg;
  uint8_t ip_interrupt;

  /*iteratori petlji*/
  uint8_t i;                /* indeks faze, int i*/
  uint16_t j;               /*int j*/
  uint16_t num_classifiers; /*a sa linije 129*/
  uint16_t haar_counter;    /*haar_counter*/

  /*update_pvalue*/
  uint8_t corner_row[4];
  uint16_t corner_col[4];
  uint32_t p[4];
  uint32_t pq[4];

  /*normalizacija varijanse*/
  uint32_t mean32;
  uint32_t pq_sum32;
  uint32_t mean_sq32; /*mean32*mean32*/
  uint32_t vnf32;
  uint16_t variance_norm_factor;
  uint8_t sqrt_pending; /*oznaka da sqrt traje vise ciklusa*/

  /*evaluacija slabih klasifikatora*/
  cls_word_t classifier;      /*tree_thresh, rect, weight, alpha */
  cls_word_t classifier_next; /*prefetch, baza za pipeline  */
  int32_t t;                  /*ap_int<32> t*/
  int32_t sum;                /*suma */
  int32_t stage_sum;          /*suma faze*/

  /* sweep mode i hit lista*/
  uint32_t p_offset_last, p_offset_step;
  uint8_t row_base; /*rotacija redova*/
  uint16_t hit_list[HIT_LIST_LEN];
  uint16_t hit_count;
} vj_core_t;

/*
 * Memorija
 */
typedef struct {
  uint32_t int_img[N_INT_ROWS][ROW_LEN];
  uint32_t sq_int[N_SQ_ROWS][ROW_LEN];
  cls_word_t classifier[NUM_CLASSIFIERS + 1];
  uint8_t stages_array[NUM_STAGES];
  int16_t stages_thresh_array[NUM_STAGES];
} vj_mem_t;

void vj_core_step(vj_core_t *IP, const vj_mem_t *mem);
int32_t run_cascade_classifier(vj_core_t *IP, const vj_mem_t *mem,
                               uint32_t p_offset);

#endif
