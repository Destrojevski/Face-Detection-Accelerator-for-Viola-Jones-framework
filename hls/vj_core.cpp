/*
/ Naziv fajla:vj_core.cpp
/ Opis fajla:Implementacija Viola-Jones HLS IP jezgra:
/- TLM infrastruktura uklonjena
/- tipovi podataka zamijenjeni  ap tipovima
/- pristup BRAM-u i DDR3-u: preko direktnog indeksiranja nizova
/ Datum: 23/3/2026
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/
#include "vj_core.h"
// Konstruktor sa inicijalizacijom
VJCore::VJCore(){
    cfg_reg=ap_uint<8>(0);
    p_offset_reg=0;
    width_reg=0;
    result_reg=0;
    ip_interrupt=false;
    state=IDLE;
    for(int i = 0; i < 4; i++)
    p[i]=pq[i]=0;
}
/* int_sqrt
/Cjelobrojno izracunavanje kvadratnog korijena upotrebom bitwise iterativne metode.
/Izbjegava floating-point aritmetiku kako bi bio hardverski kompatibilan
/Koristi 32-bitnu aritmetiku kao iz IP modela u VP(ip.cpp).
*/
static ap_uint<32> int_sqrt(ap_uint<32> value){
    int i;
    ap_uint<32> a = 0;
    ap_uint<32> b = 0;
    ap_uint<32> c = 0;
    for(i = 0; i < 16; i++){
    c<<=2;
    c+= value>>30;
    value<<=2;
    a<<=1;
    b=(a<<1) | 1;
    if(c>=b){
        c -=b;
        a++;
        }
    }
    return a;
}

// eval_weak_classifier funkcija
static ap_int<16> eval_weak_classifier(ap_uint<32> variance_norm_factor,ap_uint<32> p_offset,int tree_index,int w_index,int r_index,
ap_uint<32> width,ap_int<16> bram[BRAM_SIZE],ap_int<32> ddr3[DDR3_TOTAL_SIZE]){

//Korak 1: Citanje tree_thresh_array[tree_index] iz BRAMa
    ap_int<16> tree_thresh= bram[VP_ADDR_BRAM_TREE_TH + tree_index];
    ap_int<32> t= (ap_int<32>)tree_thresh * (ap_int<32>)variance_norm_factor;
    ap_int<40> sum= 0;

//Korak 2: Obrada 3 pravougaonika (k=0,1,2)
    for(int k=0;k<3;k++){
        /*a. Citanje raw podataka o pravougaonicima(x,y,w,h) iz rectangles_array u BRAMu
        Svaka short int vrijednost zauzima jedan ap_int<16> slot.
        */
        ap_int<8> rx = (ap_int<8>)bram[VP_ADDR_BRAM_RECT + r_index + k*4 + 0];
        ap_int<8> ry = (ap_int<8>)bram[VP_ADDR_BRAM_RECT + r_index + k*4 + 1];
        ap_int<8> rw = (ap_int<8>)bram[VP_ADDR_BRAM_RECT + r_index + k*4 + 2];
        ap_int<8> rh = (ap_int<8>)bram[VP_ADDR_BRAM_RECT + r_index + k*4 + 3];

        /* Null provjera za treci pravougaonik */
        if(k == 2 && rx == 0 && ry == 0 && rw == 0 && rh == 0)
            break;

        /* b. Racunanje linearnih ofset indeksa u int_img_buffer
        Formula:linearni_indeks = width * y + x*/
        ap_uint<14> tl = (ap_uint<14>)width * (ap_uint<14>)ry + (ap_uint<14>)rx;
        ap_uint<14> tr = (ap_uint<14>)width * (ap_uint<14>)ry + (ap_uint<14>)(rx + rw);
        ap_uint<14> bl = (ap_uint<14>)width * (ap_uint<14>)(ry + rh) + (ap_uint<14>)rx;
        ap_uint<14> br = (ap_uint<14>)width * (ap_uint<14>)(ry + rh) + (ap_uint<14>)(rx + rw);

        /* c. Citanje weights_array[w_index + k] iz BRAMa */
        ap_int<16> weight = bram[VP_ADDR_BRAM_WEIGHTS + w_index + k];

        // d. Citanje 4 int_img vrijednosti iz DDR3 */
        ap_int<32> img_tl = ddr3[(ap_uint<32>)tl + p_offset];
        ap_int<32> img_tr = ddr3[(ap_uint<32>)tr + p_offset];
        ap_int<32> img_bl = ddr3[(ap_uint<32>)bl + p_offset];
        ap_int<32> img_br = ddr3[(ap_uint<32>)br + p_offset];

        /* e. Akumulacija: Haarova karakteristika = suma po cetiri coska */
        sum += (ap_int<40>)(img_tl - img_tr - img_bl + img_br) * (ap_int<40>)weight;
    } // kraj k petlje

    //Korak 3: Poredjenje sa pragom i citanje alpha vrijednosti iz BRAM
    ap_int<16> alpha;
    if(sum >= t)
        alpha = bram[VP_ADDR_BRAM_ALPHA2 + tree_index];
    else
        alpha = bram[VP_ADDR_BRAM_ALPHA1 + tree_index];
    return alpha;
}

