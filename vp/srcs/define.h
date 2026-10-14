/*
/ Naziv fajla: define.h
/ Opis fajla: Glavni header fajl za deklaracije i definicije. Ukljucuje SystemC, definise konstante slike i zajednicke strukture podataka.
/ Datum: 6/3/2026
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/
#ifndef DEFINE_H
#define DEFINE_H

#define SC_INCLUDE_FX
#define SC_INCLUDE_DYNAMIC_PROCESSES

#include "systemc.h"
#include <vector>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fstream>
#include <iostream>
#include <sstream>

// Sirina magistrale
#define DATA_WIDTH 16 // Podaci su 16-bitni
#define ADDR_WIDTH 24 // Sirina adresne magistrale

// Dimenzije slike
#define IMAGE_WIDTH 360
#define IMAGE_HEIGHT 240
#define PGM_MAXGRAY 255

// Parametri detekcije
#define MAX_NUM_FACE 128 // Maksimalan broj detektovanih lica
#define MAXLABELS 30 // Maksimalan broj labela za groupRectangles
#define OUT_BW 9 // Bitska sirina izlaznih koordinata

// Zajednicke strukture podataka

// Tacka (piksel) sa koordinatama x i y
typedef struct MyPoint
{
    int x;
    int y;
} MyPoint;

// Velicina (sirina i visina)
struct MySize
{
    int width;
    int height;
};

// Pravougaonik sa pozicijom i dimenzijama
struct MyRect
{
    int x;
    int y;
    int width;
    int height;
};

// Grayscale slika
struct MyImage
{
    int width;
    int height;
    int maxgrey;
    unsigned char* data;
    int flag; // 1 = validna slika
};

// Integralna slika
struct MyIntImage
{
    int width;
    int height;
    int* data;
    int flag;
};

#endif
