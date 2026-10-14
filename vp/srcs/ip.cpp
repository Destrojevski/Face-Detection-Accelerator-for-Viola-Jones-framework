/*
/ Naziv fajla: ip.cpp
/ Opis fajla: Implementacija IP akcelerator modula. Modeluje hardverski blok koji izvrsava Viola-Jones kaskadnu klasifikaciju za jedan prozor slike.
/ Datum : 25/12/2024
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/
#include "ip.hpp"
#include <sstream>
#include <string>
using namespace sc_core;
using namespace sc_dt;
using namespace std;
using namespace tlm;

SC_HAS_PROCESS(ip);

// Konstruktor
ip::ip(sc_module_name name) :sc_module(name), soc_ic("ip_soc_ic"), isoc_bram("ip_isoc_bram"), isoc_ddr3("ip_isoc_ddr3"), ip_interrupt("ip_interrupt")
{
    soc_ic.register_b_transport(this, &ip::b_transport_ic);
    SC_THREAD(ip_thread);
    dont_initialize();
    sensitive << register_state_updated;
    // Inicijalizacija registara
    cfg_reg = 0x00;
    p_offset_reg = 0;
    width_reg = 0;
    result_reg = 0;
    state = IDLE;
    for(int i = 0; i < 4; i++){
        p[i] = pq[i] = 0;
    }
}

// Pomocne TLM metode
/*
/ Naziv funkcije: bram_read
/ Opis: Cita 'len' bajtova sa lokalne BRAM adrese 'local_addr' u 'dst' bafer. Koristi isoc_bram direktnu vezu.
*/
void ip::bram_read(uint64_t local_addr, void* dst, uint32_t len, pl_t& pl, unsigned char* data, tlm_utils::tlm_quantumkeeper& qk, sc_time& offset)
{
    pl.set_address(local_addr);
    pl.set_data_length(len);
    pl.set_command(TLM_READ_COMMAND);
    pl.set_response_status(TLM_INCOMPLETE_RESPONSE);
    isoc_bram->b_transport(pl, offset);
    assert(pl.get_response_status() == TLM_OK_RESPONSE);
    std::memcpy(dst, data, len);
    qk.inc(sc_time(10, SC_NS));
    offset = qk.get_local_time();
    qk.set_and_sync(offset);
}

/*
/ Naziv funkcije: ddr3_read
/ Opis: Cita 'len' bajtova sa lokalne DDR3 adrese 'local_addr' u 'dst' bafer. Koristi isoc_ddr3 direktnu vezu.
*/
void ip::ddr3_read(uint64_t local_addr, void* dst, uint32_t len, pl_t& pl, unsigned char* data, tlm_utils::tlm_quantumkeeper& qk, sc_time& offset)
{
    pl.set_address(local_addr);
    pl.set_data_length(len);
    pl.set_command(TLM_READ_COMMAND);
    pl.set_response_status(TLM_INCOMPLETE_RESPONSE);
    isoc_ddr3->b_transport(pl, offset);
    assert(pl.get_response_status() == TLM_OK_RESPONSE);
    std::memcpy(dst, data, len);
    qk.inc(sc_time(10, SC_NS));
    offset = qk.get_local_time();
    qk.set_and_sync(offset);
}

