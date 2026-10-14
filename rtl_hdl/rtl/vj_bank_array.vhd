--
-- vj_bank_array.vhd
-- Memorija za integralnu sliku, organizovana u 27 true-dual-port banki:
--   banke 0-24 : redovi integralne slike.  Logicki red r postoji u fizickoj banci
--(r + row_base) mod 25, pa je pomjeranje y_bias povecanje brojaca
--umjesto kopiranja bloka od 24 reda
--banka 25: kvadrirana integralna slika, logicki red 0
--banka 26: kvadrirana integralna slika, logicki red 23
-- Redovi 0 i 23 integralne slike se jedini koriste (4 coska
-- iz updatePvalue),pa ostale ne moramo skladistiti.
-- Dual-port banke omogucavaju dostavu sve 4 vrijednosti coskova u jednom ciklusu
-- bez potrebe za duplikacijom memorije
-- Nacin koristenja portova:
--   port A : muxovan izmedju PS write patha i IPjevog col0 reada.
--  Nema arbitraze pa softver ne smije pisati dok se izvrsava rad jezgra
-- Zbog toga sto se koristi 25 od 60 tileova za banke, loop unrolling nije moguc
--   port B : IPjev col1 read
-- Read latency je jedan takt (BRAM output registar), a 25:1 output mux se
-- registruje odvojeno kako ne bi bio na aritmeticki kriticnoj putanji.
--

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

LIBRARY work;
USE work.vj_pkg.ALL;

--
-- Jedna banka je true dual port, write moguc samo na port A.
--
ENTITY vj_row_bank IS
    GENERIC (
        DEPTH : NATURAL := BANK_DEPTH;
        AW : NATURAL := BANK_AW;
        DW : NATURAL := BANK_DW
    );
    PORT (
        clk : IN STD_LOGIC;
        -- port A: write ili read
        en_a : IN STD_LOGIC;
        we_a : IN STD_LOGIC;
        addr_a : IN STD_LOGIC_VECTOR(AW - 1 DOWNTO 0);
        din_a : IN STD_LOGIC_VECTOR(DW - 1 DOWNTO 0);
        dout_a : OUT STD_LOGIC_VECTOR(DW - 1 DOWNTO 0);
        -- port B: read only
        en_b : IN STD_LOGIC;
        addr_b : IN STD_LOGIC_VECTOR(AW - 1 DOWNTO 0);
        dout_b : OUT STD_LOGIC_VECTOR(DW - 1 DOWNTO 0)
    );
END ENTITY vj_row_bank;

ARCHITECTURE rtl OF vj_row_bank IS
    TYPE ram_t IS ARRAY (0 TO DEPTH - 1) OF STD_LOGIC_VECTOR(DW - 1 DOWNTO 0);
    SIGNAL ram : ram_t := (OTHERS => (OTHERS => '0'));


    ATTRIBUTE ram_style : STRING;
    ATTRIBUTE ram_style OF ram : SIGNAL IS "block";
