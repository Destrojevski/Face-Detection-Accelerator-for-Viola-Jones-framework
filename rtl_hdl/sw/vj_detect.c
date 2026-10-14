/* vj_detect.c
 * Radi posao koji je core1 radio u VP, ali umjesto citavih bafera, azurira samo ono sto se promijenilo
 integralna slika : 25 row bankova se rotira za vrijednost row_base, pa je zapravo 
 pomjeranje y_biasa upis jednog novog reda i povecanje row_base.
 Pomjeranje bloka od 24 reda potpuno nestaje iz hardvera.
 kvadrirana integralna slika: poslije promjena u dizajnu samo redovi 0 i 23 postoje u hardveru, i oba se mijenjaju
 u svakom koraku: dakle azuriraju se dva reda.
 Ovim se broj rijeci po biasu smanji za oko 18 puta, sto ubrzava detekciju, u suprotnom je overhead preveliki
 i akceleracija gubi smisao.
 */

#include "vj_detect.h"
#include <math.h>
#include <string.h>

/*Emulacija rada sa fiksnom tackom kao u SystemC VP*/

double vj_q_ufixed(double v,int wl,int iwl)
{
    int fw = wl - iwl;/*razlomljeni bitovi*/
    double scale = (double)(1u << fw);
    double maxv  = (double)((1u << wl) - 1u) / scale;
    double r;
    if (v < 0.0) v = 0.0;//unsigned
    r = floor(v * scale + 0.5) / scale;//SC_RND   
    if (r > maxv) r = maxv;//SC_SAT   
    return r;
}

/* myRound() MAKRO implementacija iz VP */
int vj_my_round(double v)
{
    return (int)(vj_q_ufixed(v, 16, 12) + 0.5);
}

/* Funkcije za rad s integralnim baferima (nearest-neighbour downscale + integralne sume)*/

void vj_integral_first(const uint8_t *img,int32_t *sum,int32_t *sqsum,int width,int height)
{
    int x_ratio = (int)((VJ_IMG_WIDTH  << 16) / width)  + 1;
    int y_ratio = (int)((VJ_IMG_HEIGHT << 16) / height) + 1;

    for (int i = 0;i < VJ_INT_ROWS;i++) {
        int src_i = (i*y_ratio) >> 16;
        if (src_i >= VJ_IMG_HEIGHT) src_i =VJ_IMG_HEIGHT - 1;
        int rat=0,s=0,sq=0;
        for (int j = 0;j < width;j++) {
            int src_j = rat >> 16;
            if (src_j >= VJ_IMG_WIDTH) src_j =VJ_IMG_WIDTH - 1;
            rat += x_ratio;

            int pix = img[src_i * VJ_IMG_WIDTH + src_j];
            s += pix;
            sq += pix * pix;
            int32_t above = i ? sum[(i - 1) * width + j] : 0;
            int32_t above_sq = i ? sqsum[(i - 1) * width + j] : 0;
            sum[i * width + j] = s + above;
            sqsum[i * width + j] = sq + above_sq;
        }
    }
}

void vj_integral_lastrow(const uint8_t *img,int32_t *sum,int32_t *sqsum,int width,int sz_height,int y_bias)
{
    int x_ratio = (int)((VJ_IMG_WIDTH  << 16) / width)     + 1;
    int y_ratio = (int)((VJ_IMG_HEIGHT << 16) / sz_height) + 1;

    /* pomjeranje lokalnih kopija za jedan red. U hardveru nema nikakvu cijenu, row_base se sam pomjera */
    for (int y = 0; y < VJ_INT_ROWS - 1; y++) {
        memmove(&sum[y * width],&sum[(y + 1) * width],width * sizeof(int32_t));
        memmove(&sqsum[y * width],&sqsum[(y + 1) * width],width * sizeof(int32_t));
    }
    int src_i = ((VJ_WIN + y_bias) * y_ratio) >> 16;
    if (src_i >= VJ_IMG_HEIGHT) src_i = VJ_IMG_HEIGHT - 1;
    int rat=0,s=0,sq=0;
    for (int x = 0;x < width;x++) {
        int src_j = rat >> 16;
        if (src_j >= VJ_IMG_WIDTH) src_j = VJ_IMG_WIDTH - 1;
        rat += x_ratio;
        int pix = img[src_i * VJ_IMG_WIDTH + src_j];
        s += pix;
        sq += pix * pix;
        sum[24 * width + x] = s + sum[23 * width + x];
        sqsum[24 * width + x] = sq + sqsum[23 * width + x];
    }
}

