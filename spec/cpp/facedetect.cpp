/*
/Naziv fajla: facedetect.cpp
/Opis : Funkcije za implementaciju Viola-Jones detektora lica
/Datum : 25/12/2024
/Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/

#include "define.h"
#include "facedetect.h"
#include <math.h>

#ifdef IO
int writetoTLV_int(int value, char* filename);
int writetoTLV_float(float value, char* filename);

/* 
Funkcija koja vrsi upis ulaza u .tlv fajl svaki ciklus koji je vazeci
nema ulazne parametre
nema povratne vrijednosti
*/
void facedetect::writeIO(void)
{
    int ret_v;
    
    ret_v = writetoTLV_int( (unsigned int)write_signal, "./tlv/write_signal.tlv" );
    ret_v += writetoTLV_int( (unsigned int)read_signal, "./tlv/read_signal.tlv" );
    ret_v += writetoTLV_int( (unsigned int)in_data, "./tlv/in_data.tlv" );
    ret_v += writetoTLV_float( (float)scaleFactor_in, "./tlv/scaleFactor_in.tlv" );
    ret_v += writetoTLV_int( (unsigned int)shiftStep_in, "./tlv/shiftStep_in.tlv" );

    if(ret_v!=0)
        exit(1);
}

/* 
pomocna funkcija za upis int vrijednosti u .tlv fajl
ulazni parametri int vrijednost i pokazivac na naziv fajla
vraca -1 ukoliko fajl ne moze da se otvori, u suprotnom vraca 0
*/
int writetoTLV_int(int value, char* filename)
{
    FILE* fp;
    fp = fopen(filename, "a");
    if (fp == NULL){
        printf("ERROR: unable to open file %s\n",filename);
        return -1;
    }
    
    fprintf(fp, "%u\n", value);
    fclose(fp);
    return 0;
}

/* 
pomocna funkcija za upis float vrijednosti u .tlv fajl
ulazni parametri float vrijednost i pokazivac na naziv fajla
vraca -1 ukoliko fajl ne moze da se otvori, u suprotnom vraca 0
*/
int writetoTLV_float(float value, char* filename)
{
    FILE* fp;
    fp = fopen(filename, "a");
    if (fp == NULL){
        printf("ERROR: unable to open file %s\n",filename);
        return -1;
    }
    
    fprintf(fp, "%f\n", value);
    fclose(fp);
    return 0;
}

#endif

/*NIZOVI SA PODACIMA ZA KLASIFIKACIJU:
rectangles_array : geometrijski podaci za Haarove karakteristike
stages_array : opis strukture kaskadnih klasifikatora
weights_array : vaznost individualnih Haarovih karakteristika
alpha1_array i alpha2_array : koeficijenti slabih klasifikatora za AdaBoost
tree_thresh_array : granice odlucivanja za slabe klasifikatore
stages_thresh_array : granice odlucivanja na nivou faza za progresiju kaskada
*/
const int rectangles_array[34956] = {
    #include "rectangles_array.dat"
};
const int stages_array[25] = {
    #include "stages_array.dat"
};
const int weights_array[8739] = {
    #include "weights_array.dat"
};
const int alpha1_array[2913] = {
    #include "alpha1_array.dat"
};
const int alpha2_array[2913] = {
    #include "alpha2_array.dat"
};
const int tree_thresh_array[2913] = {
    #include "tree_thresh_array.dat"
};
const int stages_thresh_array[25] = {
    #include "stages_thresh_array.dat"
};

/* 
makro za zaokruzivanje vrijednosti, vraca zaokruzenu ulaznu vrijednost
(sc_ufixed zamijenjen obicnim float)
*/
inline int myRound( float value )
{
  return (int)(value + 0.5f);
}

/* 
funkcija koja poziva sve glavne korake pri detekciji lica
ulazni parametri MySize strukturu sa sirinom i visinom prozora, faktor skaliranja slike tipa float, int vrijednost koja predstavlja broj susjeda, kao i int vrijednost shift_step koja predstavlja korak pri pomjeranju detekcijskog prozora
nema povratnu vrijednost
*/

