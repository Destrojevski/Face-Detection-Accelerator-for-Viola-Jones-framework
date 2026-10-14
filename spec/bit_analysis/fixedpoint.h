#ifndef FIXEDPOINT_H
#define FIXEDPOINT_H

/*
 * Jednostavna fixed-point klasa za bit-width analizu.
 * Simulira sc_ufixed<W,I> ponašanje: W ukupnih bita, I integer bita, F=W-I frakcijskih bita.
 * Koristi se isključivo za sweep analizu — zamjenjuje sc_ufixed u facedetect modulu.
 */

#include <cmath>
#include <stdint.h>

// Zaokruži float na fixed-point mrežu definisanu sa W i F
inline float to_fixed(float val, int W, int F)
{
    // Broj frakcijskih bita = F
    // Kvantizacijski korak = 2^(-F)
    float step = 1.0f / (float)(1 << F);

    // Saturacija: maksimalna vrijednost = 2^(W-F) - step
    float max_val = (float)((1 << (W - F)) - 1) * step + (step - step); // = 2^(W-F) - step
    // Jednostavnije:
    max_val = (float)((1 << (W - F))) - step;
    if (max_val < 0) max_val = 0; // zaštita od overflow pri malim W

    // Zaokruživanje (RND)
    float rounded = floorf(val / step + 0.5f) * step;

    // Saturacija (SAT) — clamp na [0, max_val] za unsigned
    if (rounded < 0.0f)    rounded = 0.0f;
    if (rounded > max_val) rounded = max_val;

    return rounded;
}

#endif // FIXEDPOINT_H
