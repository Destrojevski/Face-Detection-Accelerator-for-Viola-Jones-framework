/*
 * vj_driver.c
  Linux platformski drajver za Viola-Jones kaskadni detektor lica.
  Drajver upravlja sa dva uredjaja iz stabla uredjaja:
    compatible = "vj_cascade" AXI4-Lite kontrolni registri  @ 0x4000_0000
    compatible = "vj_row_bram" AXI BRAM kontroler (row upload) @ 0x4200_0000
 i eksponira TRI device fajla:
    /dev/vj_ctrl   minor 0   tekstualna konfiguracija + start + cekanje na kraj
    /dev/vj_rows   minor 1   binarni upload redova integralne slike (pozicioni)
    /dev/vj_hits   minor 2   citanje liste detekcija nakon sweep-a
  Kraj obrade se detektuje PREKIDOM (vj_0/irq - IRQ_F2P[0]), ne pollingom.
 */

#include <linux/kernel.h>
#include <linux/string.h>
#include <linux/module.h>
#include <linux/init.h>
#include <linux/version.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/types.h>
#include <linux/uaccess.h>
#include <linux/errno.h>
#include <linux/slab.h>
#include <linux/mutex.h>
#include <linux/wait.h>
#include <linux/sched.h>
#include <linux/io.h>
#include <linux/ioport.h>
#include <linux/interrupt.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/of_device.h>

MODULE_AUTHOR("EOS");
MODULE_DESCRIPTION("Driver for Viola-Jones cascade face detector IP");
MODULE_LICENSE("Dual BSD/GPL");
MODULE_ALIAS("custom: vj_cascade driver");

#define DRIVER_NAME     "vj_driver"
#define CLASS_NAME      "vj_class"
#define NUM_DEVICES     3

/* Registarska mapa (bajt offseti u odnosu na baznu adresu vj_0)
 Preuzeto direktno iz zaglavlja vj_cascade_v1_0_S00_AXI.vhd */
#define VJ_CTRL         0x00    /* RW */
#define VJ_X_START      0x04    /* RW */
#define VJ_WIDTH        0x08    /* RW */
#define VJ_RESULT       0x0C    /* RO */
#define VJ_X_LAST       0x10    /* RW */
#define VJ_X_STEP       0x14    /* RW */
#define VJ_HIT_COUNT    0x18    /* RO */
#define VJ_HIT_DATA     0x1C    /* RO */
#define VJ_ROW_BASE     0x20    /* RW */
#define VJ_STATUS       0x24    /* RO, b0 = BUSY */
#define VJ_HIT_ADDR     0x28    /* RW */

#define CTRL_RESET      (1u << 0)   /* self-clearing */
#define CTRL_START      (1u << 1)   /* self-clearing */
#define CTRL_MODE_SWEEP (1u << 2)   /* 0 = jedan prozor, 1 = x sweep */
#define CTRL_DONE       (1u << 4)   /* postavlja HW, write-1-to-clear */

#define STATUS_BUSY     (1u << 0)

/*Geometrija row-bank memorije (preuzeta iz vj_pkg.vhd)
 Adresna rijec koju vidi BRAM_PORTA je bram_addr_a(15 downto 2):
 biti 13..9 = indeks banke (0..26)
 biti  8..0 = kolona (0..511)
 Dakle bajt offset = (bank * 512 + col) * 4*/
#define BANK_DEPTH      512
#define N_BANKS         27      /* 0..24 integralna, 25 = kv. red 0, 26 = kv. red 23 */
#define ROW_BRAM_WORDS  (N_BANKS * BANK_DEPTH)
#define ROW_BRAM_BYTES  (ROW_BRAM_WORDS * 4)

#define HIT_DEPTH       512     /* maksimalan broj detekcija po sweepu */

#define CMD_BUF_SIZE    256
#define STAT_BUF_SIZE   128
#define HITS_BUF_SIZE   (HIT_DEPTH * 8)     /* "%u\n" po detekciji, sa rezervom */
#define ROW_CHUNK       4096                /* bajtova po copy_from_user prolazu */

/* Timeout za cekanje na kraj obrade. Jedan sweep najsire skale je reda
 * milisekundi; 5 sekundi je konzervativna granica koja hvata i situaciju
 * u kojoj bitstream nije ucitan pa se prekid nikad ne dogodi */