void facedetect::detectObjects( MySize minSize, float scaleFactor, int minNeighbors, int shift_step)
{

    /*grupisanje prozora koji se preklapaju*/
    const float GROUP_EPS = 0.4f;
    int y_bias, iter_counter = 0;

    /*faktor skaliranja*/
    float factor;

    /*velicina prozora kod trening seta*/
    MySize winSize0 = cascadeObj.orig_window_size;

    /*iteracija se vrsi po piramidi slika*/
    face_number = 0;
    for( factor = 1.0f; ; factor *= scaleFactor)
    {
        /*brojac iteracija*/
        iter_counter++;

        /*upscaled velicina slike*/
        MySize winSize = { myRound(winSize0.width*factor), myRound(winSize0.height*factor) };

        /*downscaled velicina slike*/
        MySize sz = { ( IMAGE_WIDTH/factor ), ( IMAGE_HEIGHT/factor ) };

        /*ako je velicina slike manja od velicine prozora, izadji iz petlje*/
        if( sz.width < 24 || sz.height < 24 )
            break;
        
        /*ako je specificirana minimalna velicina prozora drugacija od originalnog prozora, nastavi na sljedece skaliranje*/
        if( winSize.width < minSize.width || winSize.height < minSize.height )
            continue;

        /*Racunski intenzivan korak:
        izgradnja piramide slike downsamplingom slika
        downsampling se vrsi upotrebom nearest neighbor algoritma*/
         
        nearestNeighbor( downsample_buffer, sz.width, sz.height);

        /*Racunski intenzivan korak:
        na svakom nivou piramide slika,
        napravi novu integralnu i kvadriranu integralnu sliku
        */
        integralImages(downsample_buffer, int_img_buffer, sq_int_buffer, sz.width, 25);

        /*
        * Sumiranje piksela u Haarovom prozoru vrsi se upotrebom cetiri coska integralne slike
        * Ova funkcija nije racunski intenzivna jer ne vrsi nikakav racun
        * Sljedeca racunski intenzivna funkcija jeste ScaleImage_Invoker
        */
        
        setImageForCascadeClassifier(  int_img_buffer, sq_int_buffer, sz.width);

        for(y_bias=0; y_bias < sz.height-25+1; y_bias++){
            if(y_bias!=0)
                //pomjeri bafer integralne slike i azuriraj samo posljednji red piksela
                integralmages_lastrow(downsample_buffer, int_img_buffer, sq_int_buffer, sz.width, y_bias);
            
            /*obrada trenutne skale slike upotrebom kaskadnog filtra
            glavni proracuni vrse se u sklopu ove funkcije
            */
            
            ScaleImage_Invoker( factor, sz.width, shift_step, y_bias);
        }
        
    } /*kraj petlje, zavrsena obrada svih skala u piramidi*/

    if( minNeighbors != 0)
    {
        groupRectangles( minNeighbors, GROUP_EPS);
    }

}

/* 
funkcija za racunanje cijelog korijena cijelog broja upotrebom bitwise iterative metode, koja efikasno racuna korijen bez upotrebe aritmetike sa pokretnim zarezom, sto u znatnoj mjeri olaksava rad sistema.
ulazni parametar unsigned int vrijednost broja ciji korijen trazimo
povratna vrijednost broj a takav da  a^2 <= value
*/

unsigned int int_sqrt (unsigned int value)
{
    int i;
    unsigned int a = 0, b = 0, c = 0;
    for (i=0; i < (32 >> 1); i++)
    {
        c<<= 2;

        c += value>>30;

        value <<= 2;
        a <<= 1;
        b = (a<<1) | 1;
        if (c >= b)
        {
            c -= b;
            a++;
        }
    }
    return a;
}

 
/* funkcija koja priprema i podesava podatke potrebne za racunanje Haarovih karakteristika potrebnih za rad Viola-Jones algoritma, konkretno racuna i skalira  indekse pravougaonika potrebne za racunanje Haarovih karakteristika u vise faza kaskadnog klasifikatora, sto je kljucno za obradu integralnih slika i efikasno racunanje suma Haarovih karakteristika.
ulazni parametri sume integralnih i kvadriranih integralnih slika, kao i sirina integralnih slika
nema povratnu vrijednost
*/

