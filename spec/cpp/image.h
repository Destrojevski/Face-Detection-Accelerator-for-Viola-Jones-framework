/*
/ Naziv fajla : image.h
/ Opis fajla  : deklaracija funkcija za obradu grayscale slike
/ Autori      : Sandić Vojislav, Jović Radivoje, Glišević Sara
/ Datum       : 24.12.2024.
*/
#ifndef __IMAGE_H__
#define __IMAGE_H__

#include "define.h"
int readPgm(char *fileName, MyImage* image); // funkcija koja čita .pgm fajl u binarnom formatu i smešta ga u MyImage strukturu
int cpyPgm(MyImage *src, MyImage *dst); // funkcija koja čita vrednosti iz jedne MyImage strukture i kopira ih u drugu MyImage strukturu
void createImage(int width, int height, MyImage *image); // funkcija koja kreira MyImage strukturu sa određenom visinom i širinom
void createSumImage(int width, int height, MyIntImage *image); // funkcija koja kreira MyIntImage (integralnu sliku) strukturu sa određenom visinom i širinom
int freeImage(MyImage* image); // funkcija koja briše podatke iz MyImage strukture
int freeSumImage(MyIntImage* image); // funkcija koja briše integralnu sliku
void setImage(int width, int height, MyImage *image); // setter funkcija koja menja vrednosti parametara visine i širine MyImage strukture
void setSumImage(int width, int height, MyIntImage *image); // setter funkcija koja menja vrednosti parametara visine i širine MyIntImage strukture
int checkImg(uint8_t buffer[IMAGE_HEIGHT][IMAGE_WIDTH], int width, int height); // funckija koja proverava stanje bafera i upisuje vrednosti iz njega u test.pgm fajl

#endif
