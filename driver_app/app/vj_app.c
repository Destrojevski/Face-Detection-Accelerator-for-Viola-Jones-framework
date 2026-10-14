/*
 * vj_app.c
 *
 * Korisnicka aplikacija za Viola-Jones detektor lica na Zybo Z7-10.
 * Algoritamski dio je preslikan iz Vitis baremetal aplikacije
 * (vj_detect.c).
 *
 * Razlika u odnosu na baremetal verziju je iskljucivo u pristupu hardveru:
 * umjesto Xil_Out32/Xil_In32 koriste se device fajlovi kernel drajvera, a
 * umjesto pollinga se ceka na prekid.
 *   /dev/vj_ctrl   konfiguracija; citanje blokira do DONE prekida
 *   /dev/vj_rows   binarni pozicioni upis redova u row BRAM
 *   /dev/vj_hits   lista x koordinata detekcija nakon sweep-a
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>
#include <math.h>

/*Konstante iz vj_pkg.vhd / vj_accel.h*/
#define WIN_SIZE        24
#define INT_ROWS        25
#define BANK_DEPTH      512
#define SQ0_BANK        25
#define SQ23_BANK       26
#define MAX_IMG_WIDTH   360
#define HIT_DEPTH       512
#define MAX_FACES       128

#define DEV_CTRL        "/dev/vj_ctrl"
#define DEV_ROWS        "/dev/vj_rows"
#define DEV_HITS        "/dev/vj_hits"

/*Podrazumijevani parametri, isti kao u mainu baremetal aplikacije*/
#define DEF_SCALE_FACTOR 1.2
#define DEF_SHIFT_STEP   1
#define DEF_GROUP_THRESH 1
#define DEF_GROUP_EPS    0.4

typedef struct
{
	int w, h;
	uint8_t *pix;
} image_t;
typedef struct
{
	int x, y, w, h;
} rect_t;
typedef struct
{
	int fd_ctrl, fd_rows, fd_hits;
} vj_dev_t;

static long stat_sweeps, stat_row_writes, stat_raw_hits;

/*Ucitavanje slike (PGM P2/P5 ili "w h" + vrijednosti)*/
static int pgm_skip_ws(FILE *f)
{
	int c;
	for (;;)
	{
		c = fgetc(f);
		if (c == '#')
		{
			while (c != '\n' && c != EOF) c = fgetc(f);
		}
		else if (c == ' ' || c == '\t' || c == '\n' || c == '\r') continue;
		else return c;
	}
}

static int pgm_read_int(FILE *f, int *out)
{
	int c = pgm_skip_ws(f), v = 0, any = 0;
	while (c >= '0' && c <= '9')
	{
		v = v * 10 + (c - '0');
		any = 1;
		c = fgetc(f);
	}
	if (!any) return -1;
	*out = v;
	return 0;
}

static int image_load(const char *path, image_t *img)
{
	FILE *f = fopen(path, "rb");
	int magic, fmt, w, h, maxval = 255, i, n;

	if (!f)
	{
		fprintf(stderr, "[APP] ne mogu otvoriti '%s': %s\n", path, strerror(errno));
		return -1;
	}

	magic = fgetc(f);
	if (magic == 'P')
	{
		fmt = fgetc(f);
		if (fmt != '2' && fmt != '5')
		{
			fprintf(stderr, "[APP] podrzani su samo PGM P2 i P5\n");
			fclose(f);
			return -1;
		}
		if (pgm_read_int(f, &w) || pgm_read_int(f, &h) || pgm_read_int(f, &maxval))
		{
			fprintf(stderr, "[APP] neispravno PGM zaglavlje\n");
			fclose(f);
			return -1;
		}
	}
	else
	{
		ungetc(magic, f);
		fmt = '2';
		if (pgm_read_int(f, &w) || pgm_read_int(f, &h))
		{
			fprintf(stderr, "[APP] neispravno zaglavlje\n");
			fclose(f);
			return -1;
		}
	}
	if (w <= 0 || h <= 0 || maxval <= 0 || maxval > 255)
	{
		fprintf(stderr, "[APP] nepodrzane dimenzije ili maxval\n");
		fclose(f);
		return -1;
	}

	n = w * h;
	img->w = w;
	img->h = h;
	img->pix = malloc(n);
	if (!img->pix)
	{
		fclose(f);
		return -1;
	}

	if (fmt == '5')
	{
		if (fread(img->pix, 1, n, f) != (size_t)n)
		{
			fprintf(stderr, "[APP] PGM P5: nedovoljno podataka\n");
			free(img->pix);
			fclose(f);
			return -1;
		}
	}
	else
	{
		for (i = 0; i < n; i++)
		{
			int v;
			if (pgm_read_int(f, &v))
			{
				fprintf(stderr, "[APP] prekid podataka na pikselu %d\n", i);
				free(img->pix);
				fclose(f);
				return -1;
			}
			img->pix[i] = (uint8_t)(v > 255 ? 255 : v);
		}
	}
	fclose(f);
	return 0;
}