#define VJ_DONE_TIMEOUT_MS  5000

/*Strukture*/
struct vj_region
{
	unsigned long        mem_start;
	unsigned long        mem_end;
	void __iomem        *base_addr;
};

static struct vj_region *vj_core;   /* AXI4-Lite registri */
static struct vj_region *vj_rows;   /* BRAM prozor za redove */

static int vj_irq = -1;

static dev_t          vj_dev_id;
static struct cdev   *vj_cdev;
static struct class  *vj_class;

/*Sinhronizacija*/
static DEFINE_MUTEX(vj_lock);               /* serijalizuje pristup hardveru */
static DECLARE_WAIT_QUEUE_HEAD(vj_wq);      /* cekanje na DONE prekid */

static volatile int vj_done_flag;           /* postavlja ISR */
static int          vj_run_pending;         /* start poslat, DONE jos nije stigao */

/* Vrijednosti koje ISR uzima u trenutku zavrsetka obrade */
static u32 vj_last_result;
static u32 vj_last_hits;

/* Baferi za tekstualne odgovore */
static char *vj_hits_buf;
static size_t vj_hits_len;

/* Pomocne funkcije za pristup registrima */
static inline void reg_write(u32 off, u32 val)
{
	iowrite32(val, vj_core->base_addr + off);
}

static inline u32 reg_read(u32 off)
{
	return ioread32(vj_core->base_addr + off);
}

/* Prototipovi */
static int  vj_probe(struct platform_device *pdev);
static int  vj_remove(struct platform_device *pdev);
static int  vj_open(struct inode *i, struct file *f);
static int  vj_close(struct inode *i, struct file *f);
static ssize_t vj_read(struct file *f, char __user *buf, size_t len, loff_t *off);
static ssize_t vj_write(struct file *f, const char __user *buf, size_t len, loff_t *off);
static loff_t  vj_llseek(struct file *f, loff_t off, int whence);

static struct file_operations vj_fops =
{
	.owner   = THIS_MODULE,
	.open    = vj_open,
	.release = vj_close,
	.read    = vj_read,
	.write   = vj_write,
	.llseek  = vj_llseek,
};

/*Tabela uparivanja sa device treeom
  Navedena su dva stringa po uredjaju:
    "vj_cascade" / "vj_row_bram"
        kratki nazivi koji se dobijaju redefinisanjem compatible polja
        kroz system-user.dtsi;
 
    "xlnx,vj-cascade-1.0" / "xlnx,axi-bram-ctrl-4.1"
        nazivi koje PetaLinux automatski generise iz .xsa fajla.
 
  Drajver se uparuje u oba slucaja, pa redefinisanje u system-user.dtsi
  postaje opciono umjesto obavezno. Automatski generisane nazive treba
  provjeriti u pl.dtsi i ako je potrebno ispraviti stringove ispod*/
static struct of_device_id vj_of_match[] =
{
	{ .compatible = "vj_cascade",           },  /*redefinisano u dtsi*/
	{ .compatible = "xlnx,vj-cascade-1.0",  },  /*automatski generisano*/
	{ .compatible = "vj_row_bram",          },  /*redefinisano u dtsi*/
	{ .compatible = "xlnx,axi-bram-ctrl-4.1", }, /*automatski generisano*/
	{ /* end of list */ },
};
MODULE_DEVICE_TABLE(of, vj_of_match);

static struct platform_driver vj_platform_driver =
{
	.driver = {
		.name           = DRIVER_NAME,
		.owner          = THIS_MODULE,
		.of_match_table = vj_of_match,
	},
	.probe  = vj_probe,
	.remove = vj_remove,
};

