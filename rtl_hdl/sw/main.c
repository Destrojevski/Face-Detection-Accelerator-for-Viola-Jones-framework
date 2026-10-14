/*
 *main.c
 *Bare-metal aplikacija za Viola-Jones detekciju lica za Zybo Z7-10.
 *Faze rada:
 *1.reset akceleratora
 *2.pokretanje detekcije na slici sacuvanoj u test_image.h
 *3.ispis detekcija i vremena na UART
 *Dodatno mjeri trajanje detekcije jednog prozora za mod A.
 *Napomena : potrebno dodati math.c biblioteku u linker kad se kreira novi projekat(m labela u Tool Settingsu)
 */

#include <stdio.h>
#include "xparameters.h"
#include "xil_printf.h"
#include "xil_cache.h"
#include "xtime_l.h"
#include "vj_accel.h"
#include "vj_detect.h"
#include "test_image.h"/*const uint8_t test_image[240*360];*/

/* Nazivi makroa za bazne adrese */
#ifndef VJ_CTRL_BASE
#define VJ_CTRL_BASE XPAR_VJ_CASCADE_0_BASEADDR
#endif
#ifndef VJ_BRAM_BASE
#define VJ_BRAM_BASE XPAR_ROW_BRAM_CTRL_S_AXI_BASEADDR
#endif

#define SCALE_FACTOR 1.2
#define SHIFT_STEP 1

/*COUNTS_PER_SECOND je Zynq globalni timer, takt PS dijela / 2.*/
static double ticks_to_us(XTime t)
{
return (double)t*1000000.0/(double)COUNTS_PER_SECOND;
}

int main(void)
{
	setvbuf(stdout,NULL,_IONBF,0);
    XTime t0,t1;
    vj_rect_t faces[VJ_MAX_FACES];
    xil_printf("\r\n");
    xil_printf("=====================================================\r\n");
    xil_printf(" Viola-Jones sistem za detekciju lica\r\n");
    xil_printf(" slika %dx%d, scaleFactor 1.2, shiftStep %d\r\n",VJ_IMG_WIDTH, VJ_IMG_HEIGHT, SHIFT_STEP);
    xil_printf("=====================================================\r\n");
    vj_init(VJ_CTRL_BASE, VJ_BRAM_BASE);

    /*
     *Trajanje detekcije jednog prozora, mod A.
     *Uporedivo je s virtuelnom platformom zbog istog nacina rada, vecina
     *prozora se odbija u fazi 0, pa raspodjela trajanja nije uniformna
     *pa je minimalno kasnjenje pozeljno uz prosjek.*/
    {
        static int32_t sum[VJ_INT_ROWS*VJ_IMG_WIDTH];
        static int32_t sqs[VJ_INT_ROWS*VJ_IMG_WIDTH];
        vj_integral_first(test_image,sum,sqs,VJ_IMG_WIDTH,VJ_IMG_HEIGHT);
        vj_set_width(VJ_IMG_WIDTH);
        vj_set_row_base(0);
        for(int r=0;r<VJ_INT_ROWS;r++)//redovi integralne slike
            vj_upload_row(r,&sum[r*VJ_IMG_WIDTH],VJ_IMG_WIDTH);
        vj_upload_row(VJ_BANK_SQ0,&sqs[0*VJ_IMG_WIDTH],VJ_IMG_WIDTH);//dva coska kvadrirane integralne slike, relevantna za detekciju
        vj_upload_row(VJ_BANK_SQ23,&sqs[23*VJ_IMG_WIDTH],VJ_IMG_WIDTH);
        const int N=200;
        XTime_GetTime(&t0);
        for(int i=0;i<N;i++)
            (void)vj_run_window(i);
        XTime_GetTime(&t1);
        double us=ticks_to_us(t1-t0)/N;
        xil_printf("\r\n=Mod A, detekcija za jedan prozor  =\r\n");
        printf("   prosjek po prozoru : %.3f us (sa uracunatim handshakeom)\r\n", us);
    }
    /*
     *Kompletna detekcija, mod B.*/
    xil_printf("\r\n= Mod B, kompletna detekcija =\r\n");
    XTime_GetTime(&t0);
    int n=vj_detect(test_image,SCALE_FACTOR,SHIFT_STEP,faces,VJ_MAX_FACES);
    XTime_GetTime(&t1);
    printf("   proteklo : %.1f ms\r\n",ticks_to_us(t1-t0)/1000.0);
    xil_printf("   broj lica   : %d\r\n\r\n",n);
    for(int i=0;i< n;i++)
        xil_printf("   lice %2d :  x=%3d  y=%3d  w=%3d  h=%3d\r\n",i,faces[i].x,faces[i].y,faces[i].w,faces[i].h);
    xil_printf("\r\ndone.\r\n");
    return 0;
}
