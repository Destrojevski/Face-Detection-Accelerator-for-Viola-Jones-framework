/* vj_accel.c
Implementacija drajvera
 */

#include "vj_accel.h"

#ifdef VJ_HOST_SIM
/* ostavljena mogucnost za realizaciju softverskog modela */
void vj_sim_wr32(uintptr_t off,uint32_t v);
uint32_t vj_sim_rd32(uintptr_t off);
void vj_sim_bram_wr(uint32_t word_addr,uint32_t v);
#else
#include "xil_io.h"
#endif
static uintptr_t g_ctrl;
static uintptr_t g_bram;

static void vj_wr32(uintptr_t off,uint32_t v)
{
#ifdef VJ_HOST_SIM
    (void)g_ctrl;
    vj_sim_wr32(off,v);
#else
    Xil_Out32(g_ctrl + off,v);
#endif
}

static uint32_t vj_rd32(uintptr_t off)
{
#ifdef VJ_HOST_SIM
    return vj_sim_rd32(off);
#else
    return Xil_In32(g_ctrl + off);
#endif
}

static void vj_bram_wr(uint32_t word_addr, uint32_t v)
{
#ifdef VJ_HOST_SIM
    (void)g_bram;
    vj_sim_bram_wr(word_addr, v);
#else
    Xil_Out32(g_bram + (word_addr << 2), v);
#endif
}

/* inicijalizaciona funkcija akceleratora */

void vj_init(uintptr_t ctrl_base,uintptr_t bram_base)
{
    g_ctrl = ctrl_base;
    g_bram = bram_base;
    vj_reset();
}

void vj_reset(void)
{
    vj_wr32(VJ_REG_CTRL,VJ_CTRL_RESET);
    vj_wr32(VJ_REG_CTRL,VJ_CTRL_DONE);      /* clearovanje DONE signala u slucaju da je ostao aktivan */
    vj_wr32(VJ_REG_ROW_BASE,0);
    vj_wr32(VJ_REG_X_STEP,1);
}

void vj_upload_row(unsigned bank,const int32_t *row,int n)
{
    uint32_t base = bank*VJ_BANK_WORDS;
    for (int i = 0;i < n;i++)
        vj_bram_wr(base+(uint32_t)i,(uint32_t)row[i]);
}

void vj_set_row_base(unsigned base)
{
    vj_wr32(VJ_REG_ROW_BASE,base);
}

void vj_set_width(unsigned width)
{
    vj_wr32(VJ_REG_WIDTH,width);
}

/* Mod A: jedan prozor po pokretanju.*/
int32_t vj_run_window(unsigned x)
{
    vj_wr32(VJ_REG_X_START,x);
    vj_wr32(VJ_REG_X_LAST,x);
    vj_wr32(VJ_REG_CTRL,VJ_CTRL_START);          //MODE = 0 

    while ((vj_rd32(VJ_REG_CTRL) & VJ_CTRL_DONE) == 0)
        ;
    vj_wr32(VJ_REG_CTRL, VJ_CTRL_DONE);           /*write-1-to-clear*/
    return (int32_t)vj_rd32(VJ_REG_RESULT);
}

/*Mod B: jezgro samostalno mijenja x poziciju.*/
unsigned vj_run_sweep(unsigned x0,unsigned x_last,unsigned x_step)
{
    vj_wr32(VJ_REG_X_START,x0);
    vj_wr32(VJ_REG_X_LAST,x_last);
    vj_wr32(VJ_REG_X_STEP,x_step);
    vj_wr32(VJ_REG_CTRL, VJ_CTRL_START | VJ_CTRL_MODE_SWP);

    while ((vj_rd32(VJ_REG_CTRL) & VJ_CTRL_DONE) == 0)
        ;
    vj_wr32(VJ_REG_CTRL,VJ_CTRL_DONE);

    return vj_rd32(VJ_REG_HIT_COUNT);
}

unsigned vj_hit(unsigned i)
{
    vj_wr32(VJ_REG_HIT_ADDR,i);
    return vj_rd32(VJ_REG_HIT_DATA);
}