/*
/ Naziv funkcije: b_transport_ic
/ Opis: TLM handler za CPU prikljucak. Obradjuje citanje i upis IP registara. Upis u cfg_reg budi ip_thread putem register_state_updated.
*/
void ip::b_transport_ic(pl_t& pl, sc_time& offset)
{
    tlm_command cmd = pl.get_command();
    uint64 addr = pl.get_address();
    unsigned char* data = pl.get_data_ptr();
    uint32_t len = pl.get_data_length();
    switch(cmd)
    {
        case TLM_WRITE_COMMAND:
        {
            switch(addr)
            {
                case IP_CFG_REG_OFFSET:
                    std::memcpy(&cfg_reg, data, sizeof(cfg_reg));
                    pl.set_response_status(TLM_OK_RESPONSE);
                    // Budi ip_thread da procita novo stanje cfg_reg
                    register_state_updated.notify(SC_ZERO_TIME);
                    break;

                case IP_P_OFFSET_REG_OFFSET:
                    std::memcpy(&p_offset_reg, data, sizeof(p_offset_reg));
                    pl.set_response_status(TLM_OK_RESPONSE);
                    break;

                case IP_WIDTH_REG_OFFSET:
                    std::memcpy(&width_reg, data, sizeof(width_reg));
                    pl.set_response_status(TLM_OK_RESPONSE);
                    break;

                default:
                    pl.set_response_status(TLM_COMMAND_ERROR_RESPONSE);
                    SC_REPORT_ERROR("IP", "Nepoznata adresa pri upisu");
            }
            break;
        }

        case TLM_READ_COMMAND:
        {
            switch(addr)
            {
                case IP_CFG_REG_OFFSET:
                    std::memcpy(data, &cfg_reg, sizeof(cfg_reg));
                    pl.set_response_status(TLM_OK_RESPONSE);
                    break;

                case IP_RESULT_REG_OFFSET:
                    // core1 cita rezultat klasifikacije nakon DONE prekida
                    std::memcpy(data, &result_reg, sizeof(result_reg));
                    pl.set_response_status(TLM_OK_RESPONSE);
                    break;

                default:
                    pl.set_response_status(TLM_COMMAND_ERROR_RESPONSE);
                    SC_REPORT_ERROR("IP", "Nepoznata adresa pri citanju");
            }
            break;
        }
        default:
            pl.set_response_status(TLM_COMMAND_ERROR_RESPONSE);
            SC_REPORT_ERROR("IP", "TLM nepoznata komanda");
    }
    offset += sc_time(5, SC_NS);
}

/*
/ Naziv funkcije: ip_thread
/ Opis: SC_THREAD koji se budi na svaki register_state_updated dogadjaj (okida ga b_transport_ic kada CPU upise cfg_reg).
/   Dekodira stanje iz cfg_reg i izvrsava odgovarajucu akciju:
/   RESET: brise registre, gasi prekid
/   START: pokrece run_cascade_classifier za tekuci prozor
/   IDLE: gasi prekid, ceka
*/
void ip::ip_thread()
{
    tlm_utils::tlm_quantumkeeper qk;
    qk.reset();
    pl_t pl;
    unsigned char data[sizeof(uint32_t)];
    pl.set_data_ptr(data);
    while(1)
    {
        sc_time offset;
        // Dekodiranje stanja iz cfg_reg
        if(cfg_reg & 0x01)
            state = RESET;
        else if(cfg_reg & 0x02)
            state = START;
        else
            state = IDLE;
        switch(state)
        {
            case RESET:
            {
                SC_REPORT_INFO("IP", "state: RESET");
                ip_interrupt.write(false);
                // Brisanje svih radnih registara
                result_reg = 0;
                p_offset_reg = 0;
                width_reg = 0;
                for(int i = 0; i < 4; i++){
		    p[i] = pq[i] = 0;
		}
                qk.inc(sc_time(10, SC_NS));
                offset = qk.get_local_time();
                qk.set_and_sync(offset);
                // Reset je ispunjen - brisanje reset bita
                cfg_reg = 0x00;
                break;
            }
			
            case START:
            {
                //SC_REPORT_INFO("IP", "state: START");
                ip_interrupt.write(false);
                /*
                Izvrsavanje kaskadne klasifikacije za tekuci prozor.
                Ulazi: p_offset_reg (= x pozicija), width_reg (= sz.width)
                Izlaz: result_reg (1=lice, -i=odbijen na fazi i)
                */
                result_reg = run_cascade_classifier(p_offset_reg, width_reg,pl, data, qk, offset);
                /*
                Signalizacija zavrsetka:
                - setovanje DONE bita (bit 4)
                - brisanje START bita (bit 1)
                - dizanje ip_interrupt signala
                */
                cfg_reg |= 0x10;  // setuj DONE bit
                cfg_reg &= ~0x02; // brisanje START bita
                ip_interrupt.write(true);
                qk.inc(sc_time(10, SC_NS));
                offset = qk.get_local_time();
                qk.set_and_sync(offset);
                break;
            }

            case IDLE:
            default:
            {
                ip_interrupt.write(false);
                qk.inc(sc_time(10, SC_NS));
                offset = qk.get_local_time();
                qk.set_and_sync(offset);
                break;
            }
        }
    }
}