/* Glavna detekcijska funkcija */
static int32_t g_int[VJ_INT_ROWS * VJ_IMG_WIDTH];
static int32_t g_sq [VJ_INT_ROWS * VJ_IMG_WIDTH];
int vj_detect(const uint8_t *img,double scale_factor,int shift_step,vj_rect_t *faces,int max_faces)
{
    /*VP cuva scalefactor kao sc_ufixed<8,1>: 1.2 se pretvara u 1.203125. */
    double sf = vj_q_ufixed(scale_factor,8,1);
    double factor = 1.0;
    int nf = 0;
    for (;;) {
        int sz_w = (int)(VJ_IMG_WIDTH / factor);
        int sz_h = (int)(VJ_IMG_HEIGHT / factor);
        int win_w = vj_my_round(VJ_WIN * factor);
        int win_h = vj_my_round(VJ_WIN * factor);
        if (sz_w < VJ_WIN || sz_h < VJ_WIN)
            break;
        if (win_w < 20 || win_h < 20) {            //minSize iz VP
            factor = vj_q_ufixed(factor * sf,10,5);
            continue;
        }
        vj_set_width((unsigned)sz_w);
        /*y_bias = 0 znaci da je bafer potpuno nov*/
        vj_integral_first(img,g_int,g_sq,sz_w,sz_h);
        unsigned row_base = 0;
        vj_set_row_base(row_base);
        for (int r = 0;r < VJ_INT_ROWS;r++)
            vj_upload_row((unsigned)r,&g_int[r * sz_w],sz_w);
        vj_upload_row(VJ_BANK_SQ0,&g_sq[0  * sz_w],sz_w);
        vj_upload_row(VJ_BANK_SQ23,&g_sq[23 * sz_w],sz_w);
        int x2 = sz_w - VJ_WIN;
        int x_hi = x2 - 1;
        if (x_hi < 0) {
            factor = vj_q_ufixed(factor * sf,10,5);
            continue;
        }
        int x_last = (x_hi / shift_step) * shift_step;
        unsigned hits = vj_run_sweep(0,(unsigned)x_last,(unsigned)shift_step);
        for (unsigned k = 0;k < hits && nf < max_faces;k++) {
            int hx = (int)vj_hit(k);
            faces[nf].x = vj_my_round(hx * factor);
            faces[nf].y = 0;
            faces[nf].w = win_w;
            faces[nf].h = win_h;
            nf++;
        }

        /*prevlacenje prozora preko slike*/
        for (int y_bias = 1;y_bias < sz_h - VJ_INT_ROWS + 1;y_bias++) {
            vj_integral_lastrow(img,g_int,g_sq,sz_w,sz_h,y_bias);
            /*Banka koja se povlaci dobija novi donji red, nakon cega se rotacija pomjera
ovo mijenja kopiranje 24 reda iz VP i ponovno ucitavanje oba bafera. */
            vj_upload_row(row_base,&g_int[24 * sz_w],sz_w);
            row_base = (row_base + 1) % VJ_N_INT_BANKS;
            vj_set_row_base(row_base);
            vj_upload_row(VJ_BANK_SQ0,&g_sq[0  * sz_w],sz_w);
            vj_upload_row(VJ_BANK_SQ23,&g_sq[23 * sz_w],sz_w);
            hits = vj_run_sweep(0,(unsigned)x_last,(unsigned)shift_step);
            for (unsigned k = 0;k < hits && nf < max_faces;k++) {
                int hx = (int)vj_hit(k);
                faces[nf].x = vj_my_round(hx * factor);
                faces[nf].y = vj_my_round(y_bias * factor);
                faces[nf].w = win_w;
                faces[nf].h = win_h;
                nf++;
            }
        }

        factor = vj_q_ufixed(factor * sf,10,5);
    }
    return vj_group_rectangles(faces,nf,1,0.4);
}

