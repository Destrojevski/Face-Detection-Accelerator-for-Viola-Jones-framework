/*
/ Naziv fajla: facedetect_fx.cpp
/ Opis: Implementacija facedetect modula sa parametarskim fixed-point aritmetikom. Svuda gdje originalna specifikacija koristi
/   sc_ufixed tip, ovdje se poziva to_fixed(val, W, F) sa parametrima iz FxParams strukture.
/ Datum: 25/12/2024
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/

#include "facedetect.h"
#include <math.h>

// klasifikacioni nizovi ucitani iz dat fajlova
static const int rectangles_array[34956] = {
    #include "../../data/rectangles_array.dat"
};
static const int stages_array[25] = {
    #include "../../data/stages_array.dat"
};
static const int weights_array[8739] = {
    #include "../../data/weights_array.dat"
};
static const int alpha1_array[2913] = {
    #include "../../data/alpha1_array.dat"
};
static const int alpha2_array[2913] = {
    #include "../../data/alpha2_array.dat"
};
static const int tree_thresh_array[2913] = {
    #include "../../data/tree_thresh_array.dat"
};
static const int stages_thresh_array[25] = {
    #include "../../data/stages_thresh_array.dat"
};

/*
/ Naziv funkcije: int_sqrt_fx
/ Parametri: unsigned int value - vrijednost nad kojom se racuna korijen
/ Povratna vrednost: unsigned int - cjelobrojna aproksimacija kvadratnog korijena
/ Opis funkcije: Funkcija koja racuna cjelobrojni kvadratni korijen metodom iterativnog priblizavanja. Identična originalnoj int_sqrt funkciji, ne koristi fixed-point aritmetiku.
*/
static unsigned int int_sqrt_fx(unsigned int value)
{
    int i;
    unsigned int a = 0, b = 0, c = 0;
    for (i = 0; i < (32 >> 1); i++) {
        c <<= 2;
        c += value >> 30;
        value <<= 2;
        a <<= 1;
        b = (a << 1) | 1;
        if (c >= b) { c -= b; a++; }
    }
    return a;
}

// pomocna funkcija koja racuna apsolutnu vrijednost broja
static int myAbs_fx(int n) { return n >= 0 ? n : -n; }

/*
/ Naziv funkcije: detection_main
/ Parametri: 
/   uint8_t image_data - ulazna slika dimenzija IMAGE_HEIGHT x IMAGE_WIDTH
/   float scaleFactor_val - faktor skaliranja piramide
/   uint8_t shiftStep_val - korak pomjeranja prozora u pikselima
/   FxParams params - parametri fixed-point formata za tekuci run
/ Povratna vrednost: int - broj detektovanih lica
/ Opis funkcije: Ulazna tacka za jedan sweep run. Kvantizuje scaleFactor na zadati fixed-point format, kopira sliku u interni bafer i pokrace detekciju.
*/
int facedetect::detection_main(uint8_t image_data[IMAGE_HEIGHT][IMAGE_WIDTH],
                                   float scaleFactor_val, uint8_t shiftStep_val,
                                   FxParams params)
{
    fx = params;

    // kvantizacija scaleFactor signala 
    scaleFactor = to_fixed(scaleFactor_val, fx.W_SF, fx.F_SF);
    shiftStep   = shiftStep_val;

    for (int i = 0; i < IMAGE_HEIGHT; i++)
        for (int j = 0; j < IMAGE_WIDTH; j++)
            in_img_buffer[i][j] = image_data[i][j];

    detectObjects(minSize, scaleFactor, minNeighbours, (int)shiftStep);
    return (int)face_number;
}