/*Implementacija fiksne tacke iz virtuelne platforme
VP model cuva faktor skale kao sc_ufixed<8,1>, sto znaci da
1.2 postaje 1.203125. Bez ove kvantizacije piramida bi koristila
neznatno drugacije skale nego hardverski model, pa se rezultati ne bi poklapali.
*/
static double q_ufixed(double v, int wl, int iwl)
{
	int fw = wl - iwl;
	double scale = (double)(1u << fw);
	double maxv = (double)((1u << wl) - 1u) / scale;
	double r;
	if (v < 0.0) v = 0.0;
	r = floor(v * scale + 0.5) / scale;
	if (r > maxv) r = maxv;
	return r;
}

static int my_round(double v)
{
	return (int)(q_ufixed(v, 16, 12) + 0.5);
}

/*Integralne slike
sum[i][j] = suma piksela sa redom i , kolonom j
Bafer ima tacno INT_ROWS (25) redova i width kolona. Skalirana slika
se nikada ne materijalizuje nego se redovi sampluju direktno iz originala
metodom najblizeg susjeda, preko odnosa fiksnih tacaka.
*/
static void integral_first(const image_t *im, int32_t *sum, int32_t *sqsum,
                           int width, int height)
{
	int x_ratio = (int)(((int64_t)im->w << 16) / width) + 1;
	int y_ratio = (int)(((int64_t)im->h << 16) / height) + 1;
	int i, j;

	for (i = 0; i < INT_ROWS; i++)
	{
		int src_i = (i * y_ratio) >> 16;
		int rat = 0, s = 0, sq = 0;

		if (src_i >= im->h) src_i = im->h - 1;
		for (j = 0; j < width; j++)
		{
			int src_j = rat >> 16;
			int pix;
			int32_t above, above_sq;

			if (src_j >= im->w) src_j = im->w - 1;
			rat += x_ratio;
			pix = im->pix[src_i * im->w + src_j];
			s += pix;
			sq += pix * pix;
			above    = i ? sum[(i - 1) * width + j]   : 0;
			above_sq = i ? sqsum[(i - 1) * width + j] : 0;
			sum[i * width + j]   = s + above;
			sqsum[i * width + j] = sq + above_sq;
		}
	}
}

static void integral_lastrow(const image_t *im, int32_t *sum, int32_t *sqsum,
                             int width, int sz_height, int y_bias)
{
	int x_ratio = (int)(((int64_t)im->w << 16) / width) + 1;
	int y_ratio = (int)(((int64_t)im->h << 16) / sz_height) + 1;
	int src_i, rat = 0, s = 0, sq = 0, x, y;

	/* Lokalne kopije se pomjeraju za jedan red */
	for (y = 0; y < INT_ROWS - 1; y++)
	{
		memmove(&sum[y * width],   &sum[(y + 1) * width],   width * sizeof(int32_t));
		memmove(&sqsum[y * width], &sqsum[(y + 1) * width], width * sizeof(int32_t));
	}

	src_i = ((WIN_SIZE + y_bias) * y_ratio) >> 16;
	if (src_i >= im->h) src_i = im->h - 1;

	for (x = 0; x < width; x++)
	{
		int src_j = rat >> 16, pix;
		if (src_j >= im->w) src_j = im->w - 1;
		rat += x_ratio;
		pix = im->pix[src_i * im->w + src_j];
		s += pix;
		sq += pix * pix;
		sum[24 * width + x]   = s  + sum[23 * width + x];
		sqsum[24 * width + x] = sq + sqsum[23 * width + x];
	}
}

/*Pristup hardveru kroz device fajlove*/
static int vj_open(vj_dev_t *d)
{
	d->fd_ctrl = open(DEV_CTRL, O_RDWR);
	d->fd_rows = open(DEV_ROWS, O_WRONLY);
	d->fd_hits = open(DEV_HITS, O_RDONLY);
	if (d->fd_ctrl < 0 || d->fd_rows < 0 || d->fd_hits < 0)
	{
		fprintf(stderr, "[APP] ne mogu otvoriti device fajlove: %s\n", strerror(errno));
		fprintf(stderr, "[APP] da li je vj_driver ucitan i da li su dozvole postavljene?\n");
		return -1;
	}
	return 0;
}

