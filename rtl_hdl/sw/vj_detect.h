/* vj_detect.h
 * Host-side polovina detektora lica: piramida skala, klizni integralni baferi, ucitavanja u redove, i grupisanje pravougaonika.
 Radi posao koji radi core1 u VP.
 */

#ifndef VJ_DETECT_H
#define VJ_DETECT_H

#include <stdint.h>
#include "vj_accel.h"
/*Kvantizacija u SystemC sc_ufixed<wl,iwl,SC_RND,SC_SAT> tip.*/
double vj_q_ufixed(double v,int wl,int iwl);
int vj_my_round(double v);

/* Funkcije za generisanje integralnih slika kao u VP */
void vj_integral_first(const uint8_t *img,int32_t *sum,int32_t *sqsum,int width,int height);
void vj_integral_lastrow(const uint8_t *img,int32_t *sum,int32_t *sqsum,int width,int sz_height,int y_bias);

/*Potpuna detekcija koja vraca broj lica*/
int vj_detect(const uint8_t *img,double scale_factor,int shift_step,vj_rect_t *faces,int max_faces);

/* Post-processing operacije grupisanja pravougaonika*/
int vj_group_rectangles(vj_rect_t *r, int n, int group_threshold, double eps);

#endif /* VJ_DETECT_H */