/*
/ Naziv funkcije: detectObjects
/ Parametri: 
/   MySize minSize - minimalna velicina prozora za detekciju
/   float scaleFactor - faktor skaliranja piramide
/   int minNeighbors - minimalan broj susjednih detekcija
/   int shift_step - korak pomjeranja prozora u pikselima
/ Povratna vrednost: nema
/ Opis funkcije: Funkcija koja izvrsava detekciju objekata prevlacenjem prozora sa skaliranjem slike. Varijabla factor kvantizovana je sa W_FAC/F_FAC formatom .
*/
void facedetect::detectObjects(MySize minSize, float scaleFactor, int minNeighbors, int shift_step)
{
    
    float GROUP_EPS = to_fixed(0.4f, fx.W_EPS, fx.F_EPS);

    int y_bias;
    float factor;
    MySize winSize0 = cascadeObj.orig_window_size;

    face_number = 0;

    for (factor = 1.0f; ; factor *= scaleFactor)
    {
        // kvantizacija factor varijable 
        float factor_fx = to_fixed(factor, fx.W_FAC, fx.F_FAC);

        MySize winSize = { myRound(winSize0.width  * factor_fx),
                           myRound(winSize0.height * factor_fx) };

        MySize sz = { (int)((float)IMAGE_WIDTH  / factor_fx),
                      (int)((float)IMAGE_HEIGHT / factor_fx) };

        if (sz.width < 24 || sz.height < 24) break;
        if (winSize.width < minSize.width || winSize.height < minSize.height) continue;

        nearestNeighbor(downsample_buffer, sz.width, sz.height);
        integralImages(downsample_buffer, int_img_buffer, sq_int_buffer, sz.width, 25);
        setImageForCascadeClassifier(int_img_buffer, sq_int_buffer, sz.width);

        for (y_bias = 0; y_bias < sz.height - 25 + 1; y_bias++) {
            if (y_bias != 0)
                integralmages_lastrow(downsample_buffer, int_img_buffer, sq_int_buffer, sz.width, y_bias);
            ScaleImage_Invoker(factor_fx, sz.width, shift_step, y_bias);
        }
    }

    if (minNeighbors != 0)
        groupRectangles(minNeighbors, GROUP_EPS);
}

/*
/ Naziv funkcije: setImageForCascadeClassifier
/ Parametri: 
/   int* sum - pokazivac na integralnu sliku
/   int* sqsum - pokazivac na kvadriranu integralnu sliku
/   int width - sirina tekuce skale slike
/ Povratna vrednost: nema
/ Opis funkcije: Funkcija koja priprema i podesava podatke potrebne za racunanje Haarovih karakteristika. Racuna i skalira indekse pravougaonika
/   za svaku fazu kaskadnog klasifikatora. Identična originalnoj, ne koristi fixed-point aritmetiku.
*/
void facedetect::setImageForCascadeClassifier(int* sum, int* sqsum, int width)
{
    int i, j, k;
    MyRect equRect;
    int r_index = 0, w_index = 0;
    MyRect tr;

    equRect.x = equRect.y = 0;
    equRect.width  = cascadeObj.orig_window_size.width;
    equRect.height = cascadeObj.orig_window_size.height;
    cascadeObj.inv_window_area = equRect.width * equRect.height;

    for (i = 0; i < 25; i++) {
        for (j = 0; j < stages_array[i]; j++) {
            for (k = 0; k < 3; k++) {
                tr.x      = rectangles_array[r_index + k*4];
                tr.width  = rectangles_array[r_index + 2 + k*4];
                tr.y      = rectangles_array[r_index + 1 + k*4];
                tr.height = rectangles_array[r_index + 3 + k*4];
                if (k < 2) {
                    scaled_rectangles_array[r_index + k*4]     = width*(tr.y)             + (tr.x);
                    scaled_rectangles_array[r_index + k*4 + 1] = width*(tr.y)             + (tr.x + tr.width);
                    scaled_rectangles_array[r_index + k*4 + 2] = width*(tr.y + tr.height) + (tr.x);
                    scaled_rectangles_array[r_index + k*4 + 3] = width*(tr.y + tr.height) + (tr.x + tr.width);
                } else {
                    if (tr.x == 0 && tr.y == 0 && tr.width == 0 && tr.height == 0) {
                        scaled_rectangles_array[r_index + k*4]     = -1;
                        scaled_rectangles_array[r_index + k*4 + 1] = -1;
                        scaled_rectangles_array[r_index + k*4 + 2] = -1;
                        scaled_rectangles_array[r_index + k*4 + 3] = -1;
                    } else {
                        scaled_rectangles_array[r_index + k*4]     = width*(tr.y)             + (tr.x);
                        scaled_rectangles_array[r_index + k*4 + 1] = width*(tr.y)             + (tr.x + tr.width);
                        scaled_rectangles_array[r_index + k*4 + 2] = width*(tr.y + tr.height) + (tr.x);
                        scaled_rectangles_array[r_index + k*4 + 3] = width*(tr.y + tr.height) + (tr.x + tr.width);
                    }
                }
            }
            r_index += 12;
            w_index += 3;
        }
    }
}

