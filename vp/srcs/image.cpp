/*
/ Naziv fajla: image.cpp
/ Opis fajla: funkcije za obradu grayscale slike
/ Autori: Sandić Vojislav, Jović Radivoje, Glišević Sara
/ Datum: 24.12.2024.
*/

#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include "image.h"
/*
/ Naziv funkcije: strrev
/ Parametri: jedan parametar koji je pokazivač na početak stringa
/ Povratna vrednost: pokazivač na početak stringa
/ Opis funkcije: funkcija obrće string i vraća pokazivač na početak obrnutog stringa
*/
char* strrev(char* str)
{
	char *p1, *p2;
	if (!str || !*str)
		return str;
	for (p1 = str, p2 = str + strlen(str) - 1; p2 > p1; ++p1, --p2)
	{
		*p1 ^= *p2;
		*p2 ^= *p1;
		*p1 ^= *p2;
	}
	return str;
}
/*
/ Naziv funkcije: myatoi
/ Parametri: string koji je broj
/ Povratna vrednost: int broj
/ Opis funkcije: funkcija koja pretvara broj tipa string u broj tipa int
*/
int myatoi (char* string)
{
	int sign = 1;
	// dužina broja u stringu
	int length = strlen(string);
	int i = 0;
	int number = 0;

	// odreživanje znaka
	if (string[0] == '-'){
		sign = -1;
		i++;
	}

	while(i < length){
		// preskakanje decimalnog zareza
		if (string[i] == '.')
			break;
		// prebacivanje u broj iz ASCII tabele
		number = number * 10 + (string[i]- 48);
		i++;
	}
        // postavljanje znaka
	number *= sign;

	return number;
}
/*
/ Naziv funkcije: itochar
/ Parametri: int broj koji se pretvara, szBuffer niz u kojem čuvamo vrednost broja, radix broj koji označava brojni sistem (2-BIN, 8-OCT, 10-DEC, 16-HEX)
/ Povratna vrednost: nema
/ Opis funkcije: funkcija koja pretvara broj tipa int u broj tipa string, tako što deli broj osnovom brojnog sistema i izvlači cifre
*/
void itochar(int x, char* szBuffer, int radix)
{
	int i = 0, n, xx;
	n = x; // privremena promenljiva, da bi se očuvala originalna vrednost broja 
	// broj se deli dok ne postane nula
	while (n > 0)
	{
		xx = n%radix; // ostatak pri deljenju sa osnovom brojnog sistema
		n = n/radix; // deljenje osnovom brojnog sistema da bi se izdvojila cifra
		szBuffer[i++] = '0' + xx; // ubacivanje izdvojene cifre u bafer
	}
	szBuffer[i] = '\0'; // završetak stringa
	strrev(szBuffer); // obrtanje stringa jer smo radili izdvajanje cifara od najmanje značanje ka naviše značajnoj cifri
}
/*
/ Naziv funkcije: readPgm
/ Parametri: string ime .pgm fajla, MyImage struktura u koju smeštamo binarnu sliku
/ Povratna vrednost: int 0 za uspešno ili -1 za grešku
/ Opis funkcije: funkcija koja čita .pgm fajl u binarnom formatu i smešta ga u MyImage strukturu
*/
int readPgm(char *fileName, MyImage *image)
{
	FILE *in_file;
	char ch;
	int type;
	char version[3];
	char line[100];
	char mystring [20];
	char *pch;
	int i;
	long int position;

	// otvaranje fajla, stavljen mod rb jer windows cita 'r' kao tekst i 'rb' kao binarnu vrijednost
	in_file = fopen(fileName, "rb");
	if (in_file == NULL)
	{
		printf("Greska : ne mogu otvoriti fajl %s\n\n", fileName);
		return -1;
	}
	printf("\nCitanje fajla slike: %s\n", fileName);
	// Određivanje tipa fajla, sirovi .pgm fajl počinje sa P5
	ch = fgetc(in_file);// čitanje prvog karaktera
	if(ch != 'P')// ako prvi karakter u fajlu nije P onda otvoreni fajl nije .pgm fajl
	{
		printf("Greska : nije validan tip PGM fajla \n");
		return -1;
	}

	ch = fgetc(in_file); // čitanje drugog karaktera
	type = ch - 48; // prebacivanje u int preko ASCII (48 == '0')
	if(type != 5)//ako drugi karakter u fajlu nije 5 onda otvoreni fajl nije u sirovom formatu
	{
		printf("Greska : dozvoljen samo pgm raw format \n");
		return -1;
	}
	
	
        
	while ((ch = fgetc(in_file)) != EOF && isspace(ch));// preskakanje razmaka (space)
	position = ftell(in_file); // pamćenje pozicije razmaka


	// Kod za preskakanje komentara u .pgm fajlu
	if (ch == '#')// komentari u .pgm fajlu počinju sa #
		{
			if(fgets(line, sizeof(line), in_file)); // uzima celu liniju koda, if utišava upozorenje za neiskorišćenu return vrednost funkcije
			while ((ch = fgetc(in_file)) != EOF && isspace(ch)); // preskače razmake u komentaru
			position = ftell(in_file);//pamti poziciju nakon skoka
		}

        //nastavnlja se čitanje sa zapamćene pozicije
	fseek(in_file, position-1, SEEK_SET);

        //čitanje veličine slike, prebacivanje u int i čuvanje u image strukturi
	if(fgets (mystring , 20, in_file));
	pch = (char *)strtok(mystring," ");
	image->width = atoi(pch);
	pch = (char *)strtok(NULL," ");
	image->height = atoi(pch);
	//čitanje maximalne grayscale vrednosti
	if(fgets (mystring , 5, in_file));
	image->maxgrey = PGM_MAXGRAY;
	image->data = (unsigned char*)malloc(sizeof(unsigned char)*(IMAGE_HEIGHT*IMAGE_WIDTH));//alociranje memorije
	image->flag = 1; // flag za uspešno učitavanje slike
	
	// čitanje sirovih vrednosti bajtova i smeštanje u data niz image strukture
	for(i=0;i<(IMAGE_HEIGHT*IMAGE_WIDTH);i++)
	{
		ch = fgetc(in_file);
		image->data[i] = (unsigned char)ch;
	}

	fclose(in_file); // zatvaranje fajla
	return 0;
}