static void vj_close(vj_dev_t *d)
{
	if (d->fd_ctrl >= 0) close(d->fd_ctrl);
	if (d->fd_rows >= 0) close(d->fd_rows);
	if (d->fd_hits >= 0) close(d->fd_hits);
}

static int vj_cmd(vj_dev_t *d, const char *fmt, ...)
{
	char buf[256];
	va_list ap;
	int n;

	va_start(ap, fmt);
	n = vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	if (n <= 0 || n >= (int)sizeof(buf)) return -1;
	if (write(d->fd_ctrl, buf, n) != n)
	{
		fprintf(stderr, "[APP] komanda '%s' neuspjesna: %s\n", buf, strerror(errno));
		return -1;
	}
	return 0;
}

static int vj_upload_row(vj_dev_t *d, int bank, const int32_t *row, int n)
{
	off_t off = (off_t)bank * BANK_DEPTH * 4;
	ssize_t len = (ssize_t)n * 4;

	if (pwrite(d->fd_rows, row, len, off) != len)
	{
		fprintf(stderr, "[APP] upis banke %d neuspjesan: %s\n", bank, strerror(errno));
		return -1;
	}
	stat_row_writes++;
	return 0;
}

/*Cekanje na DONE prekid; vraca broj detekcija*/
static int vj_wait_done(vj_dev_t *d)
{
	char buf[128];
	ssize_t n;
	unsigned busy = 0, done = 0, hits = 0;
	int result = 0;

	n = pread(d->fd_ctrl, buf, sizeof(buf) - 1, 0);
	if (n <= 0)
	{
		fprintf(stderr, "[APP] cekanje na DONE: %s\n", strerror(errno));
		return -1;
	}
	buf[n] = '\0';
	if (sscanf(buf, "busy=%u done=%u result=%d hits=%u", &busy, &done, &result, &hits) != 4)
	{
		fprintf(stderr, "[APP] neocekivan odgovor drajvera: %s", buf);
		return -1;
	}
	if (!done)
	{
		fprintf(stderr, "[APP] obrada nije zavrsena (busy=%u)\n", busy);
		return -1;
	}
	return (int)hits;
}

static int vj_read_hits(vj_dev_t *d, int *xs, int max)
{
	static char buf[HIT_DEPTH * 8 + 1];
	ssize_t n;
	char *p;
	int cnt = 0;

	n = pread(d->fd_hits, buf, sizeof(buf) - 1, 0);
	if (n < 0)
	{
		fprintf(stderr, "[APP] citanje detekcija: %s\n", strerror(errno));
		return -1;
	}
	buf[n] = '\0';
	p = buf;
	while (*p && cnt < max)
	{
		char *end;
		long v = strtol(p, &end, 10);
		if (end == p) break;
		xs[cnt++] = (int)v;
		p = end;
	}
	return cnt;
}

/* Jedan sweep po redu: postavljanje parametara, start, cekanje, citanje. */
static int vj_sweep(vj_dev_t *d, int row_base, int width, int x_last, int step,
                    int *xs, int max)
{
	int hits, got;

	if (vj_cmd(d, "row_base=%d width=%d x_start=0 x_last=%d x_step=%d sweep",
	           row_base, width, x_last, step))
		return -1;
	stat_sweeps++;

	hits = vj_wait_done(d);
	if (hits < 0) return -1;
	if (hits == 0) return 0;

	got = vj_read_hits(d, xs, max);
	if (got < 0) return -1;
	stat_raw_hits += got;
	return got;
}

/* Grupisanje pravougaonika. Parametri su sljedeci: prag grupe je 1
(dakle grupa mora imati bar dva clana) a eps 0.4.*/
static int r_abs(int v)
{
	return v < 0 ? -v : v;
}

static int predicate_eq(double eps, const rect_t *r1, const rect_t *r2)
{
	double delta = q_ufixed(0.5 * eps * ((r1->w > r2->w ? r2->w : r1->w) +
	                                     (r1->h > r2->h ? r2->h : r1->h)), 16, 8);
	return r_abs(r1->x - r2->x) <= delta &&
	       r_abs(r1->y - r2->y) <= delta &&
	       r_abs(r1->x + r1->w - r2->x - r2->w) <= delta &&
	       r_abs(r1->y + r1->h - r2->y - r2->h) <= delta;
}