/*
/ Naziv funkcije: evalWeakClassifier
/ Parametri: 
/   int variance_norm_factor - normalizacioni faktor varijanse
/   int p_offset - pomak u integralnoj slici za tekuci prozor
/   int tree_index - indeks za nizove alpha1, alpha2 i tree_thresh
/   int w_index - indeks za niz weights
/   int r_index - indeks za niz scaled_rectangles
/ Povratna vrednost: int - tezina alpha1 ili alpha2 zavisno od odziva filtra
/ Opis funkcije: Funkcija koja izvrsava rad Haarovog filtra racunajuci sumu vrijednosti Haarovih karakteristika upotrebom indeksa pravougaonika
/   i tezina karakteristika i njihovim poredjenjem sa granicnom vrijednoscu. Identična originalnoj, radi sa int aritmetikom.
*/
int facedetect::evalWeakClassifier(int variance_norm_factor, int p_offset,
                                       int tree_index, int w_index, int r_index)
{
    int t = tree_thresh_array[tree_index] * variance_norm_factor;

    int sum = (int_img_buffer[scaled_rectangles_array[r_index]     + p_offset]
             - int_img_buffer[scaled_rectangles_array[r_index + 1] + p_offset]
             - int_img_buffer[scaled_rectangles_array[r_index + 2] + p_offset]
             + int_img_buffer[scaled_rectangles_array[r_index + 3] + p_offset])
             * weights_array[w_index];

    sum += (int_img_buffer[scaled_rectangles_array[r_index + 4] + p_offset]
          - int_img_buffer[scaled_rectangles_array[r_index + 5] + p_offset]
          - int_img_buffer[scaled_rectangles_array[r_index + 6] + p_offset]
          + int_img_buffer[scaled_rectangles_array[r_index + 7] + p_offset])
          * weights_array[w_index + 1];

    if (scaled_rectangles_array[r_index + 8] != -1)
        sum += (int_img_buffer[scaled_rectangles_array[r_index + 8]  + p_offset]
              - int_img_buffer[scaled_rectangles_array[r_index + 9]  + p_offset]
              - int_img_buffer[scaled_rectangles_array[r_index + 10] + p_offset]
              + int_img_buffer[scaled_rectangles_array[r_index + 11] + p_offset])
              * weights_array[w_index + 2];

    return (sum >= t) ? alpha2_array[tree_index] : alpha1_array[tree_index];
}