/* Prekidna rutina
irq je u RTL-u vezan direktno na reg_done i aktivan je na nivo, pa se
mora obrisati upisom jedinice u CTRL bit4 prije izlaska iz rutine,
inace bi se prekid odmah ponovo aktivirao
Upis u CTRL bezuslovno prepisuje i reg_mode (bit2), jer u
vj_cascade_v1_0_S00_AXI.vhd taj registar nema enable. Zato se mode
bit uvijek salje ponovo pri sljedecem START-u.*/
static irqreturn_t vj_isr(int irq, void *dev_id)
{
	u32 ctrl = reg_read(VJ_CTRL);

	if (!(ctrl & CTRL_DONE))
		return IRQ_NONE;    /*nije nas prekid*/

	/* Rezultate uzimamo dok su registri jos validni */
	vj_last_result = reg_read(VJ_RESULT);
	vj_last_hits   = reg_read(VJ_HIT_COUNT);

	reg_write(VJ_CTRL, CTRL_DONE);      /* write-1-to-clear, spusta irq */

	vj_done_flag   = 1;
	vj_run_pending = 0;
	wake_up_interruptible(&vj_wq);

	return IRQ_HANDLED;
}

/*Probe / Remove
  Za razliku od uobicajenog probe_counter pristupa, ovdje se uredjaj
  prepoznaje po compatible stringu. Time redoslijed kojim kernel
  prolazi kroz stablo uredjaja prestaje da bude bitan*/
  
/*Prepoznavanje uredjaja. Provjeravaju se oba moguca compatible stringa,
  pa se drajver ponasa isto bez obzira na to da li je system-user.dtsi
  redefinisao polje ili je ostao automatski generisani naziv*/
static int vj_is_core(struct platform_device *pdev)
{
	return of_device_is_compatible(pdev->dev.of_node, "vj_cascade") ||
	       of_device_is_compatible(pdev->dev.of_node, "xlnx,vj-cascade-1.0");
}

static int vj_is_rows(struct platform_device *pdev)
{
	return of_device_is_compatible(pdev->dev.of_node, "vj_row_bram") ||
	       of_device_is_compatible(pdev->dev.of_node, "xlnx,axi-bram-ctrl-4.1");
}

static int vj_map_region(struct platform_device *pdev, struct vj_region **out)
{
	struct resource *r_mem;
	struct vj_region *reg;

	r_mem = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!r_mem)
	{
		printk(KERN_ALERT "vj_driver: nema MEM resursa u stablu uredjaja\n");
		return -ENODEV;
	}

	reg = kmalloc(sizeof(*reg), GFP_KERNEL);
	if (!reg)
		return -ENOMEM;

	reg->mem_start = r_mem->start;
	reg->mem_end   = r_mem->end;

	if (!request_mem_region(reg->mem_start,
	                        reg->mem_end - reg->mem_start + 1, DRIVER_NAME))
	{
		printk(KERN_ALERT "vj_driver: zauzet memorijski region 0x%lx\n",
		       reg->mem_start);
		kfree(reg);
		return -EBUSY;
	}

	reg->base_addr = ioremap(reg->mem_start,
	                         reg->mem_end - reg->mem_start + 1);
	if (!reg->base_addr)
	{
		printk(KERN_ALERT "vj_driver: ioremap neuspjesan za 0x%lx\n",
		       reg->mem_start);
		release_mem_region(reg->mem_start,
		                   reg->mem_end - reg->mem_start + 1);
		kfree(reg);
		return -EIO;
	}

	*out = reg;
	return 0;
}

static void vj_unmap_region(struct vj_region **p)
{
	struct vj_region *reg = *p;

	if (!reg)
		return;

	iounmap(reg->base_addr);
	release_mem_region(reg->mem_start, reg->mem_end - reg->mem_start + 1);
	kfree(reg);
	*p = NULL;
}

static int vj_probe(struct platform_device *pdev)
{
	int rc;

	if (vj_is_core(pdev))
	{

		rc = vj_map_region(pdev, &vj_core);
		if (rc)
			return rc;

		/* Prekid je deklarisan samo na nodeu kontrolnih registara */
		vj_irq = platform_get_irq(pdev, 0);
		if (vj_irq < 0)
		{
			printk(KERN_ERR "vj_driver: nema IRQ resursa\n");
			vj_unmap_region(&vj_core);
			return vj_irq;
		}

		rc = request_irq(vj_irq, vj_isr, 0, DRIVER_NAME, NULL);
		if (rc)
		{
			printk(KERN_ERR "vj_driver: request_irq(%d) neuspjesan\n", vj_irq);
			vj_irq = -1;
			vj_unmap_region(&vj_core);
			return rc;
		}

		/* Jezgro prelazi u poznato stanje i brise se eventualno zaostalo DONE */
		reg_write(VJ_CTRL, CTRL_RESET);
		reg_write(VJ_CTRL, CTRL_DONE);

		printk(KERN_INFO "vj_driver: vj_cascade registrovan @0x%08lx, IRQ %d\n",
		       vj_core->mem_start, vj_irq);
		return 0;
	}

	if (vj_is_rows(pdev))
	{

		rc = vj_map_region(pdev, &vj_rows);
		if (rc)
			return rc;

		printk(KERN_INFO "vj_driver: vj_row_bram registrovan @0x%08lx (%u bajtova u upotrebi)\n",
		       vj_rows->mem_start, (unsigned)ROW_BRAM_BYTES);
		return 0;
	}

	printk(KERN_ALERT "vj_driver: nepoznat compatible string\n");
	return -ENODEV;
}

