#ifndef __HAAR_H__
#define __HAAR_H__

/*
/ Naziv fajla: facedetect_fx.h
/ Opis: Verzija facedetect modula sa parametarskim fixed-point tipovima za potrebe bit-width analize. Svaka sc_ufixed varijabla iz
/   originalne specifikacije zamjenjena je pozivom to_fixed(val, W, F) gdje su W i F parametri koji se mijenjaju u sweep petlji.
/ Datum: 25/12/2024
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/

/*
/ Zakljucno iz ove analize, optimalne vrijednosti su sljedece :
/   scaleFactor       - sc_ufixed<8,1>   - W_SF,  F_SF   (1 integer bit)
/   factor (petlja)   - sc_ufixed<10,5>  - W_FAC, F_FAC  (5 integer bita)
/   GROUP_EPS / eps   - sc_ufixed<8,1>   - W_EPS, F_EPS  (1 integer bit)
/   delta (predicate) - sc_ufixed<16,8>  - W_DEL, F_DEL  (8 integer bita)
/   s (1/rweights)    - sc_ufixed<10,1>  - W_S,   F_S    (1 integer bit)
/   myRound argument  - sc_ufixed<16,12> - W_RND, F_RND  (4 integer bita)
*/

#include "define.h"
#include "fixedpoint.h"

/*
/ Naziv strukture: FxParams
/ Opis: Struktura koja sadrzi parametre fixed-point formata za svaku sc_ufixed varijablu. 
/   Vrijednosti se mijenjaju izvana iz sweep petlje u bit_analysis_multi.cpp kako bi se testirali razliciti formati za svaku varijablu.
*/
struct FxParams {
    // scaleFactor i factor u piramidi slike
    int W_SF;  int F_SF;   // scaleFactor signal
    int W_FAC; int F_FAC;  // factor varijabla u detectObjects petlji

    // epsilon za grupiranje pravougaonika
    int W_EPS; int F_EPS;  // GROUP_EPS, eps parametar

    // delta u predicate()
    int W_DEL; int F_DEL;

    // s = 1/rweights u groupRectangles
    int W_S;   int F_S;

    // argument myRound (intermediate float multiplikacije koordinata)
    int W_RND; int F_RND;
};

/*
/ Naziv klase: facedetect_fx
/ Opis: Klasa identična originalnom facedetect modulu, ali sa parametarskom fixed-point aritmetikom umjesto hardkodovanih cpp tipova. Koristi se isključivo za bit-width analizu.
*/
class facedetect {
public:
    // konfiguracija fixed-point formata za trenutni run
    FxParams fx;

    // isti bufferi kao u originalnom modulu
    float scaleFactor;
    uint8_t shiftStep;
    int minNeighbours;
    MySize minSize;

    myCascade cascadeObj;

    uint8_t  in_img_buffer[IMAGE_HEIGHT][IMAGE_WIDTH];
    uint8_t  downsample_buffer[IMAGE_HEIGHT][IMAGE_WIDTH];
    int      int_img_buffer[25 * IMAGE_WIDTH];
    int      sq_int_buffer[25 * IMAGE_WIDTH];
    uint8_t  face_number;
    uint16_t face_coordinate[MAX_NUM_FACE][4];
    int      scaled_rectangles_array[34956];

    /*Funkcija koja kvantizuje argument na fixed-point format definisan sa W_RND i F_RND, a zatim vrsi zaokruzivanje.*/
    inline int myRound(float value) {
        float v = to_fixed(value, fx.W_RND, fx.F_RND);
        return (int)(v + 0.5f);
    }

    void setImageForCascadeClassifier(int* sum, int* sqsum, int width);
    void updatePvalue(int* sum, int* sqsum, int p_offset, int pq_offset, int width);
    int  runCascadeClassifier(MyPoint pt, int start_stage, int width);
    void groupRectangles(int groupThreshold, float eps_val);
    int  partition(int* labels, float eps_val);
    int  predicate(float eps_val, uint16_t r1[4], uint16_t r2[4]);
    void ScaleImage_Invoker(float factor, int sum_col, int shift_step, int y_bias);
    int  evalWeakClassifier(int variance_norm_factor, int p_offset, int tree_index, int w_index, int r_index);
    void integralImages(uint8_t src[IMAGE_HEIGHT][IMAGE_WIDTH], int *sumData, int *sqsumData, int width, int height);
    void integralmages_lastrow(uint8_t src[IMAGE_HEIGHT][IMAGE_WIDTH], int *sumData, int *sqsumData, int width, int y_bias);
    void nearestNeighbor(uint8_t dst[IMAGE_HEIGHT][IMAGE_WIDTH], int width, int height);
    void detectObjects(MySize minSize, float scale_factor, int min_neighbors, int shift_step);
    int  detection_main(uint8_t image_data[IMAGE_HEIGHT][IMAGE_WIDTH],
                        float scaleFactor_val, uint8_t shiftStep_val,
                        FxParams params);

    facedetect() {
        cascadeObj.orig_window_size.height = 24;
        cascadeObj.orig_window_size.width  = 24;
        minNeighbours = 1;
        minSize.height = 20;
        minSize.width  = 20;
        face_number = 0;
    }
};

#endif // __HAAR_H__