/*
/ Naziv funkcije: updatePvalue
/ Parametri: 
/   int* sum - pokazivac na integralnu sliku
/   int* sqsum - pokazivac na kvadriranu integralnu sliku
/   int p_offset - pomak za integralnu sliku
/   int pq_offset - pomak za kvadriranu integralnu sliku
/   int width - sirina tekuce skale slike
/ Povratna vrednost: nema
/ Opis funkcije: Funkcija koja azurira integralnu i kvadratnu integralnu sliku i priprema ih za dalje proracune tako sto izvlaci vrijednosti
/   coskova integralne i kvadrirane integralne slike za trenutni detekcijski prozor i skladisti ih u cascadeObj za dalju obradu.
/   Identična originalnoj, ne koristi fixed-point aritmetiku.
*/
void facedetect::updatePvalue(int* sum, int* sqsum, int p_offset, int pq_offset, int width)
{
    cascadeObj.p0  = sum[0 + p_offset];
    cascadeObj.p1  = sum[cascadeObj.orig_window_size.width - 1 + p_offset];
    cascadeObj.p2  = sum[width*(cascadeObj.orig_window_size.height - 1) + p_offset];
    cascadeObj.p3  = sum[width*(cascadeObj.orig_window_size.height - 1) + cascadeObj.orig_window_size.width - 1 + p_offset];
    cascadeObj.pq0 = sqsum[0 + pq_offset];
    cascadeObj.pq1 = sqsum[cascadeObj.orig_window_size.width - 1 + pq_offset];
    cascadeObj.pq2 = sqsum[width*(cascadeObj.orig_window_size.height - 1) + pq_offset];
    cascadeObj.pq3 = sqsum[width*(cascadeObj.orig_window_size.height - 1) + cascadeObj.orig_window_size.width - 1 + pq_offset];
}

/*
/ Naziv funkcije: runCascadeClassifier
/ Parametri: 
/   MyPoint pt - tekuca pozicija prozora
/   int start_stage - pocetna faza kaskade
/   int width - sirina tekuce skale slike
/ Povratna vrednost: int - pozitivna vrijednost ako je lice pronadjeno, negativna inace
/ Opis funkcije: Funkcija koja provlaci sliku kroz kaskadu rastuce kompleksnih klasifikacija (faza) i vrsi detekciju lica. 
/ Threshold koristi eps kvantizovan sa W_EPS/F_EPS formatom.
*/
int facedetect::runCascadeClassifier(MyPoint pt, int start_stage, int width)
{
    int p_offset  = pt.y * width + pt.x;
    int pq_offset = pt.y * width + pt.x;
    int i, j;
    unsigned int mean, variance_norm_factor;
    int haar_counter = 0, w_index = 0, r_index = 0, stage_sum;

    updatePvalue(int_img_buffer, sq_int_buffer, p_offset, pq_offset, width);

    variance_norm_factor = (cascadeObj.pq0 - cascadeObj.pq1 - cascadeObj.pq2 + cascadeObj.pq3);
    mean = (cascadeObj.p0 - cascadeObj.p1 - cascadeObj.p2 + cascadeObj.p3);
    variance_norm_factor = variance_norm_factor * cascadeObj.inv_window_area;
    variance_norm_factor = variance_norm_factor - mean * mean;

    if (variance_norm_factor > 0)
        variance_norm_factor = int_sqrt_fx(variance_norm_factor);
    else
        variance_norm_factor = 1;

    for (i = start_stage; i < 25; i++) {
        stage_sum = 0;
        for (j = 0; j < 200; j++) {
            if (j >= stages_array[i]) break;
            stage_sum += evalWeakClassifier(variance_norm_factor, p_offset, haar_counter, w_index, r_index);
            haar_counter++;
            w_index += 3;
            r_index += 12;
        }
        // kvantizacija praga 0.4 na isti format kao eps 
        float thresh_factor = to_fixed(0.4f, fx.W_EPS, fx.F_EPS);
        if (stage_sum < (int)(thresh_factor * stages_thresh_array[i]))
            return -i;
    }
    return 1;
}

