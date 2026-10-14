/*
/ Naziv fajla: tb_vp.cpp
/ Opis fajla: Implementacija testbench modula.
/   core0: ucitavanje slike iz fajla, slanje parametara IP-u, cekanje rezultata i ispis.
/   core1: koordinacija algoritma detekcije lica - racunanje integralnih slika, upisivanje u DDR3, pokretanje IP-a po prozoru, groupRectangles.
/   gic: SC_METHOD, demultipleksuje IRQ_F2P signal.
/   IP_ISR: SC_THREAD, prekidna rutina za IP - potvrdjuje DONE bit i notifikuje core1 da moze citati rezultat.
/ Datum: 28/12/2024
/ Autori: Sandic Vojislav, Glisevic Sara, Jovic Radivoje
*/

#include "tb_vp.hpp"

using namespace sc_core;
using namespace sc_dt;
using namespace std;
using namespace tlm;

SC_HAS_PROCESS(tb_vp);
tb_vp::tb_vp(sc_module_name name): sc_module(name), isoc("tb_vp_isoc"), IRQ_F2P("IRQ_F2P"){
    SC_THREAD(core0);
    SC_THREAD(core1);

    SC_METHOD(gic);
    dont_initialize();
    sensitive << IRQ_F2P;

    SC_THREAD(IP_ISR);
    sensitive << ip_interrupt_event;

    SC_METHOD(exit_simulation);
    dont_initialize();
    sensitive << end_of_simulation;
}

/*
/ Naziv funkcije: tlm_write
/ Opis: Pomocna metoda za TLM upis jednog podatka. Upisuje 'len' bajtova sa adrese 'src' na globalnu adresu 'addr'.
*/
void tb_vp::tlm_write(uint64_t addr, void* src, uint32_t len, pl_t& pl, unsigned char* data, tlm_utils::tlm_quantumkeeper& qk, sc_time& offset) {
    std::memcpy(data, src, len);
    pl.set_address(addr);
    pl.set_data_length(len);
    pl.set_command(TLM_WRITE_COMMAND);
    pl.set_response_status(TLM_INCOMPLETE_RESPONSE);
    isoc->b_transport(pl, offset);
    assert(pl.get_response_status() == TLM_OK_RESPONSE);

    qk.inc(sc_time(10, SC_NS));
    offset = qk.get_local_time();
    qk.set_and_sync(offset);
}

/*
/ Naziv funkcije: tlm_read
/ Opis: Pomocna metoda za TLM citanje jednog podatka. Cita 'len' bajtova sa globalne adrese 'addr' u 'dst'.
*/
void tb_vp::tlm_read(uint64_t addr, void* dst, uint32_t len, pl_t& pl, unsigned char* data, tlm_utils::tlm_quantumkeeper& qk, sc_time& offset){
    pl.set_address(addr);
    pl.set_data_length(len);
    pl.set_command(TLM_READ_COMMAND);
    pl.set_response_status(TLM_INCOMPLETE_RESPONSE);
    isoc->b_transport(pl, offset);
    assert(pl.get_response_status() == TLM_OK_RESPONSE);
    std::memcpy(dst, data, len);

    qk.inc(sc_time(10, SC_NS));
    offset = qk.get_local_time();
    qk.set_and_sync(offset);
}

/*
/ Naziv funkcije: write_integral_buffers_to_ddr3
/ Opis: Upisuje int_img_buffer i sq_int_buffer u DDR3 memoriju kako bi IP mogao da ih cita direktno. Upisuje 'width' * 25 int vrednosti po baferu.
*/
void tb_vp::write_integral_buffers_to_ddr3(int* int_img, int* sq_int, uint32_t width, pl_t& pl, unsigned char* data, tlm_utils::tlm_quantumkeeper& qk, sc_time& offset){
    int count = 25 * (int)width;
    for(int k = 0; k < count; k++){
        // Upis int_img_buffer[k] u DDR3 na adresu VP_ADDR_DDR3_INT_IMG + k
        tlm_write(VP_ADDR_DDR3_INT_IMG + k, &int_img[k], sizeof(int), pl, data, qk, offset);
    }

    for(int k = 0; k < count; k++){
        // Upis sq_int_buffer[k] u DDR3 na adresu VP_ADDR_DDR3_SQ_INT + k
        tlm_write(VP_ADDR_DDR3_SQ_INT + k, &sq_int[k], sizeof(int), pl, data, qk, offset);
    }
}

