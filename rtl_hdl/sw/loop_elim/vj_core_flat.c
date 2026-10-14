
#include "vj_core_flat.h"

static uint32_t cls_field(cls_word_t w, int lo, int n) {
  uint64_t v;
  if (lo >= 64)
    v = w.hi >> (lo - 64);
  else if (lo + n <= 64)
    v = w.lo >> lo;
  else
    v = (w.lo >> lo) | (w.hi << (64 - lo));
  return (uint32_t)(v & ((1u << n) - 1u));
}

static int32_t cls_sfield(cls_word_t w, int lo, int n) {
  uint32_t v = cls_field(w, lo, n);
  return (v & (1u << (n - 1))) ? (int32_t)v - (int32_t)(1u << n) : (int32_t)v;
}

static haar_rect_t rectangles_array(cls_word_t w, int k) {
  haar_rect_t r;
  int b = 20 * k;
  r.rx = (uint8_t)cls_field(w, b + 0, 5);
  r.ry = (uint8_t)cls_field(w, b + 5, 5);
  r.rw = (uint8_t)cls_field(w, b + 10, 5);
  r.rh = (uint8_t)cls_field(w, b + 15, 5);
  return r;
}

#define weight1_is_3(w) cls_field((w), 60, 1)
#define third_rect_present(w) cls_field((w), 61, 1)
#define tree_thresh_array(w) cls_sfield((w), 62, 13)
#define alpha1_array(w) cls_sfield((w), 75, 14)
#define alpha2_array(w) cls_sfield((w), 89, 14)

static uint8_t image_row(uint8_t row, uint8_t row_base) {
  uint16_t s = (uint16_t)row + row_base;
  return (uint8_t)((s >= N_INT_ROWS) ? s - N_INT_ROWS : s);
}

/* int_sqrt, unchanged from vj_core.cpp:27-44 */
static uint16_t int_sqrt(uint32_t value) {
  uint32_t a = 0, b, c = 0;
  int i;
  for (i = 0; i < 16; i++) {
    c = (c << 2) + (value >> 30);
    value <<= 2;
    a <<= 1;
    b = (a << 1) | 1u;
    if (c >= b) {
      c -= b;
      a++;
    }
  }
  return (uint16_t)a;
}

static int32_t haar_rect_sum(const vj_core_t *IP, const vj_mem_t *mem,
                             haar_rect_t r) {
  uint8_t row_t = image_row(r.ry, IP->row_base);
  uint8_t row_b = image_row(r.ry + r.rh, IP->row_base);
  uint32_t col_l = r.rx + IP->p_offset_reg;
  uint32_t col_r = r.rx + r.rw + IP->p_offset_reg;

  uint32_t img_tl = mem->int_img[row_t][col_l];
  uint32_t img_tr = mem->int_img[row_t][col_r];
  uint32_t img_bl = mem->int_img[row_b][col_l];
  uint32_t img_br = mem->int_img[row_b][col_r];

  return (int32_t)((img_tl + img_br) - (img_tr + img_bl));
}

static void accumulate_alpha(vj_core_t *IP) {
  int32_t sum_full = (int32_t)((uint32_t)IP->sum << WEIGHT_SHIFT);
  int32_t alpha = (sum_full >= IP->t) ? alpha2_array(IP->classifier)
                                      : alpha1_array(IP->classifier);
  IP->stage_sum = (int32_t)((uint32_t)IP->stage_sum + (uint32_t)alpha);
  IP->stage_sum = (IP->stage_sum << 8) >> 8;
}