BEGIN

    port_a : PROCESS (clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF en_a = '1' THEN
                IF we_a = '1' THEN
                    ram(to_integer(unsigned(addr_a))) <= din_a;
                END IF;
                dout_a <= ram(to_integer(unsigned(addr_a)));
            END IF;
        END IF;
    END PROCESS;

    port_b : PROCESS (clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF en_b = '1' THEN
                dout_b <= ram(to_integer(unsigned(addr_b)));
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE rtl;
--
-- Niz od 27 banaka sa rotacijom, read muxingom i dekodovanjem PS upisa.
--
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

LIBRARY work;
USE work.vj_pkg.ALL;

ENTITY vj_bank_array IS
    PORT (
        clk : IN STD_LOGIC;

        --PS write path (iz AXI BRAM  kontrolera)
        ps_en : IN STD_LOGIC;
        ps_we : IN STD_LOGIC;
        ps_addr : IN STD_LOGIC_VECTOR(PS_AW - 1 DOWNTO 0); -- banka & kolona
        ps_din : IN STD_LOGIC_VECTOR(BANK_DW - 1 DOWNTO 0);

        --Core read path
        rd_en : IN STD_LOGIC; -- omogucavanje reada
        rd_sq : IN STD_LOGIC; -- read za dvije banke kvadrirane integralne slike
        row_top : IN unsigned(ROW_W - 1 DOWNTO 0); -- logicki red (ry)
        row_bot : IN unsigned(ROW_W - 1 DOWNTO 0); -- logicki red (ry+rh)
        row_base : IN unsigned(ROW_W - 1 DOWNTO 0); -- rotacija
        col0 : IN unsigned(COL_W - 1 DOWNTO 0);
        col1 : IN unsigned(COL_W - 1 DOWNTO 0);

        -- Registrovane vrijednosti coskova, validne dva takta nakon rd_en.
        corner_a : OUT STD_LOGIC_VECTOR(BANK_DW - 1 DOWNTO 0); -- (row_top, col0)
        corner_b : OUT STD_LOGIC_VECTOR(BANK_DW - 1 DOWNTO 0); -- (row_top, col1)
        corner_c : OUT STD_LOGIC_VECTOR(BANK_DW - 1 DOWNTO 0); -- (row_bot, col0)
        corner_d : OUT STD_LOGIC_VECTOR(BANK_DW - 1 DOWNTO 0); -- (row_bot, col1)
        sq_a : OUT STD_LOGIC_VECTOR(BANK_DW - 1 DOWNTO 0); -- (sq row 0,  col0)
        sq_b : OUT STD_LOGIC_VECTOR(BANK_DW - 1 DOWNTO 0); -- (sq row 0,  col1)
        sq_c : OUT STD_LOGIC_VECTOR(BANK_DW - 1 DOWNTO 0); -- (sq row 23, col0)
        sq_d : OUT STD_LOGIC_VECTOR(BANK_DW - 1 DOWNTO 0) -- (sq row 23, col1)
    );
END ENTITY vj_bank_array;

ARCHITECTURE rtl OF vj_bank_array IS

    SIGNAL en_a, we_a, en_b : bank_bit_arr_t;
    SIGNAL addr_a, addr_b : bank_addr_arr_t;
    SIGNAL dout_a, dout_b : bank_data_arr_t;

    SIGNAL bank_top, bank_bot : unsigned(ROW_W - 1 DOWNTO 0);
    -- Mux selectovi prate podatke ciklus kasnije, jer BRAM izlazni registar
    -- dobija vrijednost jedan takt nakon primjene adrese
    SIGNAL bank_top_d, bank_bot_d : unsigned(ROW_W - 1 DOWNTO 0);

    SIGNAL ps_bank : unsigned(4 DOWNTO 0);
    SIGNAL ps_col : STD_LOGIC_VECTOR(BANK_AW - 1 DOWNTO 0);

BEGIN

    -- Generisanje adrese
    bank_top <= rot_bank(row_top, row_base);
    bank_bot <= rot_bank(row_bot, row_base);

    ps_bank <= unsigned(ps_addr(PS_AW - 1 DOWNTO BANK_AW));
    ps_col <= ps_addr(BANK_AW - 1 DOWNTO 0);

    gen_banks : FOR i IN 0 TO N_BANKS - 1 GENERATE

        -- Port A sluzi kao PS write ili kao col0 read.
        en_a(i) <= '1' WHEN (ps_en = '1' AND to_integer(ps_bank) = i)
    ELSE
        '1' WHEN (rd_en = '1' AND i < N_INT_BANKS
        AND (to_integer(bank_top) = i OR to_integer(bank_bot) = i))
    ELSE
        '1' WHEN (rd_en = '1' AND rd_sq = '1'
        AND (i = SQ0_BANK OR i = SQ23_BANK))
    ELSE
        '0';

        we_a(i) <= '1' WHEN (ps_en = '1' AND ps_we = '1' AND to_integer(ps_bank) = i)
    ELSE
        '0';

        addr_a(i) <= ps_col WHEN (ps_en = '1' AND to_integer(ps_bank) = i)
    ELSE
        STD_LOGIC_VECTOR(col0);

        -- Port B je uvijek read-only i uzima col1.
        en_b(i) <= '1' WHEN (rd_en = '1' AND i < N_INT_BANKS
        AND (to_integer(bank_top) = i OR to_integer(bank_bot) = i))
    ELSE
        '1' WHEN (rd_en = '1' AND rd_sq = '1'
        AND (i = SQ0_BANK OR i = SQ23_BANK))
    ELSE
        '0';

        addr_b(i) <= STD_LOGIC_VECTOR(col1);

        u_bank : ENTITY work.vj_row_bank
            GENERIC MAP(DEPTH => BANK_DEPTH, AW => BANK_AW, DW => BANK_DW)
            PORT MAP(
                clk => clk,
                en_a => en_a(i),
                we_a => we_a(i),
                addr_a => addr_a(i),
                din_a => ps_din,
                dout_a => dout_a(i),
                en_b => en_b(i),
                addr_b => addr_b(i),
                dout_b => dout_b(i)
            );
    END GENERATE gen_banks;

    --
    -- Output muxing.
    -- 4 25:1 muxa biraju dvije aktivne banke integralne slike. Postavljaju se izmedju
	-- dvije registarske faze tako da samo kasnjenje muxa, bez aritmetike za coskove, bude na ovoj putanji
    -- Banke kvadriranih integralnih slika imaju fiksne indekse pa im mux nije potreban
    --
    sel_delay : PROCESS (clk)
    BEGIN
        IF rising_edge(clk) THEN
            bank_top_d <= bank_top;
            bank_bot_d <= bank_bot;
        END IF;
    END PROCESS;

    mux_reg : PROCESS (clk)
    BEGIN
        IF rising_edge(clk) THEN
            corner_a <= dout_a(to_integer(bank_top_d));
            corner_b <= dout_b(to_integer(bank_top_d));
            corner_c <= dout_a(to_integer(bank_bot_d));
            corner_d <= dout_b(to_integer(bank_bot_d));
            sq_a <= dout_a(SQ0_BANK);
            sq_b <= dout_b(SQ0_BANK);
            sq_c <= dout_a(SQ23_BANK);
            sq_d <= dout_b(SQ23_BANK);
        END IF;
    END PROCESS;

END ARCHITECTURE rtl;