/*
/ Naziv funkcije: gic
/ Opis: SC_METHOD koji se okida na svaku promenu IRQ_F2P signala. Demultipleksuje 2-bitni signal i notifikuje odgovarajuci dogadjaj. Bit 0 = IP prekid.
*/
void tb_vp::gic()
{
    sc_uint<2> irq = IRQ_F2P.read();
    //SC_REPORT_INFO("TB", "Prekid registrovan!");
    //cout << endl << irq[1] << irq[0] << endl;

    if(irq[0])
        ip_interrupt_event.notify(SC_ZERO_TIME);
}

/*
/ Naziv funkcije: IP_ISR
/ Opis: SC_THREAD koji ceka na ip_interrupt_event. Cita cfg_reg, proverava DONE bit (bit 4). 
/ Ako je DONE bit setovan: brise ga i notifikuje ip_done_event kako bi core1 mogao da nastavi.
*/
void tb_vp::IP_ISR()
{
    tlm_utils::tlm_quantumkeeper qk;
    qk.reset();

    while(1)
    {
        wait(ip_interrupt_event);
        //SC_REPORT_INFO("TB", "IP prekid registrovan!");

        pl_t pl;
        unsigned char data[sizeof(uint32_t)];
        pl.set_data_ptr(data);
        sc_time offset;

        // Citanje cfg_reg registra IP-a
        uint8_t cfg;
        tlm_read(VP_ADDR_IP_CFG_REG, &cfg, sizeof(uint8_t), pl, data, qk, offset);

        // Ako je IP_DONE_BIT (bit 4) setovan, brise se i notifikuje core1
        if(cfg & 0x10){
            cfg &= 0xEF; // brisanje DONE bita
            tlm_write(VP_ADDR_IP_CFG_REG, &cfg, sizeof(uint8_t), pl, data, qk, offset);
            
            ip_done_event.notify(SC_ZERO_TIME);
        }
    }
}

/*
/ Naziv funkcije: exit_simulation
/ Opis: SC_METHOD koji zaustavlja simulaciju kada core0 notifikuje end_of_simulation.
*/
void tb_vp::exit_simulation(){
    sc_stop();
}

/*
/ Naziv funkcije: core0
/ Opis: Modeluje CPU jezgro 0. Odgovorno za:
/   1. Konverziju ulazne slike (jpg -> pgm)
/   2. Ucitavanje piksel podataka u lokalnu strukturu imageObj
/   3. Citanje parametara algoritma iz fajla
/   4. Notifikovanje core1 da je slika spremna
/   5. Cekanje na zavrsetak detekcije
/   6. Ispis rezultata
*/
void tb_vp::core0()
{
    tlm_utils::tlm_quantumkeeper qk;
    qk.reset();

    pl_t pl;
    unsigned char data[sizeof(uint32_t)];
    pl.set_data_ptr(data);
    sc_time offset;

    /* Korak 1: Konverzija ulazne slike iz ../data/input.jpg u Face.pgm (greyscale, resize na 360x240) */
    SC_REPORT_INFO("core0", "Priprema slike...");
    operation();

    /* Korak 2: Ucitavanje Face.pgm u lokalnu MyImage strukturu imageObj, imageObj.data ce koristiti core1 direktno (deljeni pokazivac). */
    SC_REPORT_INFO("core0", "Ucitavanje slike...");
    int flag = readPgm((char*)"Face.pgm", &imageObj);
    if(flag == -1){
        SC_REPORT_ERROR("core0", "Ne mogu otvoriti Face.pgm!");
        end_of_simulation.notify();
        return;
    }

    qk.inc(sc_time(10, SC_NS));
    offset = qk.get_local_time();
    qk.set_and_sync(offset);

    /* Korak 3: Citanje scaleFactor i shiftStep iz parameter.txt */
    float scaleFactor;
    int shiftStep;

    FILE* fp = fopen("../data/parameter.txt", "r");
    if(!fp)
    {
        SC_REPORT_ERROR("core0", "Nije moguce otvoriti parameter.txt!");
        end_of_simulation.notify();
        return;
    }
    if(fscanf(fp, "%f", &scaleFactor)); //if utišava upozorenje za neiskorišćenu return vrednost funkcije
    if(fscanf(fp, "%d", &shiftStep)); //if utišava upozorenje za neiskorišćenu return vrednost funkcije
    fclose(fp);
	shared_scale_factor = scaleFactor;
	shared_shift_step = (uint8_t)shiftStep;
    printf("-- core0: scaleFactor = %.2f, shiftStep = %d --\r\n", scaleFactor, shiftStep);

    /* Korak 4: Reset IP-a za cist start */
    SC_REPORT_INFO("core0", "Reset IP modula...");
    uint8_t cfg = 0x01; // IP_RESET_BIT
    tlm_write(VP_ADDR_IP_CFG_REG, &cfg, sizeof(uint8_t), pl, data, qk, offset);

    /* Korak 5: Notifikovanje core1 da su slika i parametri spremni, core1 ce koristiti imageObj.data direktno, nema potrebe za TLM transferom raw piksela u DDR3. */
    SC_REPORT_INFO("core0", "Slika i parametri su spremni. Notifikujem core1.");
    new_image_ready.notify(SC_ZERO_TIME);

    /* Korak 6: Cekanje na zavrsetak detekcije od strane core1 */
    wait(detection_done);
    SC_REPORT_INFO("core0", "Detekcija je zavrsena!");

    printf("\n-- Broj detektovanih lica: %d --\n", (int)shared_face_count);

    /* Korak 7: Ciscenje i zavrsetak */
    freeImage(&imageObj);
    remove("Face.pgm");

    end_of_simulation.notify();
}

