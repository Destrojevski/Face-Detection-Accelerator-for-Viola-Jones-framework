/*
/ Naziv fajla: define.h
/ Opis fajla: glavni header fajl za deklaracije i definicjije
/ Autori: Sandić Vojislav, Jović Radivoje, Glišević Sara
/ Datum: 20.12.2024.
*/

#ifndef DEFINE_H
#define DEFINE_H

#include <vector>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

// definicje konstanti
#define IMAGE_WIDTH 360
#define IMAGE_HEIGHT 240
#define PGM_MAXGRAY 255
#define MAX_NUM_FACE 128
#define MAXLABELS 30
#define OUT_BW 9 //koordinatni bitwidth
// #define INT_IMG_BW 26 //bitwidth integralne slike
// #define INT_IMG_SQ_BW 32 // bitska sirina kvadrirane integralne slike bitwidth
// #define SCALE_FACTOR 1.2
// #define MAX_ITER 13 // MAX_ITER = round down to integer( log_{SCALE_FACTOR}{ min(IMAGE_HEIGHT,IMAGE_WIDTH)/24 } ) + 1

#define INPUT_FILENAME "Face.pgm" // ulazni fajl za algoritam
#define OUTPUT_FILENAME "Output.pgm" // izlazni fajl za algoritam, NIJE POTREBNO ZA PROJEKAT

//struktura za tačku, tj. piksel, ima koordinate x i y
typedef struct MyPoint
{
    int x;
    int y;
}
MyPoint;
//struktura za veličinu slike, ima polja širinu i visinu
struct MySize
{
    int width;
    int height;
};
//struktura za pravougaonik u kojem se prevlači kaskada tokom algoritma, ima polja x i y za početnu tačku u pravougaoniku i visinu i širinu pravougaonika
struct MyRect
{
    int x;
    int y;
    int width;
    int height;
};
//struktura za sliku, polja širina, visina i maksimalna grayscale vrednost, vrednosti piksela, i flag za validnost slike
struct MyImage
{
	int width;
	int height;
	int maxgrey;
	unsigned char* data;
	int flag;
};
//struktura za integralnu sliku, polja širina i visina, vrednosti piksela, i flag za validnost slike
struct MyIntImage
{
	int width;
	int height;
	int* data;
	int flag;
};
/*
/struktura za kaskadu, odnosno kvadrat koji se prevlači preko pravougaonika u slici tokom algoritma
/ima polja veličinu slike(20x20), invertovane vrednosti u kvadratu, i vrednosti u
/ćoškovima kvadrata, kao i kvadratne vrednosti istih ćoškova
*/
struct myCascade
{    
    // veličina prozora (kvadrata) korišćenog u setu za treniranje (20 x 20)
    MySize orig_window_size;

    int inv_window_area; // invertovane vrednosti u prozoru zbog bržeg računanja u algoritmu
   
    // vrednosti piksela u ćoškovima prozora
    int pq0, pq1, pq2, pq3; //sqsum: kvadrirana integralna slika
    int p0, p1, p2, p3; //sum: integralna slika

} ;

#endif