void facedetect::setImageForCascadeClassifier( int* sum, int* sqsum, int width)
{
    int i, j, k;
    MyRect equRect;
    int r_index = 0;
    int w_index = 0;
    MyRect tr;

    equRect.x = equRect.y = 0;
    equRect.width = cascadeObj.orig_window_size.width;
    equRect.height = cascadeObj.orig_window_size.height;

    cascadeObj.inv_window_area = equRect.width*equRect.height;

    /*Ucitavanje indeksa cetiri coska pravougaonika filtera
    */

    /*petlja kroz broj faza*/
    for( i = 0; i < 25; i++ )
    {
        /*petlja kroz broj Haarovih karakteristika*/
        for( j = 0; j < stages_array[i]; j++ )
        {
            /*petlja kroz broj pravougaonika*/
            for( k = 0; k < 3; k++ )
            {
                tr.x = rectangles_array[r_index + k*4];
                tr.width = rectangles_array[r_index + 2 + k*4];
                tr.y = rectangles_array[r_index + 1 + k*4];
                tr.height = rectangles_array[r_index + 3 + k*4];
                if (k < 2)
                {
                    scaled_rectangles_array[r_index + k*4] = width*(tr.y ) + (tr.x ) ;
                    scaled_rectangles_array[r_index + k*4 + 1] = width*(tr.y ) + (tr.x  + tr.width);
                    scaled_rectangles_array[r_index + k*4 + 2] = width*(tr.y  + tr.height) + (tr.x );
                    scaled_rectangles_array[r_index + k*4 + 3] = width*(tr.y  + tr.height) + (tr.x  + tr.width);
                }
                else
                {
                    if ((tr.x == 0)&& (tr.y == 0) &&(tr.width == 0) &&(tr.height == 0))
                    {
                        scaled_rectangles_array[r_index + k*4] = -1 ;//null
                        scaled_rectangles_array[r_index + k*4 + 1] = -1 ;//null
                        scaled_rectangles_array[r_index + k*4 + 2] = -1;//null
                        scaled_rectangles_array[r_index + k*4 + 3] = -1;//null
                    }
                    else
                    {
                        scaled_rectangles_array[r_index + k*4] = width*(tr.y ) + (tr.x ) ;
                        scaled_rectangles_array[r_index + k*4 + 1] = width*(tr.y ) + (tr.x  + tr.width) ;
                        scaled_rectangles_array[r_index + k*4 + 2] = width*(tr.y  + tr.height) + (tr.x );
                        scaled_rectangles_array[r_index + k*4 + 3] = width*(tr.y  + tr.height) + (tr.x  + tr.width);
                    }
                } /*kraj grane if(k<2)*/
            } /*kraj k petlje*/
            r_index+=12;
            w_index+=3;
        } /*kraj j petlje*/
    } /*kraj i petlje*/
}


/* funkcija koja izvrsava rad Haarovog filtra racunajuci sumu vrijednosti HAarovih karakteristika upotrebom indeksa pravougaonika i tezina karakteristika i njihovim poredjenjem sa granicnom vrijednoscu.
ulazni parametri su int normalizacioni faktor koji normalizuje odziv filtra (karakteristike) i time je cini nezavisnim od skaliranja, int p_offset cija je funkcija poravnanje indeksa integralne slike na takav nacin da se posmatra trenutno podrucje cije stanje nas interesuje, int tree_index za indeksiranje nizova alpha1,alpha2 i tree_thresh, kao i int w_index i int r_index za indeksiranje nizova weights i scaled_rectangles
povratna vrijednost je tezina (alpha1 ili alpha2) koja je indikator prisustva i odsustva lica na osnovu odziva karakteristike.
*/
int facedetect::evalWeakClassifier(int variance_norm_factor, int p_offset, int tree_index, int w_index, int r_index )
{

    /* granicna vrijednost cvora se mnozi standardnom devijacijom slike*/
    int t = tree_thresh_array[tree_index] * variance_norm_factor;

    int sum = (int_img_buffer[scaled_rectangles_array[r_index] + p_offset]
        - int_img_buffer[scaled_rectangles_array[r_index + 1] + p_offset]
        - int_img_buffer[scaled_rectangles_array[r_index + 2] + p_offset]
        + int_img_buffer[scaled_rectangles_array[r_index + 3] + p_offset])
        * weights_array[w_index];

    sum += (int_img_buffer[scaled_rectangles_array[r_index+4] + p_offset]
        - int_img_buffer[scaled_rectangles_array[r_index + 5] + p_offset]
        - int_img_buffer[scaled_rectangles_array[r_index + 6] + p_offset]
        + int_img_buffer[scaled_rectangles_array[r_index + 7] + p_offset])
        * weights_array[w_index + 1];

    if ((scaled_rectangles_array[r_index+8] != -1))//null
        sum += (int_img_buffer[scaled_rectangles_array[r_index+8] + p_offset]
            - int_img_buffer[scaled_rectangles_array[r_index + 9] + p_offset]
            - int_img_buffer[scaled_rectangles_array[r_index + 10] + p_offset]
            + int_img_buffer[scaled_rectangles_array[r_index + 11] + p_offset])
            * weights_array[w_index + 2];

    if(sum >= t)
        return alpha2_array[tree_index];
    else
        return alpha1_array[tree_index];

}