/*
/ Naziv funkcije: run_cascade_classifier
/ Parametri: 
/   p_offset (x pozicija prozora),width (sz.width tekuce skale), pl, data, qk, offset (TLM infrastruktura)
/ Povratna vrednost: 1 ako je lice detektovano, -i ako je odbijen na fazi i
/ Opis: Implementira runCascadeClassifier iz originalnog koda. Prolazi kroz svih 25 faza kaskade. 
/ Za svaku fazu:
/   - cita broj klasifikatora iz BRAM
/   - poziva eval_weak_classifier za svaki
/   - akumulira stage_sum
/   - poredi sa pragom (early exit)
/Sve podatke cita direktno iz BRAM i DDR3 putem TLM.
*/
int ip::run_cascade_classifier(uint32_t p_offset, uint32_t width, pl_t& pl, unsigned char* data,tlm_utils::tlm_quantumkeeper& qk,sc_time& offset)
{
    int haar_counter = 0;
    int w_index = 0;
    int r_index = 0;
    /*
    Korak 1: updatePvalue
    Cita 4 vrednosti iz int_img_buffer i 4 iz sq_int_buffer iz DDR3.
    Racuna variance_norm_factor koji se koristi za sve slabe klasifikatore u ovom prozoru.
    */
    update_pvalue(p_offset, width, pl, data, qk, offset);
    // Racunanje variance_norm_factor (isti algoritam kao u originalnom kodu)
    unsigned int mean =(unsigned int)(p[0] - p[1] - p[2] + p[3]);
    unsigned int variance_norm_factor =(unsigned int)(pq[0] - pq[1] - pq[2] + pq[3]);
    variance_norm_factor = variance_norm_factor * (unsigned int)INV_WINDOW_AREA;
    variance_norm_factor = variance_norm_factor - mean * mean;

    if(variance_norm_factor > 0)
        variance_norm_factor = int_sqrt(variance_norm_factor);
    else
        variance_norm_factor = 1;

    /* Korak 2: Petlja kroz 25 faza kaskade */
    for(int i = 0; i < NUM_STAGES; i++)
    {
        /* Citanje broja klasifikatora u ovoj fazi iz BRAM (stages_array[i], lokalna adresa: VP_ADDR_BRAM_STAGES + i) */
        uint8_t num_classifiers = 0;
        bram_read(VP_ADDR_BRAM_STAGES + i, &num_classifiers,sizeof(uint8_t), pl, data, qk, offset);
        int stage_sum = 0;

        /* Petlja kroz sve slabe klasifikatore u ovoj fazi */
        for(int j = 0; j < (int)num_classifiers; j++)
        {
            stage_sum += eval_weak_classifier((int)variance_norm_factor, (int)p_offset,haar_counter, w_index, r_index,width, pl, data, qk, offset);
            haar_counter++;
            w_index += 3;
            r_index += 12;
        }

        /* Citanje praga faze iz BRAM (stages_thresh_array[i], lokalna adresa: VP_ADDR_BRAM_STAGES_TH + i) */
        int16_t stage_thresh = 0;
        bram_read(VP_ADDR_BRAM_STAGES_TH + i, &stage_thresh,sizeof(int16_t), pl, data, qk, offset);

        /* Poredjenje sa pragom (faktor 0.4 = 2/5 celobrojna aproksimacija), ako stage_sum < 0.4 * stage_thresh, odbijen na fazi i */
        if(stage_sum * 5 < (int)stage_thresh * 2)
            return -i; // early exit: odbijen na fazi i

    } // kraj petlje po fazama
    return 1; // prosao sve faze, lice detektovano
}