/* groupRectangles direktno iz VP */
static int vj_abs(int v) { return v < 0 ? -v : v; }
static int predicate(double eps,const vj_rect_t *r1,const vj_rect_t *r2)
{
    double delta = vj_q_ufixed(0.5 * eps * ((r1->w > r2->w ? r2->w : r1->w) +(r1->h > r2->h ? r2->h : r1->h)),16,8);
    return vj_abs(r1->x - r2->x) <= delta && vj_abs(r1->y - r2->y) <= delta && vj_abs(r1->x + r1->w - r2->x - r2->w) <= delta && vj_abs(r1->y + r1->h - r2->y - r2->h) <= delta;
}

static int partition_rects(const vj_rect_t *r,int n,int *labels,double eps)
{
    int parent[VJ_MAX_FACES], rank[VJ_MAX_FACES];
    for (int i = 0;i < n;i++) { parent[i] = -1;rank[i] = 0; }
    for (int i = 0;i < n;i++) {
        int root = i;
        while (parent[root] >= 0) root = parent[root];
        for (int j = 0;j < n;j++) {
            if (i == j || !predicate(eps,&r[i],&r[j])) continue;
            int root2 = j;
            while (parent[root2] >= 0) root2 = parent[root2];
            if (root2 != root) {
                if (rank[root] > rank[root2]) {
                    parent[root2] = root;
                } else {
                    parent[root] = root2;
                    if (rank[root] == rank[root2]) rank[root2]++;
                    root = root2;
                }

                int k =j,p;
                while ((p = parent[k]) >= 0) { parent[k] = root; k = p; }
                k = i;
                while ((p = parent[k]) >= 0) { parent[k] = root; k = p; }
            }
        }
    }
    int nclasses = 0;
    for (int i = 0;i < n;i++) {
        int root = i;
        while (parent[root] >= 0) root = parent[root];
        if (rank[root] >= 0) rank[root] = ~nclasses++;
        labels[i] = ~rank[root];
    }
    return nclasses;
}

int vj_group_rectangles(vj_rect_t *r,int n,int group_threshold,double eps)
{
    if (group_threshold <= 0 || n == 0)
        return n;
    int labels[VJ_MAX_FACES];
    int nclasses = partition_rects(r,n,labels,eps);
    vj_rect_t acc[VJ_MAX_FACES];
    int cnt[VJ_MAX_FACES];
    for (int i = 0;i < nclasses;i++) {
        acc[i].x = acc[i].y = acc[i].w = acc[i].h = 0;
        cnt[i] = 0;
    }
    for (int i = 0;i < n;i++) {
        int c = labels[i];
        acc[c].x += r[i].x; acc[c].y += r[i].y;
        acc[c].w += r[i].w; acc[c].h += r[i].h;
        cnt[c]++;
    }
    for (int i = 0;i < nclasses;i++) {
        double s = vj_q_ufixed(1.0 / cnt[i],10,1);
        acc[i].x = vj_my_round(acc[i].x * s);
        acc[i].y = vj_my_round(acc[i].y * s);
        acc[i].w = vj_my_round(acc[i].w * s);
        acc[i].h = vj_my_round(acc[i].h * s);
    }
    int out = 0;
    for (int i = 0;i < nclasses;i++) {
        int n1 = cnt[i];
        if (n1 <= group_threshold) continue;
        int j;
        for (j = 0;j < nclasses;j++) {
            if (j == i) continue;
            int n2 = cnt[j];
            if (n2 <= group_threshold) continue;
            int dx = vj_my_round(acc[j].w * eps);
            int dy = vj_my_round(acc[j].h * eps);
            if (acc[i].x >= acc[j].x - dx && acc[i].y >= acc[j].y - dy && acc[i].x + acc[i].w <= acc[j].x + acc[j].w + dx && acc[i].y + acc[i].h <= acc[j].y + acc[j].h + dy && (n2 > (3 > n1 ? 3 : n1) || n1 < 3))
                break;
        }
        if (j == nclasses && out < VJ_MAX_FACES)
            r[out++] = acc[i];
    }
    return out;
}
