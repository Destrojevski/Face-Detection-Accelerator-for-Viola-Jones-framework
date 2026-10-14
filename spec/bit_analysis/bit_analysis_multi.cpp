/*
/ Naziv fajla: bit_analysis_multi.cpp
/ Opis: Bit-width sweep analiza Viola-Jones detektora lica nad skupom od 10 slika. Za svaku konfiguraciju fixed-point parametara 
/   i svaku sliku racuna broj detektovanih lica i poredi sa ground truth vrijednostima iz face_number.txt.
/ Metrike po konfiguraciji (zbir po svim slikama):
/   TP  = min(detected, reference)
/   FP  = max(0, detected - reference)
/   FN  = max(0, reference - detected)
/   Precision = TP / (TP + FP)
/   Recall    = TP / (TP + FN)
/   F1        = 2 * P * R / (P + R)
/ Izlaz: bit_analysis_multi.csv (citljivo u Excelu/Matlabu)
/ Datum: 25/12/2024
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/

#include "define.h"
#include "facedetect.h"
#include "image_ops.h"
#include "image.h"
#include <cstdio>
#include <cstring>
#include <cmath>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <signal.h>
#include <setjmp.h>
using namespace std;

// broj slika u testnom skupu
#define NUM_IMAGES 10

// lista fajlova testnog skupa
static const char* image_files[NUM_IMAGES] = {
    "Face0.pgm","Face1.pgm","Face2.pgm","Face3.pgm","Face4.pgm",
    "Face5.pgm","Face6.pgm","Face7.pgm","Face8.pgm","Face9.pgm"
};

// ground truth vrijednosti ucitane iz face_number.txt
static int ground_truth[NUM_IMAGES];

// bafer za sve slike ucitane u memoriju
static uint8_t g_imgs[NUM_IMAGES][IMAGE_HEIGHT][IMAGE_WIDTH];

// globalni parametri detekcije
static float g_scaleFactor = 1.2f;
static int   g_shiftStep   = 1;

// pomocne varijable za timeout zastitu
static jmp_buf g_jmp;
static void alarm_handler(int) { longjmp(g_jmp, 1); }

/*
/ Naziv strukture: SweepResult
/ Opis: Struktura koja cuva rezultate jedne sweep konfiguracije. Sadrzi naziv konfiguracije, parametre fixed-point formata, 
/   broj detektovanih lica po svakoj slici i agregatne metrike.
*/
struct SweepResult {
    string   config_name;
    FxParams params;
    int      detected[NUM_IMAGES];  // broj detektovanih lica po slici
    int      total_tp, total_fp, total_fn;
    float    precision, recall, f1;
    int      exact_match_count;     // broj slika s tacno istim rezultatom kao referenca
};

/*
/ Naziv funkcije: load_ground_truth
/ Parametri: const char* filename - putanja do face_number.txt fajla
/ Povratna vrednost: bool - true ako su sve vrijednosti uspjesno ucitane
/ Opis funkcije: Funkcija koja ucitava ground truth vrijednosti iz tekstualnog fajla u niz ground_truth. Svaki red fajla sadrzi ime slike
/   i broj lica razdvojene razmakom ili dvotackom.
*/
static bool load_ground_truth(const char* filename)
{
    FILE* f = fopen(filename, "r");
    if (!f) { printf("ERROR: ne mogu otvoriti %s\n", filename); return false; }
    char name[64]; int n;
    int loaded = 0;
    while (fscanf(f, "%s %d", name, &n) == 2 && loaded < NUM_IMAGES) {
        // ukloni ':' ako postoji na kraju naziva fajla
        int len = strlen(name);
        if (name[len-1] == ':') name[len-1] = '\0';
        for (int i = 0; i < NUM_IMAGES; i++) {
            if (strcmp(name, image_files[i]) == 0) {
                ground_truth[i] = n;
                loaded++;
                break;
            }
        }
    }
    fclose(f);
    if (loaded != NUM_IMAGES)
        printf("UPOZORENJE: ucitano %d/%d ground truth vrijednosti\n", loaded, NUM_IMAGES);
    return true;
}