/*
/ Naziv funkcije: eval_weak_classifier
/ Parametri: variance_norm_factor, p_offset, tree_index, w_index, r_index, width, TLM infrastruktura
/ Povratna vrednost: alpha1 ili alpha2 vrednost (int)
/ Opis: Implementira evalWeakClassifier iz originalnog koda. Ne koristi scaled_rectangles_array. Umesto toga cita raw (x,y,w,h) iz rectangles_array u BRAM
/ i racuna linearne ofset indekse direktno koristeci 'width'. 
/ Svih 9 podataka iz BRAM (tree_thresh, 3x4 rect polja, 3 weights) i do 12 podataka iz DDR3 (int_img vrednosti) cita TLM-om.
*/
int ip::eval_weak_classifier(int variance_norm_factor, int p_offset,int tree_index, int w_index, int r_index,uint32_t width,pl_t& pl, unsigned char* data,tlm_utils::tlm_quantumkeeper& qk,sc_time& offset)
{
    /* Korak 1: Citanje tree_thresh_array[tree_index] iz BRAM, Lokalna adresa: VP_ADDR_BRAM_TREE_TH + tree_index */
    int16_t tree_thresh = 0;
    bram_read(VP_ADDR_BRAM_TREE_TH + tree_index, &tree_thresh,sizeof(int16_t), pl, data, qk, offset);
    int t = (int)tree_thresh * variance_norm_factor;
    int sum = 0;
    /*
    Korak 2: Obrada 3 pravougaonika (k = 0, 1, 2)
    Za svaki pravougaonik:
      a. Cita 4 char vrednosti (x, y, w, h) iz rectangles_array u BRAM
      b. Racuna 4 linearna ofset indeksa u int_img_buffer (zamena za scaled_rect)
      c. Cita weight iz weights_array u BRAM
      d. Cita 4 int vrednosti iz int_img_buffer u DDR3
      e. Akumulira sumu
    */
    for(int k = 0; k < 3; k++)
    {
        /*
        a. Citanje raw (x, y, w, h) iz rectangles_array u BRAM
           Svaki pravougaonik je 4 vrednosti, svaka u svom short int slotu.
           Citamo 4 odvojena short int, jer mem[] je short int niz
           (svaka char vrednost zauzima jedan 2-bajtni slot).
        */
        short int sv;
        bram_read(VP_ADDR_BRAM_RECT + r_index + k*4 + 0, &sv, sizeof(short int), pl, data, qk, offset);
        char rx = (char)sv;
        bram_read(VP_ADDR_BRAM_RECT + r_index + k*4 + 1, &sv, sizeof(short int), pl, data, qk, offset);
        char ry = (char)sv;
        bram_read(VP_ADDR_BRAM_RECT + r_index + k*4 + 2, &sv, sizeof(short int), pl, data, qk, offset);
        char rw = (char)sv;
        bram_read(VP_ADDR_BRAM_RECT + r_index + k*4 + 3, &sv, sizeof(short int), pl, data, qk, offset);
        char rh = (char)sv;

        /* Null provera za treci pravougaonik (k == 2), ako su sva 4 polja nula, treci pravougaonik ne postoji */
        if(k == 2 && rx == 0 && ry == 0 && rw == 0 && rh == 0)
            break;

        /*
        b. Racunanje linearnih ofset indeksa u int_img_buffer
           Ovo zamenjuje scaled_rectangles_array koji vise ne postoji.
           Formula: linearni_indeks = width * y + x
        */
        int tl = (int)width * (int)ry + (int)rx; // gornji levi
        int tr = (int)width * (int)ry + ((int)rx + (int)rw); // gornji desni
        int bl = (int)width * ((int)ry + (int)rh) + (int)rx; // donji levi
        int br = (int)width * ((int)ry + (int)rh) + ((int)rx + (int)rw); // donji desni

        /* c. Citanje weights_array[w_index + k] iz BRAM Lokalna adresa: VP_ADDR_BRAM_WEIGHTS + w_index + k */
        int16_t weight = 0;
        bram_read(VP_ADDR_BRAM_WEIGHTS + w_index + k, &weight,sizeof(int16_t), pl, data, qk, offset);
        /*
        d. Citanje 4 int_img vrednosti iz DDR3
           Lokalna DDR3 adresa: tl/tr/bl/br + p_offset
           (p_offset pomera prozor horizontalno u tekucem redu)
        */
        int img_tl, img_tr, img_bl, img_br;

        ddr3_read(tl + p_offset, &img_tl, sizeof(int), pl, data, qk, offset);
        ddr3_read(tr + p_offset, &img_tr, sizeof(int), pl, data, qk, offset);
        ddr3_read(bl + p_offset, &img_bl, sizeof(int), pl, data, qk, offset);
        ddr3_read(br + p_offset, &img_br, sizeof(int), pl, data, qk, offset);

        /*
        e. Akumulacija: Haar-like karakteristika = suma po cetiri coska
           (integralna slika formula)
        */
        sum += (img_tl - img_tr - img_bl + img_br) * (int)weight;
    } // kraj k petlje

    /* Korak 3: Poredjenje sa pragom i citanje alpha vrednosti iz BRAM, Ako sum >= t: vraca alpha2[tree_index], u suprotnom vraca alpha1[tree_index] */
    int16_t alpha = 0;
    if(sum >= t)
        bram_read(VP_ADDR_BRAM_ALPHA2 + tree_index, &alpha,sizeof(int16_t), pl, data, qk, offset);
    else
        bram_read(VP_ADDR_BRAM_ALPHA1 + tree_index, &alpha,sizeof(int16_t), pl, data, qk, offset);

    return (int)alpha;
}