/* funkcija koja azurira integralnu i kvadratnu integralnu sliku i priprema ih za dalje proracune tako sto izvlaci vrijednosti coskova integralne i kvadrirane integralne slike za trenutni detekcijski prozor i skladisti ih u cascadeObj za dalju obradu.
ulazni parametri sume integralnih i kvadriranih integralnih slika, int p_offset i pq_offset koji predstavljaju ofsete u integralnim slikama u odnosu na gornji lijevi cosak prozora koji se trenutno obradjuje, kao i int sirina integralne slike
nema povratnu vrijednost
*/

void facedetect::updatePvalue(  int* sum, int* sqsum, int p_offset, int pq_offset, int width)
{
    cascadeObj.p0 = sum[0+p_offset] ;
    cascadeObj.p1 = sum[cascadeObj.orig_window_size.width - 1+p_offset] ;
    cascadeObj.p2 = sum[width*(cascadeObj.orig_window_size.height - 1)+p_offset];
    cascadeObj.p3 = sum[width*(cascadeObj.orig_window_size.height - 1) + cascadeObj.orig_window_size.width - 1+p_offset];
    cascadeObj.pq0 = sqsum[0+pq_offset];
    cascadeObj.pq1 = sqsum[cascadeObj.orig_window_size.width - 1+pq_offset] ;
    cascadeObj.pq2 = sqsum[width*(cascadeObj.orig_window_size.height - 1)+pq_offset];
    cascadeObj.pq3 = sqsum[width*(cascadeObj.orig_window_size.height - 1) + cascadeObj.orig_window_size.width - 1+pq_offset];
}

/* funkcija koja provlaci sliku kroz kaskadu rastuce kompleksnih klasifikacija (faza) i vrsi detekciju lica
ulazni parametri MyPoint pt tj. pocetna tacka klasifikacije (gornji lijevi ugao detekcijskog prozora), int start_stage koji predstavlja pocetnu fazu kaskadne klasifikacije slike te int width parametar koji predstavlja sirinu slike potrebnu za indeksiranje integralnih slika i normalizaciju vrijednosti kod karakteristika
Povratna vrijednost 1 ukoliko je lice detektovano odnosno -i ukoliko detekcija ne prodje i-tu fazu*/
int facedetect::runCascadeClassifier( MyPoint pt, int start_stage, int width)
{

    int p_offset, pq_offset;
    int i, j;
    unsigned int mean;
    unsigned int variance_norm_factor;
    int haar_counter = 0;
    int w_index = 0;
    int r_index = 0;
    int stage_sum;

    p_offset = pt.y * width + pt.x;
    pq_offset = pt.y * width + pt.x;

    /*Normalizacija slike
    mean predstavlja srednju vrijednost piksela u detekcijskom prozoru
    inv_window_area je ukupan broj piksela u detekcijskom prozoru uvecan za 1*/

    updatePvalue( int_img_buffer, sq_int_buffer, p_offset, pq_offset, width);
    
    variance_norm_factor =  (cascadeObj.pq0 - cascadeObj.pq1 - cascadeObj.pq2 + cascadeObj.pq3);
    mean = (cascadeObj.p0 - cascadeObj.p1 - cascadeObj.p2 + cascadeObj.p3);

    variance_norm_factor = (variance_norm_factor*cascadeObj.inv_window_area);
    variance_norm_factor =  variance_norm_factor - mean*mean;

    if( variance_norm_factor > 0 )
        variance_norm_factor = int_sqrt(variance_norm_factor);
    else
        variance_norm_factor = 1;

    /*Racunski intenzivan korak:
    Za svako skaliranje u piramidi slika, i za svaki korak za koji je filter pomjeren, posalji pomjereni prozor kroz kaskadni filtar
    Faze u kaskadnom filtru su nezavisne, ali lice moze biti odbijeno u svakoj fazi, ako paralelno pokrecemo faze detekcije izazivamo nezeljeno kasnjenje sto uzrokuje nepotreban racun. Filtri u istoj fazi su takodje nezavisni, s tim da rezultati koje filtri daju moraju biti objedinjeni i uporedjeni sa granicnom vrijednoscu svake faze.*/
    
    for( i = start_stage; i < 25 ; i++ )
    {
        stage_sum = 0;

        for( j = 0; j < 200; j++ )
        {
            if (j>=stages_array[i])
                break;
            /*proslijedjivanje pomjerenog prozora Haarovom filtru*/
            
            stage_sum += evalWeakClassifier(variance_norm_factor, p_offset, haar_counter, w_index, r_index);
            haar_counter++;
            w_index+=3;
            r_index+=12;
        } /*kraj j petlje*/

        /* Granicna vrijednost faze:
        Ukoliko se suma nalazi ispod granice, nema detektovanih lica i detekcija se obustavlja u i-toj fazi, u suprotnom, lice je detektovano (1).
       */

        /*Zasto je faktor 0.4 tu ?
        Zato sto se najcesce koristi u embeded sistemima cija je detekcija bazirana na Viola-Jones algoritmu za thresholding. Faktori koji se generalno koriste pri thresholdingu jesu :
        0.4 (najcesci)
        0.3
        0.5
        0.25 (rijedak ali se koristi u nekim konfiguracijama)
       Koji cemo faktor koristiti generalno zavisi od primjene naseg sistema i njegove konfiguracije, manje vrijednosti cine kaskadu manje striktnom, sto za posljedicu ima veci recall ali i veci broj lazno-pozitivnih detekcija, dok vece vrijednosti cine kaskadu striktnijom, smanjujuci recall i potencijalno smanjujuci sansu da se neka lica prepoznaju, ali povecavaju preciznost.
       0.4 faktor generalno se smatra standardom za thresholding kod Viola-Jones algoritma, koristi se npr. kod komercijalnih sistema zasnovanih na Nvidia Fermi arhitekturi.
        */
        
        if( stage_sum < 0.4f * stages_thresh_array[i] ){
            return -i;
        } /* kraj thresholdinga po fazama*/
    } /* kraj i petlje*/
    return 1;
}

