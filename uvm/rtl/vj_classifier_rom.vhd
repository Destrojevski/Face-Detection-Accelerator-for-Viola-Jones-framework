--
-- vj_classifier_rom.vhd
-- ROM dio memorije u koji su upakovani klasifikatori: 2913 112-bitnih elemenata, jedan po slabom klasifikatoru
-- Ovakvo cuvanje znaci da citanje klasifikatora kosta jedan memorijski read
-- umjesto 17 koliko je stari layout zahtijevao(1 tree_thresh +
-- 12 rectangle polja + 3 weighta + 1 alpha), a adresa postaje brojac jer
-- se klasifikatori redom posjecuju.
--

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE STD.TEXTIO.ALL;
USE IEEE.STD_LOGIC_TEXTIO.ALL;

LIBRARY work;
USE work.vj_pkg.ALL;

ENTITY vj_classifier_rom IS
    GENERIC (
        INIT_FILE : STRING := "classifier_rom.mem"
    );
    PORT (
        clk : IN STD_LOGIC;
        en : IN STD_LOGIC;
        addr : IN STD_LOGIC_VECTOR(CLS_AW - 1 DOWNTO 0);
        dout : OUT STD_LOGIC_VECTOR(CLS_DW - 1 DOWNTO 0)
    );
END ENTITY vj_classifier_rom;

ARCHITECTURE rtl OF vj_classifier_rom IS

    -- Puni adresni prostor umjesto vrijednosti CLS_COUNT: prefetch za klasifikatore
    -- cita haar+1, koji se izvrsava jedan ciklus nakon kraja kaskade na posljednjem
    -- klasifikatoru. Ova vrijednost se nikad ne koristi, ali njeno citanje mora biti validno.
    TYPE rom_t IS ARRAY (0 TO 2 ** CLS_AW - 1) OF STD_LOGIC_VECTOR(CLS_DW - 1 DOWNTO 0);

    IMPURE FUNCTION load_rom (path : STRING) RETURN rom_t IS
        FILE f : text;
        VARIABLE l : line;
        VARIABLE v : STD_LOGIC_VECTOR(CLS_DW - 1 DOWNTO 0);
        VARIABLE r : rom_t := (OTHERS => (OTHERS => '0'));
        VARIABLE st : file_open_status;
    BEGIN
        file_open(st, f, path, read_mode);
        ASSERT st = open_ok
        REPORT "vj_classifier_rom: cannot open " & path
            SEVERITY failure;
        FOR i IN 0 TO CLS_COUNT - 1 LOOP
            EXIT WHEN endfile(f);
            readline(f, l);
            hread(l, v);
            r(i) := v;
        END LOOP;
        file_close(f);
        RETURN r;
    END FUNCTION;

    SIGNAL rom : rom_t := load_rom(INIT_FILE);

    ATTRIBUTE ram_style : STRING;
    ATTRIBUTE ram_style OF rom : SIGNAL IS "block";

BEGIN

    PROCESS (clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF en = '1' THEN
                dout <= rom(to_integer(unsigned(addr)));
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE rtl;
--
-- vj_isqrt.vhd
-- Implementacija cjelobrojnog korijena, kao iz VP
--     a = b = c = 0
--     for i in 0..15:
--         c = (c << 2) + (value >> 30);  value <<= 2
--         a <<= 1;  b = (a << 1) | 1
--         if c >= b then  c -= b;  a += 1
--     return a
-- Ovdje je izvrseno foldovanje dvije iteracije po taktu, pa se na rezultat ceka 8 ciklusa
-- umjesto 16. Ova optimizacija je vrijedna jer se jezgro pokrece jednom po prozoru dok
-- prosjecan prozor poredi samo oko 15 klasifikator -- fiksna cijena izvrsavanja po prozoru
-- je veliki dio ukupnog kasnjenja, pa je prepolovljavanje logicki bolje od prosirivanja unutrasnje petlje.
-- c je ograniceno sa 2a poslije svake iteracije i a < 2^16, pa je 20 bitova dovoljno
-- za cuvanje vrijednosti cak i ukljucujuci pre-subtrakciju (c << 2) + 3.
--

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

LIBRARY work;
USE work.vj_pkg.ALL;

ENTITY vj_isqrt IS
    PORT (
        clk : IN STD_LOGIC;
        rst : IN STD_LOGIC;
        start : IN STD_LOGIC; -- one-cycle impuls
        din : IN unsigned(31 DOWNTO 0);
        dout : OUT unsigned(VNF_W - 1 DOWNTO 0);
        busy : OUT STD_LOGIC;
        done : OUT STD_LOGIC -- one-cycle impuls
    );
END ENTITY vj_isqrt;

ARCHITECTURE rtl OF vj_isqrt IS

    CONSTANT C_W : NATURAL := 20;

    SIGNAL val : unsigned(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL a : unsigned(VNF_W - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL c : unsigned(C_W - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL iter : unsigned(3 DOWNTO 0) := (OTHERS => '0');
    SIGNAL run : STD_LOGIC := '0';

    -- jedna iteracija referencne petlje, kao cista funkcija tako da se foldovanjem
    -- dvije takve u ciklus dobija dvostruka primjena.
    PROCEDURE step (VARIABLE vv : INOUT unsigned(31 DOWNTO 0);
    VARIABLE aa : INOUT unsigned(VNF_W - 1 DOWNTO 0);
    VARIABLE cc : INOUT unsigned(C_W - 1 DOWNTO 0)) IS
    VARIABLE bb : unsigned(C_W - 1 DOWNTO 0);
BEGIN
    cc := shift_left(cc, 2) + resize(vv(31 DOWNTO 30), C_W);
    vv := shift_left(vv, 2);
    aa := shift_left(aa, 1);
    bb := shift_left(resize(aa, C_W), 1) + 1;
    IF cc >= bb THEN
        cc := cc - bb;
        aa := aa + 1;
    END IF;
END PROCEDURE;

BEGIN

busy <= run;

PROCESS (clk)
    VARIABLE vv : unsigned(31 DOWNTO 0);
    VARIABLE aa : unsigned(VNF_W - 1 DOWNTO 0);
    VARIABLE cc : unsigned(C_W - 1 DOWNTO 0);
BEGIN
    IF rising_edge(clk) THEN
        done <= '0';

        IF rst = '1' THEN
            run <= '0';
            a <= (OTHERS => '0');
            c <= (OTHERS => '0');
            val <= (OTHERS => '0');
            iter <= (OTHERS => '0');
            dout <= (OTHERS => '0');

        ELSIF start = '1' THEN
            val <= din;
            a <= (OTHERS => '0');
            c <= (OTHERS => '0');
            iter <= (OTHERS => '0');
            run <= '1';

        ELSIF run = '1' THEN
            vv := val;
            aa := a;
            cc := c;
            step(vv, aa, cc); -- dvije referencne iteracije
            step(vv, aa, cc); -- po taktu
            val <= vv;
            a <= aa;
            c <= cc;

            IF iter = 7 THEN
                run <= '0';
                dout <= aa;
                done <= '1';
            ELSE
                iter <= iter + 1;
            END IF;
        END IF;
    END IF;
END PROCESS;

END ARCHITECTURE rtl;