/*
/ Naziv funkcije: core1
/ Opis: Modeluje CPU jezgro 1. Odgovorno za:
/   1. Kopiranje raw piksela iz imageObj u lokalni bafer
/   2. Citanje parametara iz IP registara
/   3. Petlju detekcije (detectObjects):
/     - integralImages_fused / integralmages_lastrow_fused
/     - Upis int_img i sq_int bafera u DDR3
/     - Pokretanje IP-a za svaki prozor (write p_offset + START)
/     - Cekanje na ip_done_event
/     - Citanje result_reg i cuvanje face_coordinate
/   4. groupRectangles (cisto SW)
/   5. Notifikovanje detection_done
*/
void tb_vp::core1()
{
    tlm_utils::tlm_quantumkeeper qk;
    qk.reset();

    pl_t pl;
    unsigned char data[sizeof(uint32_t)];
    pl.set_data_ptr(data);
    sc_time offset;

    /* Cekanje na notifikaciju od core0 (slika i parametri su spremni) */
    wait(new_image_ready);
    SC_REPORT_INFO("core1", "Slika primljena. Pocinjem detekciju.");

    /* 
    Kopiranje raw piksela iz imageObj.data u clan klase in_img_buffer.
    Ovaj bafer ce koristiti integralImages_fused i integralmages_lastrow_fused.
    in_img_buffer je clan klase (heap) - ne lokalna promenljiva na stack-u.
    */
    face_number = 0;
    for(int i = 0; i < IMAGE_HEIGHT; i++)
        for(int j = 0; j < IMAGE_WIDTH; j++)
            in_img_buffer[i][j] = (sc_uint<8>)imageObj.data[i * IMAGE_WIDTH + j];

    SC_REPORT_INFO("core1", "Piksel podaci kopirani u bafer clana klase.");

    /* Citanje scaleFactor i shiftStep iz core0 */
	float scaleFactor = shared_scale_factor;
	uint8_t shiftStep = shared_shift_step;

    printf("-- core1: scaleFactor = %.2f, shiftStep = %d --\r\n", scaleFactor, (int)shiftStep);

    // Napomena: int_img_buffer, sq_int_buffer, face_coordinate i face_number
    // su clanovi klase (heap), ne lokalne promenljive.

    // Kaskadna konfiguracija (konstante - window size je uvek 24x24)
    const int ORIG_WIN_W = 24;
    const int ORIG_WIN_H = 24;
    MySize minSize = {20, 20};
    const int minNeighbours = 1;
    const sc_ufixed<8,1,SC_RND,SC_SAT> GROUP_EPS = 0.4;

    // faktor skaliranja kao sc_ufixed za myRound kompatibilnost
    sc_ufixed<8,1,SC_RND,SC_SAT> scaleFactor_uf = scaleFactor;

    /*
    PETLJA DETEKCIJE (detectObjects)
    Iterira kroz piramidu skala slike. Za svaku skalu:
      - racuna integralnu sliku za y_bias=0
      - upisuje je u DDR3
      - pokrece IP za svaki x prozor
      - azurira integralnu sliku i ponavlja za svaki y_bias
    */
    SC_REPORT_INFO("core1", "Pocinjem detectObjects petlju...");

    for(sc_ufixed<10,5,SC_RND,SC_SAT> factor = 1; ; factor *= scaleFactor_uf)
    {
        // Dimenzije downsampled slike za ovu skalu
        MySize sz = { (int)(IMAGE_WIDTH  / factor), (int)(IMAGE_HEIGHT / factor) };

        // Dimenzije prozora u originalnoj skali slike
        MySize winSize = { myRound((sc_ufixed<16,12,SC_RND,SC_SAT>)(ORIG_WIN_W * factor)), myRound((sc_ufixed<16,12,SC_RND,SC_SAT>)(ORIG_WIN_H * factor)) };

        // Izlaz iz petlje ako je downsampled slika manja od prozora
        if(sz.width < 24 || sz.height < 24)
            break;

        // Preskoči ako je prozor u originalnoj skali manji od minimalne velicine
        if(winSize.width < minSize.width || winSize.height < minSize.height)
            continue;

        /* Upis sz.width u IP registar (menja se po skali). IP koristi width za racunanje indeksa u integralnoj slici. */
        uint32_t width_val = (uint32_t)sz.width;
        tlm_write(VP_ADDR_IP_WIDTH_REG, &width_val, sizeof(uint32_t), pl, data, qk, offset);

        /* 
        Racunanje integralne i kvadrirane integralne slike za y_bias=0. Cita raw piksel podatke iz lokalnog in_img_buffer.
        Rezultat se cuva u lokalnim baferima int_img_buffer i sq_int_buffer.
        */
        integralImages_fused(in_img_buffer, int_img_buffer, sq_int_buffer, sz.width, sz.height, factor, 0);

        /* Upis int_img_buffer i sq_int_buffer u DDR3 memoriju. IP ce ih citati direktno iz DDR3 tokom klasifikacije prozora. */
        write_integral_buffers_to_ddr3(int_img_buffer, sq_int_buffer, sz.width, pl, data, qk, offset);

        /*
        ScaleImage_Invoker za y_bias = 0:
        Iterira po x pozicijama prozora. Za svaki prozor:
          - upisuje p_offset (tj. x) u IP registar
          - setuje START bit u cfg_reg
          - ceka na ip_done_event (IP_ISR ga notifikuje kada je DONE bit setovan)
          - cita result_reg
          - ako je result > 0 (lice), cuva koordinate
        */
        int x2 = sz.width - ORIG_WIN_W;

        for(int x = 0; x <= x2 - 1; x += (int)shiftStep)
        {
            // Upis p_offset = x u IP registar
            uint32_t p_off = (uint32_t)x;
            tlm_write(VP_ADDR_IP_P_OFFSET_REG, &p_off, sizeof(uint32_t), pl, data, qk, offset);

            // Pokretanje IP-a (setovanje START bita)
            uint8_t cfg = 0x02; // IP_START_BIT
            tlm_write(VP_ADDR_IP_CFG_REG, &cfg, sizeof(uint8_t), pl, data, qk, offset);

            // Cekanje na zavrsetak IP-a (IP_ISR notifikuje ip_done_event)
            wait(ip_done_event);

            // Citanje result_reg
            int32_t result = 0;
            tlm_read(VP_ADDR_IP_RESULT_REG, &result, sizeof(int32_t), pl, data, qk, offset);

            // Ako je lice detektovano, cuvanje koordinata u lokalnom nizu
            if(result > 0 && face_number < MAX_NUM_FACE - 1){
                face_coordinate[face_number][0] = myRound((sc_ufixed<16,12,SC_RND,SC_SAT>)(x * factor));
                face_coordinate[face_number][1] = myRound((sc_ufixed<16,12,SC_RND,SC_SAT>)(0 * factor));
                face_coordinate[face_number][2] = winSize.width;
                face_coordinate[face_number][3] = winSize.height;
                face_number++;
            }
        }

        /*
        Petlja po y_bias vrednostima (klizeci prozor po vertikali):
        Za svaki y_bias:
          - azurira integralnu sliku (samo poslednji red)
          - upisuje u DDR3
          - ponavlja ScaleImage_Invoker petlju
        */
        for(int y_bias = 1; y_bias < sz.height - 25 + 1; y_bias++)
        {
            /* Azuriranje integralnih slika: pomeranje bafera navise i racunanje poslednjeg reda za novi y_bias. Cita raw piksel podatke iz lokalnog in_img_buffer. */
            integralmages_lastrow_fused(in_img_buffer, int_img_buffer, sq_int_buffer, sz.width, sz.height, factor, y_bias);

            /* Upis azuriranih bafera u DDR3. IP ce citati azurirane vrednosti pri sledecoj invokaciji. */
            write_integral_buffers_to_ddr3(int_img_buffer, sq_int_buffer, sz.width, pl, data, qk, offset);

            /* ScaleImage_Invoker za tekuci y_bias: Isti postupak kao za y_bias=0. */
            for(int x = 0; x <= x2 - 1; x += (int)shiftStep)
            {
                // Upis p_offset = x u IP registar
                uint32_t p_off = (uint32_t)x;
                tlm_write(VP_ADDR_IP_P_OFFSET_REG, &p_off, sizeof(uint32_t), pl, data, qk, offset);

                // Pokretanje IP-a
                uint8_t cfg = 0x02;
                tlm_write(VP_ADDR_IP_CFG_REG, &cfg, sizeof(uint8_t), pl, data, qk, offset);

                // Cekanje na zavrsetak
                wait(ip_done_event);

                // Citanje rezultata
                int32_t result = 0;
                tlm_read(VP_ADDR_IP_RESULT_REG, &result, sizeof(int32_t), pl, data, qk, offset);

                // Cuvanje koordinata ako je lice detektovano
                if(result > 0 && face_number < MAX_NUM_FACE - 1){
                    face_coordinate[face_number][0] = myRound((sc_ufixed<16,12,SC_RND,SC_SAT>)(x * factor));
                    face_coordinate[face_number][1] = myRound((sc_ufixed<16,12,SC_RND,SC_SAT>)(y_bias * factor));
                    face_coordinate[face_number][2] = winSize.width;
                    face_coordinate[face_number][3] = winSize.height;
                    face_number++;
                }
            }

        } // kraj y_bias petlje

    } // kraj factor petlje

    SC_REPORT_INFO("core1", "detectObjects petlja zavrsena.");

    /* groupRectangles - cisto SW post-procesiranje. Grupise preklapajuce pravougaonike detekcije. */
    SC_REPORT_INFO("core1", "Pocinjem groupRectangles...");
    groupRectangles(face_coordinate, face_number, minNeighbours, GROUP_EPS);

    printf("-- core1: Detektovano %d lica nakon grupiranja. --\r\n", (int)face_number);
	shared_face_count = (uint8_t)face_number;
    /* Notifikovanje core0 da je detekcija gotova */
    SC_REPORT_INFO("core1", "Detekcija gotova. Notifikujem core0.");
    detection_done.notify();
}