/*
/ Naziv funkcije: load_all_images
/ Parametri: nema
/ Povratna vrednost: bool - true ako su sve slike uspjesno ucitane
/ Opis funkcije: Funkcija koja ucitava sve PGM slike testnog skupa u globalni bafer g_imgs. Slike se ucitavaju jednom na pocetku kako bi
/   se izbjeglo ponavljano citanje sa diska tokom sweep petlje.
*/
static bool load_all_images()
{
    for (int i = 0; i < NUM_IMAGES; i++) {
        MyImage img; img.flag = 0;
        if (readPgm((char*)image_files[i], &img) != 0) {
            printf("ERROR: ne mogu ucitati %s\n", image_files[i]);
            return false;
        }
        for (int r = 0; r < IMAGE_HEIGHT; r++)
            for (int c = 0; c < IMAGE_WIDTH; c++)
                g_imgs[i][r][c] = img.data[r * IMAGE_WIDTH + c];
        freeImage(&img);
    }
    return true;
}

/*
/ Naziv funkcije: run_detector
/ Parametri: 
/   int img_idx - indeks slike u globalnom baferu g_imgs
/   FxParams p - parametri fixed-point formata za tekuci run
/ Povratna vrednost: int - broj detektovanih lica, ili -999 u slucaju timeout-a
/ Opis funkcije: Funkcija koja pokrece detektor na jednoj slici sa zadatim fixed-point parametrima. Koristi alarm() mehanizam za zastitu
/   od beskonacnih petlji pri neispravnim konfiguracijama.
*/
static int run_detector(int img_idx, FxParams p)
{
    if (setjmp(g_jmp) != 0) return -999;
    signal(SIGALRM, alarm_handler);
    alarm(8);
    facedetect det;
    int faces = det.detection_main(g_imgs[img_idx], g_scaleFactor,
                                   (uint8_t)g_shiftStep, p);
    alarm(0);
    return faces;
}

/*
/ Naziv funkcije: default_params
/ Parametri: nema
/ Povratna vrednost: FxParams - struktura sa originalnim sc_ufixed formatima
/ Opis funkcije: Funkcija koja vraca strukturu sa originalnim fixed-point formatima iz specifikacije. Koristi se kao bazna konfiguracija
/   u sweep petlji gdje se mijenja samo jedna varijabla odjednom.
*/
static FxParams default_params()
{
    FxParams p;
    p.W_SF=8;   p.F_SF=7;    // sc_ufixed<8,1>
    p.W_FAC=10; p.F_FAC=5;   // sc_ufixed<10,5>
    p.W_EPS=8;  p.F_EPS=7;   // sc_ufixed<8,1>
    p.W_DEL=16; p.F_DEL=8;   // sc_ufixed<16,8>
    p.W_S=10;   p.F_S=9;     // sc_ufixed<10,1>
    p.W_RND=16; p.F_RND=12;  // sc_ufixed<16,12> - optimalni parametri koji su teorijski moguci
    return p;
}

/*
/ Naziv funkcije: compute_metrics
/ Parametri: SweepResult& r - referenca na rezultat cije metrike se racunaju
/ Povratna vrednost: nema
/ Opis funkcije: Funkcija koja racuna agregatne metrike (TP, FP, FN, Precision, Recall, F1, ExactMatch) za jednu sweep konfiguraciju na osnovu
/   broja detektovanih lica po svakoj slici i ground truth vrijednosti. Timeout detekcije (-999) tretira se kao 0 detektovanih lica.
*/
static void compute_metrics(SweepResult& r)
{
    r.total_tp = 0; r.total_fp = 0; r.total_fn = 0;
    r.exact_match_count = 0;
    for (int i = 0; i < NUM_IMAGES; i++) {
        int det = r.detected[i];
        int ref = ground_truth[i];
        if (det < 0) det = 0;
        int tp = (det < ref) ? det : ref;
        int fp = (det > ref) ? det - ref : 0;
        int fn = (det < ref) ? ref - det : 0;
        r.total_tp += tp;
        r.total_fp += fp;
        r.total_fn += fn;
        if (det == ref) r.exact_match_count++;
    }
    float denom_p = r.total_tp + r.total_fp;
    float denom_r = r.total_tp + r.total_fn;
    r.precision = (denom_p > 0) ? (float)r.total_tp / denom_p : 0.0f;
    r.recall    = (denom_r > 0) ? (float)r.total_tp / denom_r : 0.0f;
    float pr_sum = r.precision + r.recall;
    r.f1 = (pr_sum > 0) ? 2.0f * r.precision * r.recall / pr_sum : 0.0f;
}