/*
/ Naziv funkcije: cpyPgm
/ Parametri: dve MyImage strukture od kojih je jedna izvor a druga destinacija kopiranja
/ Povratna vrednost: int 0 za uspešno ili -1 za grešku
/ Opis funkcije: funkcija koja čita vrednosti iz jedne MyImage strukture i kopira ih u drugu MyImage strukturu
*/
int cpyPgm(MyImage* src, MyImage* dst)
{
	int i = 0;
	if (src->flag == 0)// provera da li je struktura validna
	{
		printf("Nema dostupnih podataka u navedenoj izvornoj slici\n");
		return -1;
	}
	// kopiranje formata strukture
	dst->width = src->width;
	dst->height = src->height;
	dst->maxgrey = src->maxgrey;
	dst->data = (unsigned char*)malloc(sizeof(unsigned char)*(dst->height*dst->width));// alokacija memorije
	dst->flag = 1; // flag za uspošno formiranu destinacionu strukturu
	for (i = 0; i < (dst->width * dst->height); i++)// kopiranje vrednosti izvorne strukture u destinacionu
	{
		dst->data[i] = src->data[i];
	}
	return 0;
}
/*
/ Naziv funkcije: createImage
/ Parametri: dve int vrednosti za visinu i širinu slike, pokazivač na MyImage strukturu koju kreiramo
/ Povratna vrednost: nema
/ Opis funkcije: funkcija koja kreira MyImage strukturu sa određenom visinom i širinom
*/
void createImage(int width, int height, MyImage *image)
{
	image->width = width;
	image->height = height;
	image->flag = 1;
	image->data = (unsigned char *)malloc(sizeof(unsigned char)*(height*width));
}
/*
/ Naziv funkcije: createSumImage
/ Parametri: dve int vrednosti za visinu i širinu slike, pokazivač na MyIntImage strukturu koju kreiramo
/ Povratna vrednost: nema
/ Opis funkcije: funkcija koja kreira MyIntImage (integralnu sliku) strukturu sa određenom visinom i širinom
*/
void createSumImage(int width, int height, MyIntImage *image)
{
	image->width = width;
	image->height = height;
	image->flag = 1;
	image->data = (int *)malloc(sizeof(int)*(height*width));
}
/*
/ Naziv funkcije: freeImage
/ Parametri: MyImage struktura koju brišemo
/ Povratna vrednost: int vrednosti 0 za uspešno brisanje ili -1 za neuspešno
/ Opis funkcije: funkcija koja briše podatke iz MyImage strukture
*/
int freeImage(MyImage* image)
{
	if (image->flag == 0)// provera da li postoji slika
	{
		printf("Ne postoji slika za brisanje !\n");
		return -1;
	}
	else
	{
		//printf("image deleted\n");
		free(image->data);// brisanje slike
		return 0;
	}
}
/*
/ Naziv funkcije: freeSumImage
/ Parametri: MyIntImage struktura koju brišemo
/ Povratna vrednost: int vrednosti 0 za uspešno brisanje ili -1 za neuspešno
/ Opis funkcije: funkcija koja briše integralnu sliku
*/
int freeSumImage(MyIntImage* image)
{
	if (image->flag == 0)// provera da li postoji integralna slika
	{
		printf("Ne postoji slika za brisanje !\n");
		return -1;
	}
	else
	{
		//printf("image deleted\n");
		free(image->data);// brisanje slike
		return 0;
	}
}
/*
/ Naziv funkcije: setImage
/ Parametri: dve int vrednosti visina i širina, MyImage struktura kojoj menjamo vrednosti
/ Povratna vrednost: nema
/ Opis funkcije: setter funkcija koja menja vrednosti parametara visine i širine MyImage strukture
*/
void setImage(int width, int height, MyImage *image)
{
	image->width = width;
	image->height = height;
}
/*
/ Naziv funkcije: setSumImage
/ Parametri: dve int vrednosti visina i širina, MyIntImage struktura kojoj menjamo vrednosti
/ Povratna vrednost: nema
/ Opis funkcije: setter funkcija koja menja vrednosti parametara visine i širine MyIntImage strukture
*/
void setSumImage(int width, int height, MyIntImage *image)
{
	image->width = width;
	image->height = height;
}
/*
/ Naziv funkcije: checkImg
/ Parametri: 2D niz (bafer), dve vrednosti tipa int visina i širina .pgm fajla u koji upisujemo
/ Povratna vrednost: int vrednosti 0 za uspešno izvršenu funkciju ili -1 za neuspešno
/ Opis funkcije: funckija koja proverava stanje bafera i upisuje vrednosti iz njega u test.pgm fajl
*/
int checkImg(sc_uint<8> buffer[IMAGE_HEIGHT][IMAGE_WIDTH], int width, int height)
{
	char parameters_str[5];
	int i,j;
	const char *format = "P5";// konstanta za format fajla, P5 sirovi binarni format

	FILE *fp = fopen("test.pgm", "wb");//otvaranje test.pgm fajla
	if (!fp)// provera da li je fajl uspešno otvoren
	{
		printf("Ne mogu otvoriti fajl test.pgm\n");
		return -1;
	}
	// pisanje hedera fajla za format
	fputs(format, fp);
	fputc('\n', fp);
  
        // pisanje osnovnih podataka fajla, visina, širina i maksimalna grayscale vrednost
	itochar(width, parameters_str, 10);
	fputs(parameters_str, fp);
	parameters_str[0] = 0;
	fputc(' ', fp);

	itochar(height, parameters_str, 10);
	fputs(parameters_str, fp);
	parameters_str[0] = 0;
	fputc('\n', fp);

	itochar(PGM_MAXGRAY, parameters_str, 10);
	fputs(parameters_str, fp);
	fputc('\n', fp);

        //pisanje vrednosti bafera u test.pgm fajl
        for (i=0;i<height;i++){
            for(j=0;j<width;j++){
                fputc(buffer[i][j],fp);
            }
        }
	fclose(fp);// zatvaranje fajla
	return 0;
}