static int vj_remove(struct platform_device *pdev)
{
	if (vj_is_core(pdev))
	{
		if (vj_core)
			reg_write(VJ_CTRL, CTRL_RESET);
		if (vj_irq >= 0)
		{
			free_irq(vj_irq, NULL);
			vj_irq = -1;
		}
		vj_unmap_region(&vj_core);
		printk(KERN_INFO "vj_driver: vj_cascade uklonjen\n");
	}
	else if (vj_is_rows(pdev))
	{
		vj_unmap_region(&vj_rows);
		printk(KERN_INFO "vj_driver: vj_row_bram uklonjen\n");
	}
	return 0;
}

/* open / close / llseek*/
static int vj_open(struct inode *i, struct file *f)
{
	return 0;
}

static int vj_close(struct inode *i, struct file *f)
{
	return 0;
}

/*llseek je potreban da bi aplikacija mogla pozicionirati upis u
 row BRAM (jedan pwrite po redu umjesto jednog syscalla po rijeci)*/
static loff_t vj_llseek(struct file *f, loff_t off, int whence)
{
	int minor = iminor(f->f_inode);
	loff_t newpos;
	loff_t maxpos = (minor == 1) ? ROW_BRAM_BYTES : STAT_BUF_SIZE;

	switch (whence)
	{
	case SEEK_SET:
		newpos = off;
		break;
	case SEEK_CUR:
		newpos = f->f_pos + off;
		break;
	case SEEK_END:
		newpos = maxpos + off;
		break;
	default:
		return -EINVAL;
	}

	if (newpos < 0 || newpos > maxpos)
		return -EINVAL;

	f->f_pos = newpos;
	return newpos;
}

/* /dev/vj_ctrl  --  write
  Prihvata razmakom razdvojene tokene, tako da se cijelo podesavanje i
  pokretanje jednog sweepa salje jednim syscallom:
    echo "row_base=0 x_start=0 x_last=336 x_step=1 sweep" > /dev/vj_ctrl
 
  Podrzani tokeni:
    reset            softverski reset jezgra (CTRL bit0)
    clear_done       rucno brisanje DONE flaga
    x_start=N  x_last=N  x_step=N  width=N  row_base=N  hit_addr=N
    start            pokretanje u modu A (jedan prozor)
    sweep            pokretanje u modu B (x sweep)*/