/*
/ Naziv funkcije: update_pvalue
/ Opis: Cita 8 vrednosti iz DDR3 koje odgovaraju cetiri coska 24x24 prozora u integralnoj i kvadriranoj integralnoj slici.
/   Rezultati se cuvaju u internim promenljivama p[] i pq[].
/   int_img_buffer: DDR3 lokalne adrese 0..8999
/   sq_int_buffer:  DDR3 lokalne adrese 9000..17999
/   (VP_ADDR_DDR3_INT_IMG i VP_ADDR_DDR3_SQ_INT su 0 i 9000)
*/
void ip::update_pvalue(int p_offset, uint32_t width,pl_t& pl, unsigned char* data, tlm_utils::tlm_quantumkeeper& qk, sc_time& offset)
{
    // Cetiri coska 24x24 prozora u int_img i sq_int baferima
    // p_offset = x(horizontalna pozicija prozora)
    // width = sz.width (sirina tekuce skale slike)
    int corners[4] = {p_offset,p_offset + ORIG_WIN_WIDTH - 1,p_offset + (int)width * (ORIG_WIN_HEIGHT - 1),p_offset + (int)width * (ORIG_WIN_HEIGHT - 1) + ORIG_WIN_WIDTH - 1};

    /* Citanje p0..p3 iz int_img_buffer (DDR3 lokalne adrese 0..8999) */
    for(int c = 0; c < 4; c++){
        ddr3_read(VP_ADDR_DDR3_INT_IMG + corners[c], &p[c],sizeof(int), pl, data, qk, offset);
    }
    
    /* Citanje pq0..pq3 iz sq_int_buffer (DDR3 lokalne adrese 9000..17999) */
    for(int c = 0; c < 4; c++){
        ddr3_read(VP_ADDR_DDR3_SQ_INT + corners[c], &pq[c],sizeof(int), pl, data, qk, offset);
    }
}

/*
/ Naziv funkcije: int_sqrt
/ Parametri: unsigned int vrednost
/ Povratna vrednost: unsigned int koren (a takvo da a^2 <= value)
/ Opis: Celobrojna kvadratna korena upotrebom bitwise iterativne metode. Izbegava floating-point operacije - pogodno za HW implementaciju.
/ Ista implementacija kao u originalnom facedetect.cpp.
*/
unsigned int ip::int_sqrt(unsigned int value)
{
    int i;
    unsigned int a = 0, b = 0, c = 0;
    for(i = 0; i < (32 >> 1); i++)
    {
        c <<= 2;
        c += value >> 30;
        value <<= 2;
        a <<= 1;
        b = (a << 1) | 1;
        if(c >= b)
        {
            c -= b;
            a++;
        }
    }
    return a;
}
