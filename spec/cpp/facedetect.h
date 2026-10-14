#ifndef __HAAR_H__
#define __HAAR_H__

#include "define.h"

//deklaracija klase za detekciju lica
//(SC_MODULE zamijenjen sa obicnom C++ klasom)
class facedetect {
public:
    bool write_signal;    // signal za upis / validan upis
    bool read_signal;     // burst read valid signal
    uint32_t in_data;     // prihvata 4 8-bit piksela, jedan piksel u GS = 1 bajt = 8 bita
    float scaleFactor_in; // faktor skaliranja za downsampling slike, ulazni
    uint8_t shiftStep_in; // korak u pikselima za pomjeranje detekcijskog prozora, ulazni
    uint32_t out_data;    // zavisi od {x,y,w,h} koordinata
    uint8_t face_num_out; // predstavlja broj detektovanih lica
    bool ready;           // ready signal za planiranje transakcije

    float scaleFactor;    // faktor skaliranja
    uint8_t shiftStep;    // korak u pikselima za pomjeranje detekcijskog prozora
    int minNeighbours;    // promjenljiva za nearest neighbor algoritam
    MySize minSize;

    myCascade cascadeObj; // kaskadni objekat

    uint8_t in_img_buffer[IMAGE_HEIGHT][IMAGE_WIDTH];    // ulazni bafer za sliku
    uint8_t downsample_buffer[IMAGE_HEIGHT][IMAGE_WIDTH]; // bafer za downsamplovanu sliku
    int int_img_buffer[25 * IMAGE_WIDTH];  // bafer integralne slike
    int sq_int_buffer[25 * IMAGE_WIDTH];   // bafer kvadrirane integralne slike
    uint8_t face_number;  // broj lica
    uint16_t face_coordinate[MAX_NUM_FACE][4]; // "registar" koji sadrzi izlazne koordinate (x,y,w,h)

    int scaled_rectangles_array[34956]; // skalirani niz pravougaonika

#ifdef IO
    void writeIO(void);
#endif

    /*priprema slike za Haarovu kaskadnu klasifikaciju*/
    void setImageForCascadeClassifier(int* sum, int* sqsum, int width);

    /*azuriranje vrijednosti piksela*/
    void updatePvalue(int* sum, int* sqsum, int p_offset, int pq_offset, int width);

    /*Pokretanje kaskade na odredjenom prozoru*/
    int runCascadeClassifier(MyPoint pt, int start_stage, int width);

    /*grupisanje pravougaonika koji se preklapaju pri detekciji */
    void groupRectangles(int groupThreshold, float eps);

    /*grupisanje pravougaonika u klastere na osnovu preklapanja */
    int partition(int* labels, float eps);

    /*poredjenje pravougaonika bazirano na blizini radi grupisanja u klastere */
    int predicate(float eps, uint16_t r1[4], uint16_t r2[4]);

    //progresivno skaliranje slike na 24*24 prozor radi detekcije lica razlicitih velicina
    void ScaleImage_Invoker(float factor, int sum_col, int shift_step, int y_bias);

    //evaluacija slabih klasifikatora, rad Haarovog filtra
    int evalWeakClassifier(int variance_norm_factor, int p_offset, int tree_index, int w_index, int r_index);

    //funkcija za rad sa integralnim slikama
    void integralImages(uint8_t src[IMAGE_HEIGHT][IMAGE_WIDTH], int *sumData, int *sqsumData, int width, int height);

    //posebna funkcija za rad s integralnim slikama u posljednjem redu
    void integralmages_lastrow(uint8_t src[IMAGE_HEIGHT][IMAGE_WIDTH], int *sumData, int *sqsumData, int width, int y_bias);

    //nearest neighbor algoritam, koristi se za downsampling slike kako bi se izgradila piramida slika
    void nearestNeighbor(uint8_t dst[IMAGE_HEIGHT][IMAGE_WIDTH], int width, int height);

    //funkcija koja poziva sve glavne korake
    void detectObjects(MySize minSize, float scale_factor, int min_neighbors, int shift_step);

    //main funkcija
    void detection_main(uint8_t image_data[IMAGE_HEIGHT][IMAGE_WIDTH],
                        float scaleFactor_val, uint8_t shiftStep_val);

    //konstruktor: inicijalizacija konfiguracije algoritma
    facedetect() {
        cascadeObj.orig_window_size.height = 24; // visina originalnog prozora
        cascadeObj.orig_window_size.width  = 24; // sirina originalnog prozora
        minNeighbours = 1;                        // broj potrebnih susjednih pravougaonika
        minSize.height = 20;
        minSize.width  = 20;
        ready = false;
        face_number = 0;
    }
};

#endif