/*
/ Naziv funkcije: run_config
/ Parametri: 
/   const string& name - naziv konfiguracije za ispis i CSV
/   FxParams p - parametri fixed-point formata
/ Povratna vrednost: SweepResult - rezultati detekcije i metrike za datu konfiguraciju
/ Opis funkcije: Funkcija koja pokrece detektor na svim slikama testnog skupa za jednu konfiguraciju fixed-point parametara, 
/   ispisuje rezultate na terminal i racuna agregatne metrike.
*/
static SweepResult run_config(const string& name, FxParams p)
{
    SweepResult r;
    r.config_name = name;
    r.params = p;
    for (int i = 0; i < NUM_IMAGES; i++)
        r.detected[i] = run_detector(i, p);
    compute_metrics(r);
    return r;
}

/*
/ Naziv funkcije: run_all_sweeps
/ Parametri: nema
/ Povratna vrednost: vector<SweepResult> - vektor rezultata svih testiranih konfiguracija
/ Opis funkcije: Funkcija koja pokrece sweep po svim varijablama. Za svaku varijablu mijenja se samo njen W i F format dok ostale ostaju na defaultnim vrijednostima. 
/ Redosljed sweep-a:
/   1. Referentna float konfiguracija
/   2. Originalna konfiguracija iz specifikacije
/   3. myRound sweep (I od 4 do 13, F od 8 do 12)
/   4. scaleFactor sweep
/   5. factor sweep
/   6. eps sweep
/   7. delta sweep
/   8. s (1/rweights) sweep
*/
static vector<SweepResult> run_all_sweeps()
{
    vector<SweepResult> results;

    // referentna konfiguracija sa W_RND dovoljno velikim da nema greske kvantizacije
    {
        FxParams p = default_params();
        p.W_RND=21; p.F_RND=8;   // I=13, pokriva sve vrijednosti argumenta myRound
        results.push_back(run_config("FLOAT_REF(W_RND=21,I=13)", p));
    }

    
    {
        FxParams p = default_params();
        results.push_back(run_config("ORIGINAL(W_RND=16,I=4)", p));
    }

    // myRound sweep — najvazniji parametar, I=4 uzrokuje saturaciju na svim slikama
    for (int I = 4; I <= 13; I++) {
        for (int F : {8, 10, 12}) {
            char name[64];
            snprintf(name, sizeof(name), "RND_I%d_F%d(W=%d)", I, F, I+F);
            FxParams p = default_params();
            p.W_RND = I + F;
            p.F_RND = F;
            results.push_back(run_config(name, p));
        }
    }

    // scaleFactor sweep 
    {
        for (int W = 7; W <= 10; W++) {
            for (int I = 1; I <= 2; I++) {
                if (W - I < 1) continue;
                char name[64];
                snprintf(name, sizeof(name), "SF_W%d_I%d_F%d", W, I, W-I);
                FxParams p = default_params();
                p.W_SF = W; p.F_SF = W - I;
                results.push_back(run_config(name, p));
            }
        }
    }

    // factor sweep 
    {
        for (int W = 9; W <= 12; W++) {
            for (int I = 4; I <= 6; I++) {
                if (W - I < 1) continue;
                char name[64];
                snprintf(name, sizeof(name), "FAC_W%d_I%d_F%d", W, I, W-I);
                FxParams p = default_params();
                p.W_FAC = W; p.F_FAC = W - I;
                results.push_back(run_config(name, p));
            }
        }
    }

    // eps sweep 
    {
        for (int W = 7; W <= 10; W++) {
            for (int I = 1; I <= 2; I++) {
                if (W - I < 1) continue;
                char name[64];
                snprintf(name, sizeof(name), "EPS_W%d_I%d_F%d", W, I, W-I);
                FxParams p = default_params();
                p.W_EPS = W; p.F_EPS = W - I;
                results.push_back(run_config(name, p));
            }
        }
    }

    // delta sweep 
    {
        for (int W = 14; W <= 18; W++) {
            for (int I = 7; I <= 9; I++) {
                if (W - I < 1) continue;
                char name[64];
                snprintf(name, sizeof(name), "DEL_W%d_I%d_F%d", W, I, W-I);
                FxParams p = default_params();
                p.W_DEL = W; p.F_DEL = W - I;
                results.push_back(run_config(name, p));
            }
        }
    }

    // s (1/rweights) sweep 
    {
        for (int W = 9; W <= 12; W++) {
            for (int I = 1; I <= 2; I++) {
                if (W - I < 1) continue;
                char name[64];
                snprintf(name, sizeof(name), "S_W%d_I%d_F%d", W, I, W-I);
                FxParams p = default_params();
                p.W_S = W; p.F_S = W - I;
                results.push_back(run_config(name, p));
            }
        }
    }

    return results;
}