static int vj_exec_token(const char *tok)
{
	unsigned int val;

	if (!strcmp(tok, "reset"))
	{
		reg_write(VJ_CTRL, CTRL_RESET);
		vj_done_flag = 0;
		vj_run_pending = 0;
		return 0;
	}
	if (!strcmp(tok, "clear_done"))
	{
		reg_write(VJ_CTRL, CTRL_DONE);
		vj_done_flag = 0;
		return 0;
	}
	if (!strcmp(tok, "start") || !strcmp(tok, "sweep"))
	{
		u32 ctrl = CTRL_START;

		if (reg_read(VJ_STATUS) & STATUS_BUSY)
		{
			printk(KERN_WARNING "vj_driver: start odbijen, jezgro je zauzeto\n");
			return -EBUSY;
		}
		if (!strcmp(tok, "sweep"))
			ctrl |= CTRL_MODE_SWEEP;

		vj_done_flag   = 0;
		vj_run_pending = 1;
		/*Mode bit se salje zajedno sa START-om jer ga svaki prethodni upis u CTRL (ukljucujuci brisanje DONE u ISR-u) obrise*/
		reg_write(VJ_CTRL, ctrl);
		return 0;
	}

	if (sscanf(tok, "x_start=%u", &val) == 1)
	{
		reg_write(VJ_X_START, val);
		return 0;
	}
	if (sscanf(tok, "x_last=%u", &val) == 1)
	{
		reg_write(VJ_X_LAST, val);
		return 0;
	}
	if (sscanf(tok, "x_step=%u", &val) == 1)
	{
		if (val == 0)
		{
			printk(KERN_WARNING "vj_driver: x_step=0 bi zaglavio sweep\n");
			return -EINVAL;
		}
		reg_write(VJ_X_STEP, val);
		return 0;
	}
	if (sscanf(tok, "width=%u", &val) == 1)
	{
		reg_write(VJ_WIDTH, val);
		return 0;
	}
	if (sscanf(tok, "row_base=%u", &val) == 1)
	{
		if (val > 24) return -EINVAL;
		reg_write(VJ_ROW_BASE, val);
		return 0;
	}
	if (sscanf(tok, "hit_addr=%u", &val) == 1)
	{
		if (val >= HIT_DEPTH) return -EINVAL;
		reg_write(VJ_HIT_ADDR, val);
		return 0;
	}

	printk(KERN_WARNING "vj_driver: nepoznata komanda '%s'\n", tok);
	return -EINVAL;
}

static ssize_t vj_ctrl_write(const char __user *buf, size_t len)
{
	char *kbuf, *p, *tok;
	int rc = 0;

	if (len == 0 || len >= CMD_BUF_SIZE)
		return -EINVAL;

	kbuf = kmalloc(len + 1, GFP_KERNEL);
	if (!kbuf)
		return -ENOMEM;

	if (copy_from_user(kbuf, buf, len))
	{
		kfree(kbuf);
		return -EFAULT;
	}
	kbuf[len] = '\0';

	p = kbuf;
	while ((tok = strsep(&p, " \t\n\r")) != NULL)
	{
		if (*tok == '\0')
			continue;                 /*preskoci visestruke separatore*/
		rc = vj_exec_token(tok);
		if (rc)
			break;
	}

	kfree(kbuf);
	return rc ? rc : (ssize_t)len;
}

/* /dev/vj_ctrl  --  read
 
  Ako je obrada u toku, citanje blokira dok ne stigne DONE prekid.
  Ako nije, odmah vraca trenutno stanje. Time aplikacija ceka kraj
  obrade bez ijedne polling petlje
 
 EOF se signalizira preko *off, a ne preko globalnog end_read flaga kako bi se izbjegla
 greska u kojoj citanje jednog uredjaja odmah vrati EOF na drugom*/
static ssize_t vj_ctrl_read(struct file *f, char __user *buf,
                            size_t len, loff_t *off)
{
	char kbuf[STAT_BUF_SIZE];
	int n, rc;
	u32 status, ctrl;

	if (*off > 0)
		return 0;   /* EOF */

	if (vj_run_pending)
	{
		rc = wait_event_interruptible_timeout(
		         vj_wq, vj_done_flag != 0,
		         msecs_to_jiffies(VJ_DONE_TIMEOUT_MS));

		if (rc == 0)
		{
			printk(KERN_ERR "vj_driver: timeout, DONE prekid nije stigao "
			       "(da li je bitstream ucitan?)\n");
			vj_run_pending = 0;
			return -ETIMEDOUT;
		}
		if (rc < 0)
			return -ERESTARTSYS;    /* prekinuto signalom */
	}

	status = reg_read(VJ_STATUS);
	ctrl   = reg_read(VJ_CTRL);

	n = scnprintf(kbuf, sizeof(kbuf),
	              "busy=%u done=%u result=%d hits=%u\n",
	              status & STATUS_BUSY,
	              vj_done_flag,
	              (int)vj_last_result,
	              vj_last_hits);

	if (len < (size_t)n)
		return -EINVAL;
	if (copy_to_user(buf, kbuf, n))
		return -EFAULT;

	*off += n;
	return n;
}

