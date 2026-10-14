/*
/Naziv fajla: tb_facedetect.h
/Opis : Header fajl za testbench 
/Datum : 28/12/2024
/Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/

#ifndef TB_FACEDETECT_H_
#define TB_FACEDETECT_H_

#include "define.h"
#include "image.h"
#include "facedetect.h"

// Testbench klasa 
class test_FACEDETECT {
public:
    MyImage imageObj; // struktura za bilo kakvu sliku
    MyImage *image = &imageObj;

    /*main metoda testbencha*/
    void test_main();
};

#endif