/* funkcija koja izvrsava detekciju objekata prevlacenjem prozora sa skaliranjem slike. Radi tako sto skalira velicinu prozora, zatim ga prevlaci horizontalno po slici i za svaku poziciju pomjerenog prozora pozove runClassifierCascade() funkciju, ako klasifikator pronadje lice njegove koordinate se cuvaju a promjenljiva broja lica se uvecava. Pri pomjeranju prozora odrzava se odredjena margina da bi se izbjegli problemi u detekciji u ivicnim oblastima slike.
ulazni parametri faktor skaliranja tipa float, int sum_col odnosno broj kolona u slici, int shift_step odnosno korak pomjeraja za prevlacenje prozora, te int y_bias promjenljiva za podesavanje pozicije detekcijskog prozora referentno u odnosu na pocetnu y koordinatu
nema povratnu vrijednost*/

void facedetect::ScaleImage_Invoker( float factor, int sum_col, int shift_step, int y_bias)
{

    MyPoint p;

    int result;
    int x2, x, step;

    MySize winSize0 = cascadeObj.orig_window_size;
    MySize winSize;

    winSize.width =  myRound(winSize0.width*factor);
    winSize.height =  myRound(winSize0.height*factor);

    /*pri pomjeranju filtracijskog prozora ka ivici slike, mora postojati odredjena margina*/
    x2 = sum_col - winSize0.width;
    p.y = 0;
    
    step = shift_step;

    for( x = 0; x <= x2-1; x += step )
    {
        p.x = x;

        result = runCascadeClassifier( p, 0, sum_col);

        if( result > 0 )
        {
            face_coordinate[face_number][0] = (uint16_t)myRound(x*factor);
            face_coordinate[face_number][1] = (uint16_t)myRound(y_bias*factor);
            face_coordinate[face_number][2] = (uint16_t)winSize.width;
            face_coordinate[face_number][3] = (uint16_t)winSize.height;
            if(face_number<MAX_NUM_FACE-1)
                face_number++;
        }
    }
}

/* funkcija koja izvrsava proracune integralnih i kvadratnih integralnih slika, koje pomazu da se odredjena oblast slike brzo sumira
ulazni parametri su uint src koji je 2D niz koji predstavlja ulaznu greyscale sliku dimenzija IMAGE_HEIGHT*IMAGE_WIDTH, zatim int sumData i sqsumData sto su izlazni nizovi u kojima se cuvaju izlazni podaci integralnih i kvadriranih integralnih slika, te int width i height koji predstavljaju sirinu i visinu slike.
nema povratnu vrijednost*/

void facedetect::integralImages( uint8_t src[IMAGE_HEIGHT][IMAGE_WIDTH], int *sumData, int *sqsumData, int width, int height)
{
    int x, y, s, sq, t, tq;
    unsigned char it;

    for( y = 0; y < height; y++)
    {
        s = 0;
        sq = 0;
        /* petlja po broju kolona*/
        for( x = 0; x < width; x ++)
        {
            it = src[y][x];
            /* cijela suma trenutnog reda*/
            s += it;
            sq += it*it;

            t = s;
            tq = sq;
            if (y != 0)
            {
                t += sumData[(y-1)*width+x];
                tq += sqsumData[(y-1)*width+x];
            }
            sumData[y*width+x]=t;
            sqsumData[y*width+x]=tq;
        }
    }
}