// run_cascade_classifier
static ap_int<32> run_cascade_classifier(ap_uint<32> p_offset,ap_uint<32> width,ap_int<32> p[4],ap_int<32> pq[4],ap_int<16> bram[BRAM_SIZE],ap_int<32> ddr3[DDR3_TOTAL_SIZE]){
//inicijalizacija indeksa i brojacke promjenljive
ap_uint<12> haar_counter = 0;
ap_uint<14> w_index = 0;
ap_uint<16> r_index = 0;
/*Korak 1: update_pvalue (preveden u inline funkciju)
Cita vrijednosti 4 coska integralne slike iz int_img_buffer i 4 coska kvadrirane integralne slike iz sq_int_buffer iz DDR3.*/
    ap_uint<14> corners[4];
    corners[0] = (ap_uint<14>)p_offset;
    corners[1] = (ap_uint<14>)(p_offset + ORIG_WIN_WIDTH - 1);
    corners[2] = (ap_uint<14>)(p_offset + (ap_uint<32>)width * (ORIG_WIN_HEIGHT - 1));
    corners[3] = (ap_uint<14>)(p_offset + (ap_uint<32>)width * (ORIG_WIN_HEIGHT - 1) + ORIG_WIN_WIDTH - 1);
    for(int c = 0; c < 4; c++)
        p[c]  = ddr3[corners[c]];
    for(int c = 0; c < 4; c++)
        pq[c] = ddr3[DDR3_SQ_INT_OFFSET + corners[c]];
    /*Korak 2: Racunanje variance_norm_factor
    Koristi 32-bitnu unsigned aritmetiku , kao i IP iz VPa koji koristi unsigned int*/
    ap_uint<32> mean32=(ap_uint<32>)(p[0] - p[1] - p[2] + p[3]);
    ap_uint<32> pq_sum32=(ap_uint<32>)(pq[0] - pq[1] - pq[2] + pq[3]);
    ap_uint<32> vnf32= pq_sum32 * (ap_uint<32>)INV_WINDOW_AREA;
    vnf32=vnf32-mean32*mean32;
    ap_uint<32> variance_norm_factor;
    if(vnf32 > 0)
        variance_norm_factor = int_sqrt(vnf32);
    else
        variance_norm_factor = 1;
    /*Korak 3: Petlja kroz 25 faza kaskade*/
    for(int i = 0; i < NUM_STAGES; i++){
        /* Citanje broja klasifikatora u ovoj fazi iz BRAM */
        ap_uint<8> num_classifiers = (ap_uint<8>)bram[VP_ADDR_BRAM_STAGES + i];
        ap_int<24> stage_sum = 0;
        /* Petlja kroz sve slabe klasifikatore u ovoj fazi */
        for(int j = 0; j < (int)num_classifiers; j++){
            stage_sum += eval_weak_classifier(variance_norm_factor, p_offset,(int)haar_counter, (int)w_index, (int)r_index,width, bram, ddr3);
            haar_counter++;
            w_index += 3;
            r_index += 12;
        }
        /* Citanje praga faze iz BRAM */
        ap_int<16> stage_thresh = bram[VP_ADDR_BRAM_STAGES_TH + i];
        /* Poredjenje sa pragom: stage_sum < 0.4 * stage_thresh - odbijen na i fazi */
        if(stage_sum * 5 < (ap_int<24>)stage_thresh * 2)
            return (ap_int<32>)(-i);
    } // kraj petlje po fazama
    return ap_int<32>(1);
}

// top_function
void top_function(ap_uint<8> *cfg_val,ap_uint<32> p_offset,ap_uint<32> width,ap_int<16> bram[BRAM_SIZE],ap_int<32> ddr3[DDR3_TOTAL_SIZE],bool *ip_interrupt,ap_int<32> *result){
static VJCore IP;
IP.cfg_reg = *cfg_val;
//promjena stanja zavisno od stanja konfiguracionog registra
    if(IP.cfg_reg[IP_RESET_BIT])
    IP.state = RESET;
    else if(IP.cfg_reg[IP_START_BIT])
    IP.state = START;
    else
    IP.state = IDLE;
//reagovanje na promjene stanja
    switch(IP.state){
    case IDLE:
    {
    IP.ip_interrupt = false;
    break;
    }
    case RESET:
    {
    IP.ip_interrupt=false;
    IP.result_reg=0;
    IP.p_offset_reg=0;
    IP.width_reg=0;
    reset_l:for(int i = 0; i < 4; i++)
        IP.p[i] = IP.pq[i] = 0;
    IP.cfg_reg = ap_uint<8>(0);
    break;
    }
    case START:
    {
    IP.ip_interrupt = false;
    IP.p_offset_reg = p_offset;
    IP.width_reg = width;
    IP.result_reg = run_cascade_classifier(IP.p_offset_reg, IP.width_reg, IP.p, IP.pq,bram, ddr3);
    IP.cfg_reg.set(IP_DONE_BIT, 1);
    IP.cfg_reg.set(IP_START_BIT, 0);
    IP.ip_interrupt = true;
    break;
    }
   }
    *cfg_val = IP.cfg_reg;
    *ip_interrupt = IP.ip_interrupt;
    *result = IP.result_reg;
}