/*
/ Naziv funkcije: integralImages_fused
/ Opis: Racuna integralnu i kvadriranu integralnu sliku za prvih 25 redova downsampled slike koriscenjem nearest-neighbor interpolacije direktno iz in_img bafera.
*/
void tb_vp::integralImages_fused( sc_uint<8> in_img[IMAGE_HEIGHT][IMAGE_WIDTH], int* sumData, int* sqsumData, int width, int height, sc_ufixed<10,5,SC_RND,SC_SAT> factor, int y_bias){

    int x_ratio = (int)((IMAGE_WIDTH  << 16) / width) + 1;
    int y_ratio = (int)((IMAGE_HEIGHT << 16) / height) + 1;

    for(int i = 0; i < 25; i++){
        int src_i = (((i + y_bias) * y_ratio) >> 16);
        if(src_i >= IMAGE_HEIGHT) 
            src_i = IMAGE_HEIGHT - 1;

        int rat = 0;
        int s = 0;
        int sq = 0;

        for(int j = 0; j < width; j++){
            int src_j = (rat >> 16);
            if(src_j >= IMAGE_WIDTH) 
                src_j = IMAGE_WIDTH - 1;
            rat += x_ratio;

            int pix = (int)(sc_uint<8>)in_img[src_i][src_j];
            s += pix;
            sq += pix * pix;

            int above = (i > 0 ? sumData[(i-1)*width + j] : 0);
            int above_sq = (i > 0 ? sqsumData[(i-1)*width + j] : 0);

            sumData[i*width + j] = s + above;
            sqsumData[i*width + j] = sq + above_sq;
        }
    }
}