/* funkcija koja izvrsava proracune integralnih i kvadratnih integralnih slika, koje pomazu da se odredjena oblast slike brzo sumira. Razlika u odnosu na integralImages funkciju je to sto je ova funkcija pravljena posebno za posljednji red, tj. pomjera se bafer i samo se posljednji red azurira
ulazni parametri su uint src koji je 2D niz koji predstavlja ulaznu greyscale sliku dimenzija IMAGE_HEIGHT*IMAGE_WIDTH, zatim int sumData i sqsumData sto su izlazni nizovi u kojima se cuvaju izlazni podaci integralnih i kvadriranih integralnih slika, te int width i height koji predstavljaju sirinu i visinu slike.
nema povratnu vrijednost*/

void facedetect::integralmages_lastrow(uint8_t src[IMAGE_HEIGHT][IMAGE_WIDTH], int *sumData, int *sqsumData, int width, int y_bias)
{
    int x, y, s, sq, t, tq;
    unsigned char it;
    
    // shift u gornji red
    for(y=0; y<24; y++){
        for(x=0; x<width; x++){
            sumData[y*width+x] = sumData[(y+1)*width+x];
            sqsumData[y*width+x] = sqsumData[(y+1)*width+x];
        }
    }
    
    // azuriranje posljednjeg reda
    s = 0;
    sq = 0;
    for(x=0; x<width; x++){
        it = src[24+y_bias][x];
        s += it;
        sq += it*it;
        
        t = s;
        tq = sq;
        t += sumData[23*width+x];
        tq += sqsumData[23*width+x];
        
        sumData[24*width+x] = t;
        sqsumData[24*width+x] = tq;
    }
}

/*funkcija koja izvrsava downsampling slike upotrebom nearest-neighbor metode za interpolaciju gdje svaki piksel u resized slici odgovara najblizem pikselu u originalnoj slici, ovo se koristi za izgradnju piramide slika za detekciju lica.
ulazni parametri uint dst koji je 2D niz koji predstavlja resized sliku dimenzija IMAGE_HEIGHT*IMAGE_WIDTH, int width i int height koji predstavljaju sirinu i visinu slike respektivno
nema povratnu vrijednost
*/
void facedetect::nearestNeighbor ( uint8_t dst[IMAGE_HEIGHT][IMAGE_WIDTH], int width, int height)
{

    int y;
    int j;
    int x;
    int i;
    int w1 = IMAGE_WIDTH;
    int h1 = IMAGE_HEIGHT;
    int w2 = width;
    int h2 = height;

    int rat = 0;
    int x_ratio = (int)((w1<<16)/w2) +1;
    int y_ratio = (int)((h1<<16)/h2) +1;

    for (i=0;i<h2;i++)
    {
        y = ((i*y_ratio)>>16);
        rat = 0;
        for(j=0;j<w2;j++)
        {
            x = (rat>>16);
            dst[i][j] = in_img_buffer[y][x];
            rat += x_ratio;
        }
    }
}

/*funkcija koja se koristi za grupisanje detektovanih pravougaonika lica bazirano na metodi klasterovanja i granici preklapanja (eps parametar), ona objedinjuje preklopljene pravougaonike u vece, razradjenije granicne kvadrate, smanjujuci redundantnost detekcija i istovremeno ocuvavajuci znacajnije detekcije.
ulazni parametri int groupThreshold koji predstavlja minimalan broj pravougaonika koji se mogu posmatrati kao grupa, i float eps koji predstavlja granicnu vrijednost preklapanja pravougaonika potrebnu da bi se pravougaonici objedinili
nema povratnu vrijednost
*/