/*
/ Naziv funkcije: ScaleImage_Invoker
/ Parametri: 
/   float factor - tekuci faktor skaliranja (vec kvantizovan)
/   int sum_col - broj kolona integralne slike
/   int shift_step - korak pomjeranja prozora
/   int y_bias - vertikalni pomak tekuceg reda
/ Povratna vrednost: nema
/ Opis funkcije: Funkcija koja izvrsava detekciju objekata prevlacenjem prozora sa skaliranjem slike. Factor je vec kvantizovan u detectObjects,
/   a myRound koristi W_RND/F_RND kvantizaciju za koordinate.
*/
void facedetect::ScaleImage_Invoker(float factor, int sum_col, int shift_step, int y_bias)
{
    MyPoint p;
    int result, x2, x;
    MySize winSize0 = cascadeObj.orig_window_size;
    MySize winSize  = { myRound(winSize0.width  * factor),
                        myRound(winSize0.height * factor) };

    x2  = sum_col - winSize0.width;
    p.y = 0;

    for (x = 0; x <= x2 - 1; x += shift_step) {
        p.x    = x;
        result = runCascadeClassifier(p, 0, sum_col);
        if (result > 0) {
            face_coordinate[face_number][0] = (uint16_t)myRound(x      * factor);
            face_coordinate[face_number][1] = (uint16_t)myRound(y_bias * factor);
            face_coordinate[face_number][2] = (uint16_t)winSize.width;
            face_coordinate[face_number][3] = (uint16_t)winSize.height;
            if (face_number < MAX_NUM_FACE - 1) face_number++;
        }
    }
}

/*
/ Naziv funkcije: integralImages
/ Parametri: 
/   uint8_t src - ulazna slika
/   int* sumData - izlazni niz integralne slike
/   int* sqsumData - izlazni niz kvadrirane integralne slike
/   int width - sirina slike
/   int height - visina slike
/ Povratna vrednost : nema
/ Opis funkcije: Funkcija koja izvrsava proracune integralnih i kvadratnih integralnih slika koje pomazu da se odredjena oblast slike brzo
/   sumira. Identična originalnoj, radi sa uint8 i int aritmetikom.
*/
void facedetect::integralImages(uint8_t src[IMAGE_HEIGHT][IMAGE_WIDTH],
                                    int *sumData, int *sqsumData, int width, int height)
{
    int x, y, s, sq, t, tq;
    unsigned char it;
    for (y = 0; y < height; y++) {
        s = 0; sq = 0;
        for (x = 0; x < width; x++) {
            it = src[y][x];
            s += it; sq += it * it;
            t = s; tq = sq;
            if (y != 0) { t += sumData[(y-1)*width+x]; tq += sqsumData[(y-1)*width+x]; }
            sumData[y*width+x]   = t;
            sqsumData[y*width+x] = tq;
        }
    }
}

/*
/ Naziv funkcije: integralmages_lastrow
/ Parametri: 
/   uint8_t src - ulazna slika
/   int* sumData - niz integralne slike
/   int* sqsumData - niz kvadrirane integralne slike
/   int width - sirina slike
/   int y_bias - vertikalni pomak tekuceg reda
/ Povratna vrednost: nema
/ Opis funkcije: Funkcija koja izvrsava proracune integralnih i kvadratnih integralnih slika. Razlika u odnosu na integralImages funkciju  je to sto je
/   ova funkcija pravljena posebno za posljednji red, tj. pomjera se bafer i samo se posljednji red azurira.
*/
void facedetect::integralmages_lastrow(uint8_t src[IMAGE_HEIGHT][IMAGE_WIDTH],
                                           int *sumData, int *sqsumData, int width, int y_bias)
{
    int x, y, s, sq, t, tq;
    unsigned char it;
    for (y = 0; y < 24; y++)
        for (x = 0; x < width; x++) {
            sumData[y*width+x]   = sumData[(y+1)*width+x];
            sqsumData[y*width+x] = sqsumData[(y+1)*width+x];
        }
    s = 0; sq = 0;
    for (x = 0; x < width; x++) {
        it = src[24 + y_bias][x];
        s += it; sq += it * it;
        t  = s  + sumData[23*width+x];
        tq = sq + sqsumData[23*width+x];
        sumData[24*width+x]   = t;
        sqsumData[24*width+x] = tq;
    }
}