/*
/ Naziv funkcije: integralmages_lastrow_fused
/ Opis: Azurira integralne slike za novi y_bias: pomera bafer navise za jedan red i racuna novi poslednji red. Koristi nearest-neighbor interpolaciju iz in_img bafera.
*/
void tb_vp::integralmages_lastrow_fused( sc_uint<8> in_img[IMAGE_HEIGHT][IMAGE_WIDTH], int* sumData, int* sqsumData, int width, int sz_height, sc_ufixed<10,5,SC_RND,SC_SAT> factor, int y_bias){

    int x_ratio = (int)((IMAGE_WIDTH << 16) / width) + 1;
    int y_ratio = (int)((IMAGE_HEIGHT << 16) / sz_height) + 1;

    // Pomeranje bafera navise (shift)
    for(int y = 0; y < 24; y++){
        for(int x = 0; x < width; x++){
            sumData[y*width + x]   = sumData[(y+1)*width + x];
            sqsumData[y*width + x] = sqsumData[(y+1)*width + x];
        }
    }

    // Racunanje novog poslednjeg reda
    int src_i = (((24 + y_bias) * y_ratio) >> 16);
    if(src_i >= IMAGE_HEIGHT)
        src_i = IMAGE_HEIGHT - 1;

    int rat = 0;
    int s = 0;
    int sq  = 0;

    for(int x = 0; x < width; x++){
        int src_j = (rat >> 16);
        if(src_j >= IMAGE_WIDTH) 
            src_j = IMAGE_WIDTH - 1;
        rat += x_ratio;

        int pix = (int)(sc_uint<8>)in_img[src_i][src_j];
        s += pix;
        sq += pix * pix;

        sumData[24*width + x]   = s  + sumData[23*width + x];
        sqsumData[24*width + x] = sq + sqsumData[23*width + x];
    }
}