void facedetect::groupRectangles( int groupThreshold, float eps)
{
    if( groupThreshold <= 0 || face_number==0 )
        return;

    int labels[MAX_NUM_FACE];

    int nclasses = partition(labels, eps);
    
    MyRect rrects[MAXLABELS];
    int rweights[MAXLABELS];
    
    int i, j, nlabels = face_number;

    for( i = 0; i < nclasses; i++ )
    {
        rrects[i].x = 0;
        rrects[i].y = 0;
        rrects[i].width = 0;
        rrects[i].height = 0;
        rweights[i]=0;
    }
    
    for( i = 0; i < nlabels; i++ )
    {
        int cls = labels[i];
        rrects[cls].x += face_coordinate[i][0];
        rrects[cls].y += face_coordinate[i][1];
        rrects[cls].width += face_coordinate[i][2];
        rrects[cls].height += face_coordinate[i][3];
        rweights[cls]++;
    }
    
    for( i = 0; i < nclasses; i++ )
    {
        MyRect r = rrects[i];
        float s = 1.0f/rweights[i];
        rrects[i].x = myRound(r.x*s);
        rrects[i].y = myRound(r.y*s);
        rrects[i].width = myRound(r.width*s);
        rrects[i].height = myRound(r.height*s);
    }

    face_number=0;

    for( i = 0; i < nclasses; i++ )
    {
        MyRect r1 = rrects[i];
        int n1 = rweights[i];
        if( n1 <= groupThreshold )
            continue;
        /* filtracija manjih detektovanih pravougaonika unutar vecih*/
        for( j = 0; j < nclasses; j++ )
        {
            int n2 = rweights[j];
            /*ukoliko je u pitanju isti pravougaonik, ili je broj pravougaonika u klasi j manji od granicne vrijednosti za grupisanje, ne radi nista */
            if( j == i || n2 <= groupThreshold )
                continue;
            
            MyRect r2 = rrects[j];

            int dx = myRound( r2.width * eps );
            int dy = myRound( r2.height * eps );

            if( i != j &&
                r1.x >= r2.x - dx &&
                r1.y >= r2.y - dy &&
                r1.x + r1.width <= r2.x + r2.width + dx &&
                r1.y + r1.height <= r2.y + r2.height + dy &&
                (n2 > ( (3>n1) ? 3 : n1 ) || n1 < 3) )
                break;
        }

        if( j == nclasses )
        {
            face_coordinate[face_number][0] = (uint16_t)r1.x;
            face_coordinate[face_number][1] = (uint16_t)r1.y;
            face_coordinate[face_number][2] = (uint16_t)r1.width;
            face_coordinate[face_number][3] = (uint16_t)r1.height;
            if(face_number<MAX_NUM_FACE-1)
                face_number++;
        }
    }
}