static int partition_rects(const rect_t *r, int n, int *labels, double eps)
{
	int parent[MAX_FACES], rank[MAX_FACES];
	int i, j, nclasses = 0;

	for (i = 0; i < n; i++)
	{
		parent[i] = -1;
		rank[i] = 0;
	}
	for (i = 0; i < n; i++)
	{
		int root = i;
		while (parent[root] >= 0) root = parent[root];
		for (j = 0; j < n; j++)
		{
			int root2 = j, k, p;
			if (i == j || !predicate_eq(eps, &r[i], &r[j])) continue;
			while (parent[root2] >= 0) root2 = parent[root2];
			if (root2 == root) continue;
			if (rank[root] > rank[root2])
			{
				parent[root2] = root;
			}
			else
			{
				parent[root] = root2;
				if (rank[root] == rank[root2]) rank[root2]++;
				root = root2;
			}
			k = j;
			while ((p = parent[k]) >= 0)
			{
				parent[k] = root;
				k = p;
			}
			k = i;
			while ((p = parent[k]) >= 0)
			{
				parent[k] = root;
				k = p;
			}
		}
	}
	for (i = 0; i < n; i++)
	{
		int root = i;
		while (parent[root] >= 0) root = parent[root];
		if (rank[root] >= 0) rank[root] = ~nclasses++;
		labels[i] = ~rank[root];
	}
	return nclasses;
}

static int group_rectangles(rect_t *r, int n, int group_threshold, double eps)
{
	int labels[MAX_FACES], cnt[MAX_FACES];
	rect_t acc[MAX_FACES];
	int nclasses, i, j, out = 0;

	if (group_threshold <= 0 || n == 0) return n;
	nclasses = partition_rects(r, n, labels, eps);

	for (i = 0; i < nclasses; i++)
	{
		acc[i].x = acc[i].y = acc[i].w = acc[i].h = 0;
		cnt[i] = 0;
	}
	for (i = 0; i < n; i++)
	{
		int c = labels[i];
		acc[c].x += r[i].x;
		acc[c].y += r[i].y;
		acc[c].w += r[i].w;
		acc[c].h += r[i].h;
		cnt[c]++;
	}
	for (i = 0; i < nclasses; i++)
	{
		double s = q_ufixed(1.0 / cnt[i], 10, 1);
		acc[i].x = my_round(acc[i].x * s);
		acc[i].y = my_round(acc[i].y * s);
		acc[i].w = my_round(acc[i].w * s);
		acc[i].h = my_round(acc[i].h * s);
	}
	for (i = 0; i < nclasses; i++)
	{
		int n1 = cnt[i];
		if (n1 <= group_threshold) continue;
		for (j = 0; j < nclasses; j++)
		{
			int n2 = cnt[j], dx, dy;
			if (j == i) continue;
			if (n2 <= group_threshold) continue;
			dx = my_round(acc[j].w * eps);
			dy = my_round(acc[j].h * eps);
			if (acc[i].x >= acc[j].x - dx && acc[i].y >= acc[j].y - dy &&
			        acc[i].x + acc[i].w <= acc[j].x + acc[j].w + dx &&
			        acc[i].y + acc[i].h <= acc[j].y + acc[j].h + dy &&
			        (n2 > (3 > n1 ? 3 : n1) || n1 < 3))
				break;
		}
		if (j == nclasses && out < MAX_FACES) r[out++] = acc[i];
	}
	return out;
}