/* /dev/vj_rows  --  write
 
  Binarni, pozicioni upis gdje je pozicija u fajlu bajt offset u row
  BRAM prozoru. Aplikacija salje jedan red odjednom:
 
    off = (bank * 512 + col) * 4
    pwrite(fd, row_words, n * 4, off);
 
  Ovim je upload cijele slike reda 27 syscalla
 
  Ogranicenje iz RTL-a je da port A row banaka dijele ovaj write path i
  col0 read jezgra, pod pretpostavkom da se nikad ne preklapaju. Zato
  upis dok je BUSY postavljen mora biti odbijen*/
static ssize_t vj_rows_write(const char __user *buf, size_t len, loff_t *off)
{
	u32 *kbuf;
	size_t done = 0;

	if (!vj_rows)
		return -ENODEV;

	if ((len & 3) || (*off & 3))
	{
		printk(KERN_WARNING "vj_driver: duzina i offset moraju biti umnozak 4\n");
		return -EINVAL;
	}
	if (*off + len > ROW_BRAM_BYTES)
		return -EINVAL;
	if (len == 0)
		return 0;

	if (reg_read(VJ_STATUS) & STATUS_BUSY)
	{
		printk(KERN_WARNING "vj_driver: upis redova odbijen, jezgro je zauzeto\n");
		return -EBUSY;
	}

	kbuf = kmalloc(ROW_CHUNK, GFP_KERNEL);
	if (!kbuf)
		return -ENOMEM;

	while (done < len)
	{
		size_t chunk = min((size_t)ROW_CHUNK, len - done);
		size_t i;

		if (copy_from_user(kbuf, buf + done, chunk))
		{
			kfree(kbuf);
			return -EFAULT;
		}
		for (i = 0; i < chunk / 4; i++)
			iowrite32(kbuf[i], vj_rows->base_addr + *off + done + i * 4);

		done += chunk;
	}

	kfree(kbuf);
	*off += len;
	return len;
}

/* /dev/vj_hits  --  read
 
 Pri prvom citanju (off == 0) drajver prolazi kroz hit buffer preko
 HIT_ADDR/HIT_DATA para i formira tekstualnu listu x koordinata,
 jednu po liniji. Naredna citanja samo iscitavaju taj bafer*/
static ssize_t vj_hits_read(struct file *f, char __user *buf,
                            size_t len, loff_t *off)
{
	size_t remaining;

	if (*off == 0)
	{
		u32 count, i;

		if (reg_read(VJ_STATUS) & STATUS_BUSY)
			return -EBUSY;

		count = reg_read(VJ_HIT_COUNT);
		if (count > HIT_DEPTH)
		{
			printk(KERN_WARNING "vj_driver: hit_count=%u van opsega\n", count);
			count = HIT_DEPTH;
		}

		vj_hits_len = 0;
		for (i = 0; i < count; i++)
		{
			u32 x;

			reg_write(VJ_HIT_ADDR, i);
			x = reg_read(VJ_HIT_DATA);
			vj_hits_len += scnprintf(vj_hits_buf + vj_hits_len,
			                         HITS_BUF_SIZE - vj_hits_len,
			                         "%u\n", x);
		}
	}

	if (*off >= (loff_t)vj_hits_len)
		return 0;   /* EOF */

	remaining = vj_hits_len - *off;
	if (len > remaining)
		len = remaining;

	if (copy_to_user(buf, vj_hits_buf + *off, len))
		return -EFAULT;

	*off += len;
	return len;
}

/* Dispecer po minor broju */
static ssize_t vj_read(struct file *f, char __user *buf, size_t len, loff_t *off)
{
	int minor = iminor(f->f_inode);
	ssize_t rc;

	if (!vj_core)
		return -ENODEV;

	if (mutex_lock_interruptible(&vj_lock))
		return -ERESTARTSYS;

	switch (minor)
	{
	case 0:
		rc = vj_ctrl_read(f, buf, len, off);
		break;
	case 1:
		/*BRAM_PORTA je sa strane magistrale write-only:
		 bram_rddata_a <= (others => '0') u RTL-u */
		printk(KERN_WARNING "vj_driver: row BRAM se ne moze citati\n");
		rc = -EIO;
		break;
	case 2:
		rc = vj_hits_read(f, buf, len, off);
		break;
	default:
		rc = -EINVAL;
	}

	mutex_unlock(&vj_lock);
	return rc;
}

