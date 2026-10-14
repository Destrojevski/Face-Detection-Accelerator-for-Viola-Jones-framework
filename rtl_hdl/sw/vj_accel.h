/*
 * vj_accel.h
 * Bare-metal driver za  Viola-Jones detektor lica.
 */

#ifndef VJ_ACCEL_H
#define VJ_ACCEL_H

#include <stdint.h>
/* 
 *AXI4-Lite registarska mapa (bajt ofseti u odnosu na kontrolni bazni registar)        
 */
#define VJ_REG_CTRL 0x00u
#define VJ_REG_X_START 0x04u
#define VJ_REG_WIDTH 0x08u /*zadrzan radi kompatibilnosti sa VP*/
#define VJ_REG_RESULT 0x0Cu
#define VJ_REG_X_LAST 0x10u
#define VJ_REG_X_STEP 0x14u
#define VJ_REG_HIT_COUNT 0x18u
#define VJ_REG_HIT_DATA 0x1Cu
#define VJ_REG_ROW_BASE 0x20u
#define VJ_REG_STATUS 0x24u
#define VJ_REG_HIT_ADDR 0x28u
#define VJ_CTRL_RESET (1u << 0)
#define VJ_CTRL_START (1u << 1)
#define VJ_CTRL_MODE_SWP (1u << 2)/*0=jedan prozor, 1 = row sweep*/
#define VJ_CTRL_DONE (1u << 4)/* write-1-to-clear*/
#define VJ_STATUS_BUSY (1u << 0)

/*raspored row banki, onako kako ga vidi AXI BRAM kontroler*                                                                  *
 *adresna rijec = banka * VJ_BANK_WORDS + kolona*/
#define VJ_BANK_WORDS 512u
#define VJ_N_INT_BANKS 25u
#define VJ_BANK_SQ0 25u/*kvadrirana integralna slika, red 0*/
#define VJ_BANK_SQ23 26u/*kvadrirana integralna slika, red 23*/

/*Algoritamske konstante (iste kao u vj_pkg.vhd) */
#define VJ_IMG_WIDTH 360
#define VJ_IMG_HEIGHT 240
#define VJ_WIN 24
#define VJ_INT_ROWS 25
#define VJ_MAX_FACES 128

typedef struct {
int x, y, w, h;
} vj_rect_t; //struktura pravougaonika

/*Driver*/
void vj_init(uintptr_t ctrl_base, uintptr_t bram_base);
void vj_reset(void);

/* Ubacivanje n rijeci u banku. Dozvoljeno samo kada jezgro ne radi nista : port A svake banke dijeljen je izmedju ovog upisa
 * i citanja jezgra, bez ikakvog arbitera. Upis u toku citanja kvari prozor koji se klasifikuje.*/
void vj_upload_row(unsigned bank, const int32_t *row, int n);
void vj_set_row_base(unsigned base);
void vj_set_width(unsigned width);

/*Mod A: klasifikacija jednog prozora.  Vraca 1 ako je pronadjeno lice, -i ako prozor otkaze
 *na fazi i.Preslikan iz VP modela, sluzi za mjerenje trajanja klasifikacije jednog prozora*/
int32_t vj_run_window(unsigned x);

/* Mod B: sweep vrijednosti x od x0 do x_last u koraku x_step, pracenje hitova.
 * Vraca broj detekcija.*/
unsigned vj_run_sweep(unsigned x0,unsigned x_last,unsigned x_step);

/*Citanje detekcije i iz hit bafera (valid je poslije vj_run_sweep).*/
unsigned vj_hit(unsigned i);

#endif /* VJ_ACCEL_H */
