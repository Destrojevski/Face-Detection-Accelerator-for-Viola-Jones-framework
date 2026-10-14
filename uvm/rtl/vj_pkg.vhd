--
-- vj_pkg.vhd
-- Zajednicke konstante, tipovi i pomocne funkcije za Viola-Jones 
-- detektor lica.
-- Glavni dio predstavlja 112-bitnu upakovanu weak-classifier rijec.Raspored ovog paketa je sljedeci:
--   [4:0] r0.x   [24:20] r1.x   [44:40] r2.x
--   [9:5] r0.y   [29:25] r1.y   [49:45] r2.y
--   [14:10] r0.w [34:30] r1.w   [54:50] r2.w
--   [19:15] r0.h [39:35] r1.h   [59:55] r2.h
--   [60] w1_sel      0 => weight1 = 8192 (k=2), 1 => weight1 = 12288 (k=3)
--   [61] w2_en       0 => treci pravougaonik ne postoji, 1 => weight2 = 8192 (k=2)
--   [74:62] tree_thresh 13-bitni komplement dvojke
--   [88:75] alpha1      14-bitni komplement dvojke
--   [102:89] alpha2      14-bitni komplement dvojke
--   [111:103] rezervisano
--
--
--

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

PACKAGE vj_pkg IS

    --
    -- Geometrija slike i prozora
    --
    CONSTANT MAX_IMG_WIDTH : NATURAL := 360; -- najsira skala (factor = 1)
    CONSTANT WIN_SIZE : NATURAL := 24; -- detekcijski prozor 24 x 24
    CONSTANT INT_ROWS : NATURAL := 25; -- redovi sadrzani u kliznom baferu

    --
    -- Row-bank memorija
    -- 25 banki drzi redove integralne slike, rotirane za row_base
    -- tako da pomjeranje y_biasa nema cijenu izvrsavanja.Druge dvije banke sadrze logicke redove 0 i 23
    -- kvadrirane integralne slike -- jedina dva te slike koja algoritam uopste cita
    -- i oni nisu rotirani.
    --
    CONSTANT BANK_DEPTH : NATURAL := 512; -- >= MAX_IMG_WIDTH, stepen dvojke
    CONSTANT BANK_AW : NATURAL := 9; -- log2(BANK_DEPTH)
    CONSTANT BANK_DW : NATURAL := 32;
    CONSTANT N_INT_BANKS : NATURAL := 25;
    CONSTANT N_BANKS : NATURAL := 27; -- 25 integralna + 2 kvadrirana
    CONSTANT SQ0_BANK : NATURAL := 25; -- kvadrirana integralna, logicki red 0
    CONSTANT SQ23_BANK : NATURAL := 26; -- kvadrirana integralna, logicki red 23

    -- Byte-lane-free adresna rijec koju vidi PS write port:
    --   ps_addr(13 downto 9) = index banke(0..26)
    --   ps_addr( 8 downto 0) = kolona
    CONSTANT PS_AW : NATURAL := BANK_AW + 5;

    --
    -- Klasifikacioni ROM
    --
    CONSTANT CLS_COUNT : NATURAL := 2913;
    CONSTANT CLS_AW : NATURAL := 12; -- 4096 >= 2913
    CONSTANT CLS_DW : NATURAL := 112;

    --
    -- Sirine datapatha
    --
    CONSTANT ACC_W : NATURAL := 32; -- mora biti 32 (kao u referentnom modelu)
    -- oslanja se na 32-bitni wrap-around
    CONSTANT VNF_W : NATURAL := 16; -- int_sqrt 32-bitne vrijednosti
    CONSTANT TT_W : NATURAL := 13; -- tree_thresh
    CONSTANT ALPHA_W : NATURAL := 14; -- alpha1 / alpha2
    CONSTANT STAGE_SUM_W : NATURAL := 24; -- max |sum| = 211 * 7680 < 2^21
    CONSTANT FIELD_W : NATURAL := 5; -- polja pravougaonika su 0..24
    CONSTANT COL_W : NATURAL := BANK_AW;
    CONSTANT ROW_W : NATURAL := 5;

    -- 24 * 24, koristi se za skaliranje kvadrirane sume.  576 = 2^9 + 2^6, pa
    -- monzac nije potreban.
    CONSTANT INV_WINDOW_AREA : NATURAL := WIN_SIZE * WIN_SIZE;

    --
    -- Hit buffer (za mod B).Najsira skala ima 336 prozorskih pozicija po redu,
    -- pa nam bafer dubine 512 onemogucava overflow i dozvoljava nam da izbacimo
    -- overflow flag u potpunosti.
    --
    CONSTANT HIT_DEPTH : NATURAL := 512;
    CONSTANT HIT_AW : NATURAL := 9;

    --
    -- Tezinski kodovi
    -- Svaka tezina u kaskadi je 4096 * k gdje je k {-1, 2, 3}, pa se
    -- suma karakteristika faktorise u (sum of k*rect_sum) << 12 i unutrasnja petlja
    -- opet ne treba mnozac.
    --
    CONSTANT KCODE_NEG1 : STD_LOGIC_VECTOR(1 DOWNTO 0) := "00"; -- weight -4096
    CONSTANT KCODE_2 : STD_LOGIC_VECTOR(1 DOWNTO 0) := "01"; -- weight  8192
    CONSTANT KCODE_3 : STD_LOGIC_VECTOR(1 DOWNTO 0) := "10"; -- weight 12288
    CONSTANT WEIGHT_SHIFT : NATURAL := 12; -- 4096 = 1 << 12

    --
    -- Tipovi
    --
    TYPE bank_addr_arr_t IS ARRAY (0 TO N_BANKS - 1)
    OF STD_LOGIC_VECTOR(BANK_AW - 1 DOWNTO 0);
    TYPE bank_data_arr_t IS ARRAY (0 TO N_BANKS - 1)
    OF STD_LOGIC_VECTOR(BANK_DW - 1 DOWNTO 0);
    TYPE bank_bit_arr_t IS ARRAY (0 TO N_BANKS - 1) OF STD_LOGIC;

    -- Jedan pravougaonik onako kako se cita iz pakovane rijeci
    TYPE rect_t IS RECORD
        x : unsigned(FIELD_W - 1 DOWNTO 0);
        y : unsigned(FIELD_W - 1 DOWNTO 0);
        w : unsigned(FIELD_W - 1 DOWNTO 0);
        h : unsigned(FIELD_W - 1 DOWNTO 0);
    END RECORD;

    --
    -- Funkcije koje pristupaju poljima pakovane rijeci
    --
    FUNCTION cls_rect (word : STD_LOGIC_VECTOR(CLS_DW - 1 DOWNTO 0);
        k : NATURAL
    ) RETURN rect_t;
    FUNCTION cls_w1_sel (word : STD_LOGIC_VECTOR(CLS_DW - 1 DOWNTO 0)) RETURN STD_LOGIC;
    FUNCTION cls_w2_en (word : STD_LOGIC_VECTOR(CLS_DW - 1 DOWNTO 0)) RETURN STD_LOGIC;
    FUNCTION cls_tree_thresh(word : STD_LOGIC_VECTOR(CLS_DW - 1 DOWNTO 0)) RETURN signed;
    FUNCTION cls_alpha1 (word : STD_LOGIC_VECTOR(CLS_DW - 1 DOWNTO 0)) RETURN signed;
    FUNCTION cls_alpha2 (word : STD_LOGIC_VECTOR(CLS_DW - 1 DOWNTO 0)) RETURN signed;

    -- rotacija logickog reda integralne slike u indeks njegove fizicke banke.
    FUNCTION rot_bank (row : unsigned; base : unsigned) RETURN unsigned;