/*Glavna detekcijska petlja - struktura identicna vj_detect()*/
static int detect(vj_dev_t *d, const image_t *im, double scale_factor,
                  int shift_step, rect_t *faces, int max_faces, int verbose)
{
	double sf = q_ufixed(scale_factor, 8, 1);
	double factor = 1.0;
	int nf = 0, nscales = 0;
	int32_t *g_int, *g_sq;
	int xs[HIT_DEPTH];

	g_int = malloc((size_t)INT_ROWS * im->w * sizeof(int32_t));
	g_sq  = malloc((size_t)INT_ROWS * im->w * sizeof(int32_t));
	if (!g_int || !g_sq)
	{
		free(g_int);
		free(g_sq);
		return -1;
	}

	for (;;)
	{
		int sz_w = (int)(im->w / factor);
		int sz_h = (int)(im->h / factor);
		int win_w = my_round(WIN_SIZE * factor);
		int win_h = my_round(WIN_SIZE * factor);
		int x2, x_hi, x_last, row_base = 0, y_bias, k, got;

		if (sz_w < WIN_SIZE || sz_h < WIN_SIZE) break;
		if (win_w < 20 || win_h < 20)
		{
			factor = q_ufixed(factor * sf, 10, 5);
			continue;
		}
		if (sz_w > BANK_DEPTH)
		{
			if (verbose) printf("[APP] skala %.4f (%dx%d): presiroka, preskacem\n", factor, sz_w, sz_h);
			factor = q_ufixed(factor * sf, 10, 5);
			continue;
		}

		x2 = sz_w - WIN_SIZE;
		x_hi = x2 - 1;
		if (x_hi < 0)
		{
			factor = q_ufixed(factor * sf, 10, 5);
			continue;
		}
		x_last = (x_hi / shift_step) * shift_step;

		/*Prva pozicija reda: puni bafer i svih 25 banaka*/
		integral_first(im, g_int, g_sq, sz_w, sz_h);
		for (k = 0; k < INT_ROWS; k++)
			if (vj_upload_row(d, k, &g_int[k * sz_w], sz_w)) goto fail;
		if (vj_upload_row(d, SQ0_BANK,  &g_sq[0  * sz_w], sz_w)) goto fail;
		if (vj_upload_row(d, SQ23_BANK, &g_sq[23 * sz_w], sz_w)) goto fail;

		got = vj_sweep(d, row_base, sz_w, x_last, shift_step, xs, HIT_DEPTH);
		if (got < 0) goto fail;
		for (k = 0; k < got && nf < max_faces; k++)
		{
			faces[nf].x = my_round(xs[k] * factor);
			faces[nf].y = 0;
			faces[nf].w = win_w;
			faces[nf].h = win_h;
			nf++;
		}

		/*Pomjeranje prozora po y: jedan novi red + dva kvadrirana*/
		for (y_bias = 1; y_bias < sz_h - INT_ROWS + 1; y_bias++)
		{
			integral_lastrow(im, g_int, g_sq, sz_w, sz_h, y_bias);

			if (vj_upload_row(d, row_base, &g_int[24 * sz_w], sz_w)) goto fail;
			row_base = (row_base + 1) % INT_ROWS;
			if (vj_upload_row(d, SQ0_BANK,  &g_sq[0  * sz_w], sz_w)) goto fail;
			if (vj_upload_row(d, SQ23_BANK, &g_sq[23 * sz_w], sz_w)) goto fail;

			got = vj_sweep(d, row_base, sz_w, x_last, shift_step, xs, HIT_DEPTH);
			if (got < 0) goto fail;
			for (k = 0; k < got && nf < max_faces; k++)
			{
				faces[nf].x = my_round(xs[k] * factor);
				faces[nf].y = my_round(y_bias * factor);
				faces[nf].w = win_w;
				faces[nf].h = win_h;
				nf++;
			}
			if (verbose && got)
				printf("[APP]   skala %.4f  y=%3d: %d detekcija\n", factor, y_bias, got);
		}

		nscales++;
		if (verbose)
			printf("[APP] skala %.4f (%d x %d), prozor %d, x_last %d\n",
			       factor, sz_w, sz_h, win_w, x_last);

		factor = q_ufixed(factor * sf, 10, 5);
	}

	free(g_int);
	free(g_sq);
	printf("[APP] Skala obradjeno: %d\n", nscales);
	return nf;

fail:
	free(g_int);
	free(g_sq);
	return -1;
}

static void usage(const char *prog)
{
	printf("Nacin koristenja: %s <slika.pgm> [opcije]\n\n", prog);
	printf("  -f <faktor>  faktor skale (podrazumijevano %.1f)\n", DEF_SCALE_FACTOR);
	printf("  -s <korak>   shift step (podrazumijevano %d)\n", DEF_SHIFT_STEP);
	printf("  -n <prag>    prag grupisanja (podrazumijevano %d)\n", DEF_GROUP_THRESH);
	printf("  -e <eps>     eps grupisanja (podrazumijevano %.1f)\n", DEF_GROUP_EPS);
	printf("  -o <fajl>    upis rezultata u fajl\n");
	printf("  -r           ispis negrupisanih detekcija\n");
	printf("  -v           detaljan ispis\n");
}