static ssize_t vj_write(struct file *f, const char __user *buf,
                        size_t len, loff_t *off)
{
	int minor = iminor(f->f_inode);
	ssize_t rc;

	if (!vj_core)
		return -ENODEV;

	if (mutex_lock_interruptible(&vj_lock))
		return -ERESTARTSYS;

	switch (minor)
	{
	case 0:
		rc = vj_ctrl_write(buf, len);
		break;
	case 1:
		rc = vj_rows_write(buf, len, off);
		break;
	case 2:
		rc = -EPERM;    /*hit buffer je read-only*/
		break;
	default:
		rc = -EINVAL;
	}

	mutex_unlock(&vj_lock);
	return rc;
}

/*Init / Exit*/
static const char *vj_dev_names[NUM_DEVICES] =
{
	"vj_ctrl", "vj_rows", "vj_hits"
};

static int __init vj_init(void)
{
	int rc, i;

	printk(KERN_INFO "vj_driver: ucitavanje modula\n");

	vj_hits_buf = kmalloc(HITS_BUF_SIZE, GFP_KERNEL);
	if (!vj_hits_buf)
		return -ENOMEM;

	rc = alloc_chrdev_region(&vj_dev_id, 0, NUM_DEVICES, DRIVER_NAME);
	if (rc)
	{
		printk(KERN_ERR "vj_driver: alloc_chrdev_region neuspjesan\n");
		goto fail_kmalloc;
	}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0)
	vj_class = class_create(CLASS_NAME);
#else
	vj_class = class_create(THIS_MODULE, CLASS_NAME);
#endif
	if (IS_ERR(vj_class))
	{
		rc = PTR_ERR(vj_class);
		goto fail_chrdev;
	}

	for (i = 0; i < NUM_DEVICES; i++)
	{
		if (device_create(vj_class, NULL, MKDEV(MAJOR(vj_dev_id), i),
		                  NULL, vj_dev_names[i]) == NULL)
		{
			printk(KERN_ERR "vj_driver: device_create(%s) neuspjesan\n",
			       vj_dev_names[i]);
			rc = -EIO;
			goto fail_device;
		}
	}

	vj_cdev = cdev_alloc();
	if (!vj_cdev)
	{
		rc = -ENOMEM;
		goto fail_device;
	}
	vj_cdev->ops   = &vj_fops;
	vj_cdev->owner = THIS_MODULE;

	rc = cdev_add(vj_cdev, vj_dev_id, NUM_DEVICES);
	if (rc)
	{
		kfree(vj_cdev);         /*cdev_alloc uspio, cdev_add nije*/
		vj_cdev = NULL;
		goto fail_device;
	}

	rc = platform_driver_register(&vj_platform_driver);
	if (rc)
	{
		printk(KERN_ERR "vj_driver: platform_driver_register neuspjesan\n");
		cdev_del(vj_cdev);      /*cdev_del oslobadja i strukturu*/
		vj_cdev = NULL;
		goto fail_device;
	}

	printk(KERN_INFO "vj_driver: inicijalizovan (major %d)\n", MAJOR(vj_dev_id));
	return 0;

fail_device:
	while (--i >= 0)
		device_destroy(vj_class, MKDEV(MAJOR(vj_dev_id), i));
	class_destroy(vj_class);
fail_chrdev:
	unregister_chrdev_region(vj_dev_id, NUM_DEVICES);
fail_kmalloc:
	kfree(vj_hits_buf);
	return rc;
}

static void __exit vj_exit(void)
{
	int i;

	/* Redoslijed ciscenja je obrnut od inicijalizacije */
	platform_driver_unregister(&vj_platform_driver);

	if (vj_cdev)
		cdev_del(vj_cdev);

	for (i = 0; i < NUM_DEVICES; i++)
		device_destroy(vj_class, MKDEV(MAJOR(vj_dev_id), i));

	class_destroy(vj_class);
	unregister_chrdev_region(vj_dev_id, NUM_DEVICES);
	kfree(vj_hits_buf);

	printk(KERN_INFO "vj_driver: modul uklonjen\n");
}

module_init(vj_init);
module_exit(vj_exit);
