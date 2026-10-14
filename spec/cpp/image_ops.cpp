/*
/Naziv fajla: image_ops.cpp
/Opis : Funkcije za preprocesiranu obradu slike
/Datum : 23/12/2024
/Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image_resize.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#include <iostream>
#include <vector>
#include <fstream>
#include "image_ops.h"
using namespace std;

/* 
Funkcija koja pretvara RGB sliku u greyscale sliku
ulazni parametri su vektori koji predstavljaju nizove piksela, sirina i visina slike
nema povratne vrijednosti
*/
void convertToGrayscale(const vector<unsigned char>& rgbImage, vector<unsigned char>& grayImage, int width, int height) {
    for (int i = 0; i < width * height; ++i) {
        unsigned char r = rgbImage[i * 3];
        unsigned char g = rgbImage[i * 3 + 1];
        unsigned char b = rgbImage[i * 3 + 2];
        grayImage[i] = static_cast<unsigned char>(0.299 * r + 0.587 * g + 0.114 * b); //standardna formula za greyscaling 
    }
}

/* 
Funkcija koja greyscaled sliku upisuje u .pgm (Portable Greyscale Map) fajl iz kojeg moze kasnije da se cita
ulazni parametri su string koji predstavlja naziv fajla, vektor koji predstavlja niz piksela greyscale slike, visina i sirina slike
povratna vrijednost : boolean, oznacava da li je upis u fajl uspjesan
*/
bool writePGM(const string& filename, const vector<unsigned char>& grayImage, int width, int height) {
    ofstream file(filename, ios::binary);
    if (!file) {
        cerr << "Greska: Nemoguce je otvoriti izlazni fajl." << endl;
        return false;
    }

    file << "P5\n" << width << " " << height << "\n255\n";
    file.write(reinterpret_cast<const char*>(grayImage.data()), grayImage.size());

    return true;
}

/* 
glavna funkcija koja izvrsava operacije konverzije i resizeovanja
nema ulazne parametre
povratna vrijednost : int, vraca 1 u slucaju gresaka pri ucitavanju ili resizeovanju, u suprotnom vraca 0
*/
int operation() {
    const string inputFile = "../../data/input.jpg";  // Ulazni JPEG fajl
    const string outputFile = "Face.pgm"; // Izlazna greyscale PGM slika

    // Ucitavanje ulazne slike
    int inputWidth, inputHeight, channels;
    unsigned char* inputImage = stbi_load(inputFile.c_str(), &inputWidth, &inputHeight, &channels, 3);
    if (!inputImage) {
        cerr << "Greska pri ucitavanju ulazne slike" << endl;
        return 1;
    }

    // Resizing slike
    vector<unsigned char> resizedImage(PREPWIDTH * PREPHEIGHT * 3);
    if (!stbir_resize_uint8(inputImage, inputWidth, inputHeight, 0,
                            resizedImage.data(), PREPWIDTH, PREPHEIGHT, 0, 3)) {
        cerr << "Greska, resizeovanje slike nije uspjelo" << endl;
        stbi_image_free(inputImage);
        return 1;
    }

    // Oslobadjanje memorije zauzete od strane ulazne slike
    stbi_image_free(inputImage);

    // Konverzija u greyscale
    vector<unsigned char> grayImage(PREPWIDTH * PREPHEIGHT);
    convertToGrayscale(resizedImage, grayImage, PREPWIDTH, PREPHEIGHT);

    // Upis u greyscale PGM fajl
    if (!writePGM(outputFile, grayImage, PREPWIDTH, PREPHEIGHT)) {
        return 1;
    }

    cout << "Konverzija uspjesna, slika sacuvana u :" << outputFile << endl;
    return 0;
}