/*
/ Naziv funkcije: nearestNeighbor
/ Parametri: 
/   uint8_t dst - izlazni bafer za resizovanu sliku
/   int width - ciljna sirina
/   int height - ciljna visina
/ Povratna vrednost: nema
/ Opis funkcije: Funkcija koja izvrsava downsampling slike upotrebom nearest-neighbor metode za interpolaciju gdje svaki piksel u
/   resized slici odgovara najblizem pikselu u originalnoj slici. Koristi se za izgradnju piramide slika za detekciju lica.
*/
void facedetect::nearestNeighbor(uint8_t dst[IMAGE_HEIGHT][IMAGE_WIDTH], int width, int height)
{
    int w1 = IMAGE_WIDTH, h1 = IMAGE_HEIGHT;
    int x_ratio = (int)((w1 << 16) / width)  + 1;
    int y_ratio = (int)((h1 << 16) / height) + 1;
    for (int i = 0; i < height; i++) {
        int y   = ((i * y_ratio) >> 16);
        int rat = 0;
        for (int j = 0; j < width; j++) {
            int x     = (rat >> 16);
            dst[i][j] = in_img_buffer[y][x];
            rat += x_ratio;
        }
    }
}

/*
/ Naziv funkcije: groupRectangles
/ Parametri: 
/   int groupThreshold - minimalan broj pravougaonika u grupi
/   float eps_val - granicna vrijednost preklapanja pravougaonika
/ Povratna vrednost: nema
/ Opis funkcije: Funkcija koja izvrsava grupisanje detektovanih pravougaonika lica bazirano na metodi klasterovanja i granici preklapanja.
/   Objedinjuje preklopljene pravougaonike u vece, smanjujuci redundantnost detekcija. Eps je kvantizovan sa W_EPS/F_EPS formatom.
*/
void facedetect::groupRectangles(int groupThreshold, float eps_val)
{
    if (groupThreshold <= 0 || face_number == 0) return;

    // kvantizacija eps parametra 
    float eps = to_fixed(eps_val, fx.W_EPS, fx.F_EPS);

    int labels[MAX_NUM_FACE];
    int nclasses = partition(labels, eps);

    MyRect rrects[MAXLABELS];
    int    rweights[MAXLABELS];
    int i, j, nlabels = face_number;

    for (i = 0; i < nclasses; i++) {
        rrects[i].x = rrects[i].y = rrects[i].width = rrects[i].height = 0;
        rweights[i] = 0;
    }
    for (i = 0; i < nlabels; i++) {
        int cls = labels[i];
        rrects[cls].x      += face_coordinate[i][0];
        rrects[cls].y      += face_coordinate[i][1];
        rrects[cls].width  += face_coordinate[i][2];
        rrects[cls].height += face_coordinate[i][3];
        rweights[cls]++;
    }
    for (i = 0; i < nclasses; i++) {
        MyRect r = rrects[i];
        // s = 1/rweights
        float s = to_fixed(1.0f / rweights[i], fx.W_S, fx.F_S);
        rrects[i].x = myRound(r.x* s);
        rrects[i].y = myRound(r.y* s);
        rrects[i].width  = myRound(r.width*s);
        rrects[i].height = myRound(r.height*s);
    }

    face_number = 0;
    for (i = 0; i < nclasses; i++) {
        MyRect r1 = rrects[i];
        int    n1 = rweights[i];
        if (n1 <= groupThreshold) continue;
        for (j = 0; j < nclasses; j++) {
            int n2 = rweights[j];
            if (j == i || n2 <= groupThreshold) continue;
            MyRect r2 = rrects[j];
            int dx = myRound(r2.width  * eps);
            int dy = myRound(r2.height * eps);
            if (r1.x >= r2.x - dx &&
                r1.y >= r2.y - dy &&
                r1.x + r1.width  <= r2.x + r2.width  + dx &&
                r1.y + r1.height <= r2.y + r2.height + dy &&
                (n2 > ((3 > n1) ? 3 : n1) || n1 < 3))
                break;
        }
        if (j == nclasses) {
            face_coordinate[face_number][0] = (uint16_t)r1.x;
            face_coordinate[face_number][1] = (uint16_t)r1.y;
            face_coordinate[face_number][2] = (uint16_t)r1.width;
            face_coordinate[face_number][3] = (uint16_t)r1.height;
            if (face_number < MAX_NUM_FACE - 1) face_number++;
        }
    }
}