/*
/ Naziv funkcije: groupRectangles
/ Opis: Grupise preklapajuce pravougaonike detekcije. Ista implementacija kao u originalnom facedetect.cpp, premestena u testbench jer je cisto SW operacija.
*/
void tb_vp::groupRectangles(sc_uint<OUT_BW> face_coordinate[][4], sc_uint<8>& face_number, int groupThreshold, sc_ufixed<8,1,SC_RND,SC_SAT> eps){
    if(groupThreshold <= 0 || face_number == 0)
        return;

    int labels[MAX_NUM_FACE];
    int nclasses = partition(face_coordinate, (int)face_number, labels, eps);
    MyRect rrects[MAXLABELS];
    int rweights[MAXLABELS];
    
    int nlabels = (int)face_number;

    for(int i = 0; i < nclasses; i++){
        rrects[i].x = rrects[i].y = rrects[i].width = rrects[i].height = 0;
        rweights[i] = 0;
    }

    for(int i = 0; i < nlabels; i++){
        int cls = labels[i];
        rrects[cls].x += (int)face_coordinate[i][0];
        rrects[cls].y += (int)face_coordinate[i][1];
        rrects[cls].width += (int)face_coordinate[i][2];
        rrects[cls].height += (int)face_coordinate[i][3];
        rweights[cls]++;
    }

    for(int i = 0; i < nclasses; i++){
        MyRect r = rrects[i];
        sc_ufixed<10,1,SC_RND,SC_SAT> s = (sc_ufixed<10,1,SC_RND,SC_SAT>)1.0 / rweights[i];
        rrects[i].x = myRound((sc_ufixed<16,12,SC_RND,SC_SAT>)(r.x * s));
        rrects[i].y = myRound((sc_ufixed<16,12,SC_RND,SC_SAT>)(r.y * s));
        rrects[i].width = myRound((sc_ufixed<16,12,SC_RND,SC_SAT>)(r.width * s));
        rrects[i].height = myRound((sc_ufixed<16,12,SC_RND,SC_SAT>)(r.height * s));
    }

    face_number = 0;

    for(int i = 0; i < nclasses; i++){
        MyRect r1 = rrects[i];
        int n1 = rweights[i];

        if(n1 <= groupThreshold)
            continue;

        int j;
        for(j = 0; j < nclasses; j++){
            if(j == i) 
                continue;
            int n2 = rweights[j];
            if(n2 <= groupThreshold) 
                continue;

            MyRect r2 = rrects[j];
            int dx = myRound((sc_ufixed<16,12,SC_RND,SC_SAT>)(r2.width * eps));
            int dy = myRound((sc_ufixed<16,12,SC_RND,SC_SAT>)(r2.height * eps));

            if(i != j &&
               r1.x >= r2.x - dx &&
               r1.y >= r2.y - dy &&
               r1.x + r1.width  <= r2.x + r2.width  + dx &&
               r1.y + r1.height <= r2.y + r2.height + dy &&
               (n2 > ((3 > n1) ? 3 : n1) || n1 < 3))
                break;
        }

        if(j == nclasses && face_number < MAX_NUM_FACE - 1){
            face_coordinate[face_number][0] = r1.x;
            face_coordinate[face_number][1] = r1.y;
            face_coordinate[face_number][2] = r1.width;
            face_coordinate[face_number][3] = r1.height;
            face_number++;
        }
    }
}

