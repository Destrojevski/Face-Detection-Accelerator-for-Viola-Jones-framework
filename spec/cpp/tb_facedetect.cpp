/*
/Naziv fajla: tb_facedetect.cpp
/Opis : Testbench za testiranje ispravnosti rada sistema
/Datum : 28/12/2024
/Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/

#include "define.h"
#include "image.h"
#include "tb_facedetect.h"
#include "image_ops.h"
#include "facedetect.h"
#include <cstdio>
#include <vector>
using namespace std;

void test_FACEDETECT::test_main()
{
    int flag;
    int face_number;
    int shiftStep;
    float scaleFactor;
    vector<MyRect> result;
    FILE *fp;

    printf("-- priprema slike za main funkciju --\r\n");

    // preprocessing: konverzija ulaznog jpg u greyscale pgm
    operation();

    printf("-- ulazak u main funkciju --\r\n");
    printf("-- ucitavanje slike --\r\n");

    flag = readPgm((char *)"Face.pgm", image); // citanje .pgm fajla
    if (flag == -1)
    {
        printf("Ne mogu otvoriti .pgm fajl\n");
        return;
    }

    printf("-- slanje podataka --\r\n");

    // citanje iz parameter.txt fajla
    fp = fopen("../../data/parameter.txt","r");
    if (!fp){
        printf("Nemoguce citanje iz parameter.txt\n");
        return;
    }
    fscanf(fp,"%f",&scaleFactor); // prva linija u parameter.txt
    fscanf(fp,"%d",&shiftStep);   // druga linija u parameter.txt
    fclose(fp);

    // kopiranje podataka iz image strukture u 2D bafer koji ocekuje facedetect
    uint8_t img_buf[IMAGE_HEIGHT][IMAGE_WIDTH];
    for(int i = 0; i < IMAGE_HEIGHT; i++)
        for(int j = 0; j < IMAGE_WIDTH; j++)
            img_buf[i][j] = image->data[i * IMAGE_WIDTH + j];

    printf("-- detektovanje lica --\r\n");

    // kreiranje i pokretanje detektora
    facedetect u_FACEDETECT;
    u_FACEDETECT.detection_main(img_buf, scaleFactor, (uint8_t)shiftStep);

    face_number = u_FACEDETECT.face_num_out;
    printf("tb: face_num_out=%d\n", face_number);

    for(int i = 0; i < face_number; i++){
        MyRect r = {
            (int)u_FACEDETECT.face_coordinate[i][0],
            (int)u_FACEDETECT.face_coordinate[i][1],
            (int)u_FACEDETECT.face_coordinate[i][2],
            (int)u_FACEDETECT.face_coordinate[i][3]
        };
        result.push_back(r);
    }

    printf("velicina rezultata: %d\n", (int)result.size());

    // brisanje pomocne slike
    remove("Face.pgm");

    /* brisanje slike i oslobadjanje klasifikatora */
    freeImage(image);
}