int main(int argc, char **argv)
{
	const char *img_path = NULL, *out_path = NULL;
	double scale_factor = DEF_SCALE_FACTOR, eps = DEF_GROUP_EPS;
	int shift_step = DEF_SHIFT_STEP, group_thresh = DEF_GROUP_THRESH;
	int verbose = 0, raw = 0, opt, i, nf, ngrouped, rc = EXIT_FAILURE;
	image_t img = { 0, 0, NULL };
	vj_dev_t dev = { -1, -1, -1 };
	rect_t *faces = NULL;
	struct timespec t0, t1;
	double ms;

	while ((opt = getopt(argc, argv, "f:s:n:e:o:rvh")) != -1)
	{
		switch (opt)
		{
		case 'f':
			scale_factor = atof(optarg);
			break;
		case 's':
			shift_step = atoi(optarg);
			break;
		case 'n':
			group_thresh = atoi(optarg);
			break;
		case 'e':
			eps = atof(optarg);
			break;
		case 'o':
			out_path = optarg;
			break;
		case 'r':
			raw = 1;
			break;
		case 'v':
			verbose = 1;
			break;
		case 'h':
			usage(argv[0]);
			return EXIT_SUCCESS;
		default:
			usage(argv[0]);
			return EXIT_FAILURE;
		}
	}
	if (optind >= argc)
	{
		usage(argv[0]);
		return EXIT_FAILURE;
	}
	img_path = argv[optind];
	if (shift_step < 1)
	{
		fprintf(stderr, "[APP] korak mora biti >= 1\n");
		return EXIT_FAILURE;
	}

	if (image_load(img_path, &img)) return EXIT_FAILURE;
	printf("[APP] Slika: %s (%d x %d)\n", img_path, img.w, img.h);
	printf("[APP] scaleFactor %.4f, shiftStep %d, grupisanje prag %d eps %.2f\n",
	       q_ufixed(scale_factor, 8, 1), shift_step, group_thresh, eps);
	if (img.w > MAX_IMG_WIDTH)
		printf("[APP] UPOZORENJE: sirina %d prelazi MAX_IMG_WIDTH (%d)\n", img.w, MAX_IMG_WIDTH);

	faces = malloc(MAX_FACES * sizeof(rect_t));
	if (!faces) goto cleanup;
	if (vj_open(&dev)) goto cleanup;
	if (vj_cmd(&dev, "reset clear_done")) goto cleanup;

	clock_gettime(CLOCK_MONOTONIC, &t0);
	nf = detect(&dev, &img, scale_factor, shift_step, faces, MAX_FACES, verbose);
	clock_gettime(CLOCK_MONOTONIC, &t1);
	if (nf < 0) goto cleanup;
	ms = (t1.tv_sec - t0.tv_sec) * 1000.0 + (t1.tv_nsec - t0.tv_nsec) / 1e6;

	if (raw)
	{
		printf("\nSirove detekcije (x y w h):\n");
		for (i = 0; i < nf; i++)
			printf("  %4d %4d %4d %4d\n", faces[i].x, faces[i].y, faces[i].w, faces[i].h);
	}

	ngrouped = group_rectangles(faces, nf, group_thresh, eps);

	printf("\n=============== REZULTATI ===============\n");
	printf("Sweep-ova pokrenuto : %ld\n", stat_sweeps);
	printf("Redova poslato      : %ld\n", stat_row_writes);
	printf("Sirovih detekcija   : %ld\n", stat_raw_hits);
	printf("Nakon grupisanja    : %d\n", ngrouped);
	printf("Vrijeme             : %.2f ms\n", ms);
	printf("=========================================\n\n");

	printf("Detektovana lica (x y w h):\n");
	for (i = 0; i < ngrouped; i++)
		printf("  lice %2d :  x=%3d  y=%3d  w=%3d  h=%3d\n",
		       i, faces[i].x, faces[i].y, faces[i].w, faces[i].h);

	if (out_path)
	{
		FILE *fo = fopen(out_path, "w");
		if (fo)
		{
			fprintf(fo, "# x y w h\n");
			for (i = 0; i < ngrouped; i++)
				fprintf(fo, "%d %d %d %d\n", faces[i].x, faces[i].y, faces[i].w, faces[i].h);
			fclose(fo);
			printf("\n[APP] Rezultat upisan u %s\n", out_path);
		}
		else
		{
			fprintf(stderr, "[APP] ne mogu pisati u '%s': %s\n", out_path, strerror(errno));
		}
	}

	rc = EXIT_SUCCESS;

cleanup:
	vj_close(&dev);
	free(faces);
	free(img.pix);
	return rc;
}