/*
/ Naziv funkcije: partition
/ Parametri: 
/   int* labels - niz labela za svaki detektovani pravougaonik
/   float eps_val - prag tolerancije koji odredjuje koliko slicna lica moraju biti da bi bila u istoj grupi
/ Povratna vrednost: int - broj prepoznatih klasa (lica)
/ Opis funkcije: Funkcija koja od niza labela pronalazi broj lica tako sto iz labela nalazi roditeljsko lice i pravi stablo sve dok ne dodje do najstarijeg lica (root).
/   Broj root-ova je broj lica.
*/
int facedetect::partition(int* labels, float eps_val)
{
    int i, j;
    int N = face_number;
    const int _PArent = 0, _RAnk = 1;
    int nodes[MAX_NUM_FACE][2];

    for (i = 0; i < N; i++) { nodes[i][_PArent] = -1; nodes[i][_RAnk] = 0; }

    for (i = 0; i < N; i++) {
        int root = i;
        while (nodes[root][_PArent] >= 0) root = nodes[root][_PArent];
        for (j = 0; j < N; j++) {
            if (i == j || !predicate(eps_val, face_coordinate[i], face_coordinate[j])) continue;
            int root2 = j;
            while (nodes[root2][_PArent] >= 0) root2 = nodes[root2][_PArent];
            if (root2 != root) {
                int rank = nodes[root][_RAnk], rank2 = nodes[root2][_RAnk];
                if (rank > rank2) nodes[root2][_PArent] = root;
                else { nodes[root][_PArent] = root2; nodes[root2][_RAnk] += (rank == rank2); root = root2; }
                int k = j, parent;
                while ((parent = nodes[k][_PArent]) >= 0) { nodes[k][_PArent] = root; k = parent; }
                k = i;
                while ((parent = nodes[k][_PArent]) >= 0) { nodes[k][_PArent] = root; k = parent; }
            }
        }
    }
    int nclasses = 0;
    for (i = 0; i < N; i++) {
        int root = i;
        while (nodes[root][_PArent] >= 0) root = nodes[root][_PArent];
        if (nodes[root][_RAnk] >= 0) nodes[root][_RAnk] = ~nclasses++;
        labels[i] = ~nodes[root][_RAnk];
    }
    return nclasses;
}

/*
/ Naziv funkcije    : predicate
/ Parametri         : float eps_val - prag tolerancije preklapanja
/  uint16_t r1[4] - koordinate prvog pravougaonika (x,y,w,h)
/  uint16_t r2[4] - koordinate drugog pravougaonika (x,y,w,h)
/ Povratna vrednost : int - 1 ako su pravougaonici dovoljno slicni, 0 ako nisu
/ Opis funkcije     : Funkcija poredi dva pravougaonika i odredjuje da li su dovoljno slicni za grupisanje. Delta je kvantizovana sa W_DEL/F_DEL formatom 
*/
int facedetect::predicate(float eps_val, uint16_t r1[4], uint16_t r2[4])
{
    float delta_raw = 0.5f * eps_val * (float)(((r1[2] > r2[2]) ? r2[2] : r1[2])
                                              + ((r1[3] > r2[3]) ? r2[3] : r1[3]));
    float delta = to_fixed(delta_raw, fx.W_DEL, fx.F_DEL);
    int d = (int)delta;
    return myAbs_fx(r1[0] - r2[0]) <= d &&
           myAbs_fx(r1[1] - r2[1]) <= d &&
           myAbs_fx(r1[0] + r1[2] - r2[0] - r2[2]) <= d &&
           myAbs_fx(r1[1] + r1[3] - r2[1] - r2[3]) <= d;
}

/* Kraj fajla. */