END PACKAGE vj_pkg;
PACKAGE BODY vj_pkg IS

    FUNCTION cls_rect (word : STD_LOGIC_VECTOR(CLS_DW - 1 DOWNTO 0);
        k : NATURAL) RETURN rect_t IS
        VARIABLE r : rect_t;
        VARIABLE base : NATURAL;
    BEGIN
        base := k * 20;
        r.x := unsigned(word(base + 4 DOWNTO base + 0));
        r.y := unsigned(word(base + 9 DOWNTO base + 5));
        r.w := unsigned(word(base + 14 DOWNTO base + 10));
        r.h := unsigned(word(base + 19 DOWNTO base + 15));
        RETURN r;
    END FUNCTION;

    FUNCTION cls_w1_sel (word : STD_LOGIC_VECTOR(CLS_DW - 1 DOWNTO 0)) RETURN STD_LOGIC IS
    BEGIN
        RETURN word(60);
    END FUNCTION;

    FUNCTION cls_w2_en (word : STD_LOGIC_VECTOR(CLS_DW - 1 DOWNTO 0)) RETURN STD_LOGIC IS
    BEGIN
        RETURN word(61);
    END FUNCTION;

    FUNCTION cls_tree_thresh (word : STD_LOGIC_VECTOR(CLS_DW - 1 DOWNTO 0)) RETURN signed IS
    BEGIN
        RETURN signed(word(74 DOWNTO 62));
    END FUNCTION;

    FUNCTION cls_alpha1 (word : STD_LOGIC_VECTOR(CLS_DW - 1 DOWNTO 0)) RETURN signed IS
    BEGIN
        RETURN signed(word(88 DOWNTO 75));
    END FUNCTION;

    FUNCTION cls_alpha2 (word : STD_LOGIC_VECTOR(CLS_DW - 1 DOWNTO 0)) RETURN signed IS
    BEGIN
        RETURN signed(word(102 DOWNTO 89));
    END FUNCTION;

    -- (row + base) mod 25, implementirano kao uslovno oduzimanje jer su oba operanda
    -- manja od 25.
    FUNCTION rot_bank (row : unsigned; base : unsigned) RETURN unsigned IS
        VARIABLE s : unsigned(6 DOWNTO 0);
    BEGIN
        s := resize(row, 7) + resize(base, 7);
        IF s >= to_unsigned(N_INT_BANKS, 7) THEN
            s := s - to_unsigned(N_INT_BANKS, 7);
        END IF;
        RETURN s(4 DOWNTO 0);
    END FUNCTION;

END PACKAGE BODY vj_pkg;