/*
/ Naziv funkcije: partition
/ Opis: Union-find algoritam za grupisanje preklapajucih pravougaonika. Vraca broj klasa (lica) i popunjava niz labels.
*/
int tb_vp::partition( sc_uint<OUT_BW> face_coordinate[][4], int face_number, int* labels, sc_ufixed<8,1,SC_RND,SC_SAT> eps){
    int N = face_number;

    const int _PArent = 0;
    const int _RAnk = 1;

    int nodes[MAX_NUM_FACE][2];

    for(int i = 0; i < N; i++){
        nodes[i][_PArent] = -1;
        nodes[i][_RAnk] =  0;
    }

    for(int i = 0; i < N; i++){
        int root = i;
        while(nodes[root][_PArent] >= 0)
            root = nodes[root][_PArent];

        for(int j = 0; j < N; j++){
            if(i == j || !predicate(eps, face_coordinate[i], face_coordinate[j]))
                continue;

            int root2 = j;
            while(nodes[root2][_PArent] >= 0)
                root2 = nodes[root2][_PArent];

            if(root2 != root){
                int rank = nodes[root][_RAnk];
                int rank2 = nodes[root2][_RAnk];

                if(rank > rank2){
                    nodes[root2][_PArent] = root;
                }else{
                    nodes[root][_PArent] = root2;
                    nodes[root2][_RAnk] += (rank == rank2) ? 1 : 0;
                    root = root2;
                }

                int k = j, parent;
                while((parent = nodes[k][_PArent]) >= 0){
                    nodes[k][_PArent] = root;
                    k = parent;
                }

                k = i;
                while((parent = nodes[k][_PArent]) >= 0){
                    nodes[k][_PArent] = root;
                    k = parent;
                }
            }
        }
    }

    int nclasses = 0;
    for(int i = 0; i < N; i++){
        int root = i;
        while(nodes[root][_PArent] >= 0)
            root = nodes[root][_PArent];

        if(nodes[root][_RAnk] >= 0)
            nodes[root][_RAnk] = ~nclasses++;

        labels[i] = ~nodes[root][_RAnk];
    }

    return nclasses;
}

/*
/ Naziv funkcije: predicate
/ Opis: Poredi dva pravougaonika r1 i r2. Vraca 1 ako su dovoljno slicni (preklapaju se unutar eps granice).
*/
int tb_vp::predicate( sc_ufixed<8,1,SC_RND,SC_SAT> eps, sc_uint<OUT_BW> r1[4], sc_uint<OUT_BW> r2[4]){
    
    sc_ufixed<16,8,SC_RND,SC_SAT> delta = (sc_ufixed<16,8,SC_RND,SC_SAT>)0.5 * eps * (((r1[2] > r2[2]) ? r2[2] : r1[2]) + ((r1[3] > r2[3]) ? r2[3] : r1[3]));

    return myAbs((int)r1[0] - (int)r2[0]) <= delta &&
           myAbs((int)r1[1] - (int)r2[1]) <= delta &&
           myAbs((int)r1[0] + (int)r1[2] - (int)r2[0] - (int)r2[2]) <= delta &&
           myAbs((int)r1[1] + (int)r1[3] - (int)r2[1] - (int)r2[3]) <= delta;
}