/*
/ Naziv funkcije: write_csv
/ Parametri: 
/   const vector<SweepResult>& results - vektor svih rezultata
/   const char* filename - naziv izlaznog CSV fajla
/ Povratna vrednost: nema
/ Opis funkcije: Funkcija koja upisuje rezultate sweep analize u CSV fajl. Svaki red odgovara jednoj konfiguraciji i sadrzi parametre
/   fixed-point formata, broj detekcija po svakoj slici i agregatne metrike (TP, FP, FN, Precision, Recall, F1, ExactMatch).
*/
static void write_csv(const vector<SweepResult>& results, const char* filename)
{
    FILE* f = fopen(filename, "w");
    if (!f) { printf("ERROR: ne mogu pisati %s\n", filename); return; }

    // zaglavlje CSV fajla
    fprintf(f, "config_name,W_SF,F_SF,W_FAC,F_FAC,W_EPS,F_EPS,W_DEL,F_DEL,W_S,F_S,W_RND,I_RND,F_RND");
    for (int i = 0; i < NUM_IMAGES; i++)
        fprintf(f, ",Face%d(ref=%d)", i, ground_truth[i]);
    fprintf(f, ",TP,FP,FN,Precision,Recall,F1,ExactMatch\n");

    for (const auto& r : results) {
        const FxParams& p = r.params;
        fprintf(f, "%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d",
            r.config_name.c_str(),
            p.W_SF, p.F_SF, p.W_FAC, p.F_FAC,
            p.W_EPS, p.F_EPS, p.W_DEL, p.F_DEL,
            p.W_S, p.F_S,
            p.W_RND, p.W_RND - p.F_RND, p.F_RND);
        for (int i = 0; i < NUM_IMAGES; i++)
            fprintf(f, ",%d", r.detected[i]);
        fprintf(f, ",%d,%d,%d,%.4f,%.4f,%.4f,%d\n",
            r.total_tp, r.total_fp, r.total_fn,
            r.precision, r.recall, r.f1, r.exact_match_count);
    }
    fclose(f);
    printf("\nCSV zapisan: %s\n", filename);
}

/*
/ Naziv funkcije: main
/ Parametri: nema
/ Povratna vrednost: int - 0 pri uspjesnom izvrsavanju
/ Opis funkcije: Glavna funkcija programa. Ucitava ground truth i slike, pokrece sweep po svim varijablama i upisuje rezultate u CSV.
*/
int main()
{
    printf("Analiza u toku, molimo sacekajte...\n");
    fflush(stdout);

    if (!load_ground_truth("face_number.txt")) return 1;
    if (!load_all_images()) return 1;

    vector<SweepResult> results = run_all_sweeps();

    write_csv(results, "bit_analysis_multi.csv");

    printf("Analiza zavrsena. Testirano konfiguracija: %zu\n", results.size());
    printf("Rezultati zapisani u: bit_analysis_multi.csv\n");
    return 0;
}

/* Kraj fajla. */
