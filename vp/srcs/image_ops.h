/*
/Naziv fajla: image_ops.h
/Opis : Header fajl za image_ops.cpp
/Datum : 23/12/2024
/Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/

#include <vector>
#include <string>

// Konstante za velicinu obradjene slike
const int PREPWIDTH = 360;
const int PREPHEIGHT = 240;

// Funkcija koja pretvara RGB sliku u greyscale
void convertToGrayscale(const std::vector<unsigned char>& rgbImage, std::vector<unsigned char>& grayImage,  int width, int height);

// Funkcija koja sliku upisuje u .pgm fajl
bool writePGM(const std::string& filename, const std::vector<unsigned char>& grayImage, int width, int height);
              
// Glavna funkcija koja izvrsava proces konverzije slike
int operation();