void vj_core_step(vj_core_t *IP, const vj_mem_t *mem) {
  switch (IP->state) {

  case S_IDLE:
    IP->ip_interrupt = 0;
    if (IP->cfg_reg & (1u << IP_START_BIT))
      IP->state = S_WINDOW_INIT;
    break;

  case S_WINDOW_INIT:
    IP->haar_counter = 0;
    IP->i = 0;
    IP->j = 0;
    IP->hit_count = 0;
    IP->state = S_PV_ADDR;
    break;

  case S_PV_ADDR:
    IP->corner_row[0] = 0;
    IP->corner_col[0] = IP->p_offset_reg;
    IP->corner_row[1] = 0;
    IP->corner_col[1] = IP->p_offset_reg + ORIG_WIN_WIDTH - 1;
    IP->corner_row[2] = ORIG_WIN_HEIGHT - 1;
    IP->corner_col[2] = IP->p_offset_reg;
    IP->corner_row[3] = ORIG_WIN_HEIGHT - 1;
    IP->corner_col[3] = IP->p_offset_reg + ORIG_WIN_WIDTH - 1;
    IP->state = S_PV_FETCH;
    break;

  case S_PV_FETCH:
    IP->p[0] = mem->int_img[image_row(IP->corner_row[0], IP->row_base)]
                           [IP->corner_col[0]];
    IP->p[1] = mem->int_img[image_row(IP->corner_row[1], IP->row_base)]
                           [IP->corner_col[1]];
    IP->p[2] = mem->int_img[image_row(IP->corner_row[2], IP->row_base)]
                           [IP->corner_col[2]];
    IP->p[3] = mem->int_img[image_row(IP->corner_row[3], IP->row_base)]
                           [IP->corner_col[3]];
    IP->pq[0] = mem->sq_int[0][IP->corner_col[0]];
    IP->pq[1] = mem->sq_int[0][IP->corner_col[1]];
    IP->pq[2] = mem->sq_int[1][IP->corner_col[2]];
    IP->pq[3] = mem->sq_int[1][IP->corner_col[3]];
    IP->state = S_PV_LATCH;
    break;

  case S_PV_LATCH:
    IP->state = S_VNF_SUMS;
    break;

  case S_VNF_SUMS:
    IP->mean32 = (IP->p[0] + IP->p[3]) - (IP->p[1] + IP->p[2]);
    IP->pq_sum32 = (IP->pq[0] + IP->pq[3]) - (IP->pq[1] + IP->pq[2]);
    IP->state = S_VNF_MUL;
    break;

  case S_VNF_MUL:
    IP->vnf32 = (IP->pq_sum32 << 9) + (IP->pq_sum32 << 6); /* *576 */
    IP->mean_sq32 = IP->mean32 * IP->mean32;
    IP->state = S_VNF_SUB;
    break;

  case S_VNF_SUB:
    IP->vnf32 = IP->vnf32 - IP->mean_sq32;
    if (IP->vnf32 == 0) {
      IP->variance_norm_factor = 1;
      IP->sqrt_pending = 0;
    } else {
      IP->sqrt_pending = 1;
    }
    IP->state = S_VNF_SQRT;
    break;

  case S_VNF_SQRT:
    if (IP->sqrt_pending) {
      IP->variance_norm_factor = int_sqrt(IP->vnf32);
      IP->sqrt_pending = 0;
    }
    IP->state = S_STAGE_ENTER;
    break;

  case S_STAGE_ENTER:
    IP->num_classifiers = mem->stages_array[IP->i];
    IP->j = 0;
    IP->stage_sum = 0;
    IP->classifier_next = mem->classifier[IP->haar_counter];
    IP->state = S_CLS_FETCH;
    break;

  case S_CLS_FETCH:
    IP->classifier = IP->classifier_next;
    IP->state = S_RECT_0;
    break;

  case S_RECT_0: {
    haar_rect_t r = rectangles_array(IP->classifier, 0);
    IP->t = (int32_t)tree_thresh_array(IP->classifier) *
            (int32_t)IP->variance_norm_factor;
    IP->classifier_next = mem->classifier[IP->haar_counter + 1];
    IP->sum = -haar_rect_sum(IP, mem, r);
    IP->state = S_RECT_1;
    break;
  }

  /* k = 1*/
  case S_RECT_1: {
    haar_rect_t r = rectangles_array(IP->classifier, 1);
    int32_t rs = haar_rect_sum(IP, mem, r);
    IP->sum += weight1_is_3(IP->classifier) ? ((rs << 1) + rs) : (rs << 1);
    if (third_rect_present(IP->classifier)) {
      IP->state = S_RECT_2; /* iteratorski hold*/
    } else {
      accumulate_alpha(IP);
      IP->classifier = IP->classifier_next;
      IP->haar_counter++;
      IP->j++;
      IP->state = (IP->j >= IP->num_classifiers) ? S_CLS_FLUSH : S_RECT_0;
    }
    break;
  }

  /* k = 2 */
  case S_RECT_2: {
    haar_rect_t r = rectangles_array(IP->classifier, 2);
    IP->sum += (haar_rect_sum(IP, mem, r) << 1); /* weight 2 je 8192 */
    accumulate_alpha(IP);
    IP->classifier = IP->classifier_next;
    IP->haar_counter++;
    IP->j++;
    IP->state = (IP->j >= IP->num_classifiers) ? S_CLS_FLUSH : S_RECT_0;
    break;
  }

  /* dodatno stanje za praznjenje pipelinea*/
  case S_CLS_FLUSH:
    IP->state = S_STAGE_TEST;
    break;

  /**/
  case S_STAGE_TEST:
    if (IP->stage_sum * 5 < (int32_t)mem->stages_thresh_array[IP->i] * 2)
      IP->state = S_RETURN_REJECT;
    else if (IP->i == NUM_STAGES - 1)
      IP->state = S_RETURN_ACCEPT;
    else {
      IP->i++;
      IP->state = S_STAGE_ENTER;
    }
    break;

  /*return -i*/
  case S_RETURN_REJECT:
    IP->result_reg = -(int32_t)IP->i;
    IP->state = S_WINDOW_END;
    break;

  /*return 1*/
  case S_RETURN_ACCEPT:
    IP->result_reg = 1;
    if (IP->hit_count < HIT_LIST_LEN)
      IP->hit_list[IP->hit_count++] = (uint16_t)IP->p_offset_reg;
    IP->state = S_WINDOW_END;
    break;

  /**/
  case S_WINDOW_END:
    if ((IP->cfg_reg & (1u << IP_MODE_BIT)) &&
        IP->p_offset_reg + IP->p_offset_step <= IP->p_offset_last) {
      IP->p_offset_reg += IP->p_offset_step;
      IP->i = 0;
      IP->j = 0;
      IP->haar_counter = 0;
      IP->state = S_PV_ADDR; /* bypass S_WINDOW_INIT*/
    } else {
      IP->state = S_DONE;
    }
    break;

  case S_DONE:
    IP->cfg_reg |= (1u << IP_DONE_BIT);
    IP->cfg_reg &= (uint8_t)~(1u << IP_START_BIT);
    IP->ip_interrupt = 1;
    IP->state = S_IDLE;
    break;
  }
}

/*
 */
int32_t run_cascade_classifier(vj_core_t *IP, const vj_mem_t *mem,
                               uint32_t p_offset) {
  IP->p_offset_reg = p_offset;
  IP->cfg_reg |= (1u << IP_START_BIT);
  IP->ip_interrupt = 0;
  do {
    vj_core_step(IP, mem);
  } while (!IP->ip_interrupt);
  IP->cfg_reg &= (uint8_t)~(1u << IP_DONE_BIT);
  return IP->result_reg;
}