/*
/ Naziv funkcije    : partition
/ Parametri         : int niz labela i eps prag tolerancije koji određuje koliko slična lica moraju da budu za detekciju
/ Povratna vrednost : int vrednost nclasses broj prepoznatih klasa (lica)
/ Opis funkcije     : funkcija koja od niza labela treba da pronađe broj lica tako što iz labela nalazi roditeljsko lice i tako pravi stablo sve dok ne dođe do najstarijeg 
/ lica (root), broj root-ova je broj prepoznatih lica
*/
int facedetect::partition(int* labels, float eps)
{
    int i, j;
    int N = face_number;
    
    const int _PArent=0;
    const int _RAnk=1;

    int nodes[MAX_NUM_FACE][2];
    
    /* prvi prolaz kroz niz, inicjalizacija gde je svako lice samo sebi root (O(N))*/
    for(i = 0; i < N; i++)
    {
        nodes[i][_PArent]=-1;
        nodes[i][_RAnk] = 0;
    }

    /* glavni prolaz u kom se nalaze root-ovi i spajaju u setove (Union-find metoda O(N^2))*/
    for( i = 0; i < N; i++ )
    {
        int root = i;

        /* nalaženje root-a lica */
        while( nodes[root][_PArent] >= 0 )
        root = nodes[root][_PArent];

        for( j = 0; j < N; j++ ) // poređenje svakog para lica u nizu
        {
            if( i == j || !predicate(eps, face_coordinate[i], face_coordinate[j])) // preskakanje poređenja lica sa sobom, i preskakanje ako nisu "dovoljno slični"
                continue;
            int root2 = j;
            
            //ovaj deo koda se izvršava ako su lica dovoljno slična
            while( nodes[root2][_PArent] >= 0 )
            root2 = nodes[root2][_PArent];
            
            if( root2 != root )// ako nisu lica u istom setu
            {
                /* sjedini set, root postaje lice sa većim rankom, tj. starije lice */
                int rank = nodes[root][_RAnk], rank2 = nodes[root2][_RAnk];
                if( rank > rank2 ) 
                    nodes[root2][_PArent] = root;
                else
                {
                    nodes[root][_PArent] = root2;
                    nodes[root2][_RAnk] += rank == rank2;
                    root = root2;
                }

                int k = j, parent;

                /* kompresovanje putanje do root-a zbog lakšeg daljeg računanja */
                while( (parent = nodes[k][_PArent]) >= 0 )
                {
                    nodes[k][_PArent] = root;
                    k = parent;
                }
                
                k = i;
                while( (parent = nodes[k][_PArent]) >= 0 )
                {
                    nodes[k][_PArent] = root;
                    k = parent;
                }
            }
        }
    }

    int nclasses = 0;
    //prolaženje kroz ceo niz i prebrojavanje root-ova, time dobijamo broj klasa (lica); poslednji prolaz kroz niz (O(N))
    for( i = 0; i < N; i++ )
    {
        int root = i;
        while( nodes[root][_PArent] >= 0 )
            root = nodes[root][_PArent];
        /* rank je labela klase */
        if( nodes[root][_RAnk] >= 0 )
            nodes[root][_RAnk] = ~nclasses++;// dupla negacija jer se računa dubina stabla, a ne visina
        labels[i] = ~nodes[root][_RAnk]; //u nizu labels se nalaze labele svake klase
    }

    return nclasses;
}
// funkcija koja računa apsolutnu vrednost broja
int myAbs(int n)
{
  if (n >= 0)
    return n;
  else
    return -n;
}
/*
/ Naziv funkcije    : predicate
/ Parametri         : dva pravougaonika r1 i r2 koja sadrže 4 vrednosti piksela u ćoškovima, i eps prag tolerancije
/ Povratna vrednost : int vrednost 1 ako su pravougaonici dovoljno slični ili 0 ako nisu
/ Opis funkcije     : funkcija poredi dva pravougaonika sa 4 vrednosti piksela u ćoškovima i odrećuje da li su te vrednosti dovoljno slične, ako jesu vraća 1, u suprotnom 0
*/
int facedetect::predicate(float eps, uint16_t r1[4], uint16_t r2[4])
{
    // računanje vrednosti delta koja predstavlja toleranciju i koja se koristi za poređenje, zavisi od eps i od veličine pravougaonika
    float delta = 0.5f * eps * (((r1[2]>r2[2]) ? r2[2] : r1[2]) + ((r1[3]>r2[3]) ? r2[3] : r1[3]));
    // poređenje koordinata i razlike njihovih vrednosti, da li je manja od delta
    // ako su sve razlike manje od delta onda su pravougaonici dovoljno slični
    return myAbs(r1[0] - r2[0]) <= (int)delta &&
        myAbs(r1[1] - r2[1]) <= (int)delta &&
        myAbs(r1[0] + r1[2] - r2[0] - r2[2]) <= (int)delta &&
        myAbs(r1[1] + r1[3] - r2[1] - r2[3]) <= (int)delta;
}
/*
/ Naziv funkcije    : detection_main
/ Parametri         : image_data 2D niz piksela slike, scaleFactor_val faktor skaliranja, shiftStep_val korak pomjeranja
/ Povratna vrednost : nema
/ Opis funkcije     : main funkcija facedetect.cpp fajla; Ona cita vrijednosti slike, izvrsava algoritam i ispisuje broj lica i njegove koordinate na terminalu
/ Napomena         : SC_CTHREAD/wait() simulacioni model zamijenjen direktnim pozivom funkcija (izvrsna specifikacija)
*/
void facedetect::detection_main(uint8_t image_data[IMAGE_HEIGHT][IMAGE_WIDTH],
                                float scaleFactor_val, uint8_t shiftStep_val)
{
    int i, j;

    // konfiguracija algoritma
    cascadeObj.orig_window_size.height = 24;  // visina originalnog prozora
    cascadeObj.orig_window_size.width  = 24;  // sirina originalnog prozora
    minNeighbours = 1; // broj potrebnih susjednih pravougaonika za uspjesnu detekciju
    // minimalna velicina objekata za detekciju
    minSize.height = 20;
    minSize.width  = 20;

    ready = false; // signal da je proces detekcije u toku

    // kopiranje ulaznih podataka slike u interni bafer
    for(i = 0; i < IMAGE_HEIGHT; i++)
        for(j = 0; j < IMAGE_WIDTH; j++)
            in_img_buffer[i][j] = image_data[i][j];

    scaleFactor = scaleFactor_val;
    shiftStep   = shiftStep_val;

    // glavna funkcija za detektovanje lica, poziva sve ostale funkcije i izvrsava sve korake algoritma
    detectObjects(minSize, scaleFactor, minNeighbours, (int)shiftStep);

    ready = true;        // signal da je proces detektovanja zavrsen
    face_num_out = face_number; // broj lica

    // ispis koordinata lica na terminal (nepotrebno, komplikuje realizaciju)
   /* printf("face_num_out=%d\n", (int)face_number);
    for(i = 0; i < (int)face_number; i++){
        printf("Lice %d: x=%d y=%d w=%d h=%d\n",
               i,
               (int)face_coordinate[i][0],
               (int)face_coordinate[i][1],
               (int)face_coordinate[i][2],
               (int)face_coordinate[i][3]);
    }*/
}


/* Kraj fajla. */
