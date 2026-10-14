--
-- vj_cascade_v1_0_S00_AXI.vhd
-- AXI4-Lite registarski fajl za Viola-Jones detektor lica, sa
-- instanciranjem jezgra i prolaskom kroz BRAM_PORTA kojim upravlja AXI BRAM kontroler
-- Imamo dva interfejsa magistrale:
--
--   S00_AXI     AXI4-Lite, kontrolni i statusni registri(ovaj fajl)
--   BRAM_PORTA  njim upravlja AXI BRAM kontroler, prenosi redove
--               integralne slike u row banke
--
-- Drugi interfejs postoji jer je azuriranje redova jedini prenos visokog opterecenja u sistemu
-- od priblizno 1.06 M rijeci za detekciju kompletne slike, koji
-- AXI BRAM Controller obavlja u burstovima od priblizno jedne rijeci po taktu,
-- dok bi pojedinacni AXI4-Lite upisi trajali oko deset puta duze.
--
-- Registarska mapa (byte offseti u odnosu na S00_AXI baznu adresu):
--
--   0x00  CTRL       RW   b0 RESET (self-clearing)
--                         b1 START (self-clearing)
--                         b2 MODE   0 = jedan prozor, 1 = x sweep
--                         b4 DONE   podesava hardware, write-1-to-clear
--   0x04  X_START    RW   prozor x (Mod A) / prvi x (Mod B)
--   0x08  WIDTH      RW   sz.width trenutne skale.Zadrzan zbog kompatibilnosti sa VP,ali je nepotreban datapathu,
--                         jer smo row bankingom izbacili mnozenje.
--   0x0C  RESULT     RO   Mod A: 1 = lice, -i = odbijeno na fazi i
--   0x10  X_LAST     RW   Mod B: posljednji x koji se testira
--   0x14  X_STEP     RW   Mod B: shiftStep
--   0x18  HIT_COUNT  RO   Mod B: broj detekcija u hit bufferu
--   0x1C  HIT_DATA   RO   Mod B: podaci u hit bufferu na HIT_ADDR
--   0x20  ROW_BASE   RW   rotacija 25 row banaka integralne slike, 0..24
--   0x24  STATUS     RO   b0 BUSY
--   0x28  HIT_ADDR   RW   indeks u hit bufferu za HIT_DATA
--
-- Dva ogranicenja:
--   1. bram_clk_a mora biti isti takt kao s00_axi_aclk.Row banke su
--      taktovane AXI taktom i bram_clk_a namjerno nije iskoriscen;
--      kada bi BRAM port bio taktovan drugim taktom podaci ne bi bili dobri
--      a tesko bi bilo uociti problem.U block designu oba su taktovana taktom
--      FCLK_CLK0.
--   2. Softver ne smije pisati podatke o redovima dok je jezgro zauzeto.  Port A 
--      svake banke je dijeljen izmedju ovog write patha i jezgrovog col0 reada,
--      pod pretpostavkom da se ova dva nikada ne preklapaju.Redovi se uploaduju tek nakon DONE stanja,
--      nikada u toku izvrsavanja.
--
-- BRAM_PORTA adresni decode: adresna rijec = bram_addr_a(15 downto 2), gdje 
--   biti 13..9 biraju banku (0..24 integralna, 25 = kvadrirana red 0, 26 = kvadrirana red 23)
--   biti  8..0 biraju kolonu
--

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

LIBRARY work;
USE work.vj_pkg.ALL;

ENTITY vj_cascade_v1_0_S00_AXI IS
    GENERIC (
        ROM_INIT_FILE : STRING := "classifier_rom.mem";
        C_S_AXI_DATA_WIDTH : INTEGER := 32;
        C_S_AXI_ADDR_WIDTH : INTEGER := 6
    );
    PORT (
        --interrupt
        irq : OUT STD_LOGIC;

        --BRAM port A, od AXI BRAM kontrolera
        bram_clk_a : IN STD_LOGIC;
        bram_en_a : IN STD_LOGIC;
        bram_we_a : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
        bram_addr_a : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        bram_wrdata_a : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        bram_rddata_a : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);

        --AXI4-Lite slave
        S_AXI_ACLK : IN STD_LOGIC;
        S_AXI_ARESETN : IN STD_LOGIC;
        S_AXI_AWADDR : IN STD_LOGIC_VECTOR(C_S_AXI_ADDR_WIDTH - 1 DOWNTO 0);
        S_AXI_AWPROT : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
        S_AXI_AWVALID : IN STD_LOGIC;
        S_AXI_AWREADY : OUT STD_LOGIC;
        S_AXI_WDATA : IN STD_LOGIC_VECTOR(C_S_AXI_DATA_WIDTH - 1 DOWNTO 0);
        S_AXI_WSTRB : IN STD_LOGIC_VECTOR((C_S_AXI_DATA_WIDTH/8) - 1 DOWNTO 0);
        S_AXI_WVALID : IN STD_LOGIC;
        S_AXI_WREADY : OUT STD_LOGIC;
        S_AXI_BRESP : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
        S_AXI_BVALID : OUT STD_LOGIC;
        S_AXI_BREADY : IN STD_LOGIC;
        S_AXI_ARADDR : IN STD_LOGIC_VECTOR(C_S_AXI_ADDR_WIDTH - 1 DOWNTO 0);
        S_AXI_ARPROT : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
        S_AXI_ARVALID : IN STD_LOGIC;
        S_AXI_ARREADY : OUT STD_LOGIC;
        S_AXI_RDATA : OUT STD_LOGIC_VECTOR(C_S_AXI_DATA_WIDTH - 1 DOWNTO 0);
        S_AXI_RRESP : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
        S_AXI_RVALID : OUT STD_LOGIC;
        S_AXI_RREADY : IN STD_LOGIC
    );
END ENTITY vj_cascade_v1_0_S00_AXI;
ARCHITECTURE rtl OF vj_cascade_v1_0_S00_AXI IS

    -- AXI handshake
    SIGNAL awready_r : STD_LOGIC := '0';
    SIGNAL wready_r : STD_LOGIC := '0';
    SIGNAL bvalid_r : STD_LOGIC := '0';
    SIGNAL arready_r : STD_LOGIC := '0';
    SIGNAL rvalid_r : STD_LOGIC := '0';
    SIGNAL rdata_r : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL awaddr_r : STD_LOGIC_VECTOR(C_S_AXI_ADDR_WIDTH - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL araddr_r : STD_LOGIC_VECTOR(C_S_AXI_ADDR_WIDTH - 1 DOWNTO 0) := (OTHERS => '0');

    -- Registri
    SIGNAL reg_mode : STD_LOGIC := '0';
    SIGNAL reg_done : STD_LOGIC := '0';
    SIGNAL reg_x_start : unsigned(COL_W - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL reg_x_last : unsigned(COL_W - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL reg_x_step : unsigned(COL_W - 1 DOWNTO 0) := to_unsigned(1, COL_W);
    SIGNAL reg_width : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL reg_row_base : unsigned(ROW_W - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL reg_hit_addr : unsigned(HIT_AW - 1 DOWNTO 0) := (OTHERS => '0');

    SIGNAL soft_reset : STD_LOGIC := '0';
    SIGNAL start_p : STD_LOGIC := '0';

    -- Jezgro
    SIGNAL core_rst : STD_LOGIC;
    SIGNAL core_busy : STD_LOGIC;
    SIGNAL core_done : STD_LOGIC;
    SIGNAL core_result : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL core_hit_cnt : STD_LOGIC_VECTOR(HIT_AW DOWNTO 0);
    SIGNAL core_hit_dat : STD_LOGIC_VECTOR(COL_W - 1 DOWNTO 0);

    SIGNAL ps_en : STD_LOGIC;
    SIGNAL ps_we : STD_LOGIC;
    SIGNAL ps_adr : STD_LOGIC_VECTOR(PS_AW - 1 DOWNTO 0);

    SIGNAL wr_en : STD_LOGIC;
    SIGNAL rd_en : STD_LOGIC;

BEGIN

    --
    -- AXI4-Lite write kanal
    --
    S_AXI_AWREADY <= awready_r;
    S_AXI_WREADY <= wready_r;
    S_AXI_BVALID <= bvalid_r;
    S_AXI_BRESP <= "00";

    wr_en <= awready_r AND S_AXI_AWVALID AND wready_r AND S_AXI_WVALID;

    write_ch : PROCESS (S_AXI_ACLK)
    BEGIN
        IF rising_edge(S_AXI_ACLK) THEN
            IF S_AXI_ARESETN = '0' THEN
                awready_r <= '0';
                wready_r <= '0';
                bvalid_r <= '0';
            ELSE
                IF awready_r = '0' AND S_AXI_AWVALID = '1' AND S_AXI_WVALID = '1' THEN
                    awready_r <= '1';
                    awaddr_r <= S_AXI_AWADDR;
                ELSE
                    awready_r <= '0';
                END IF;

                IF wready_r = '0' AND S_AXI_WVALID = '1' AND S_AXI_AWVALID = '1' THEN
                    wready_r <= '1';
                ELSE
                    wready_r <= '0';
                END IF;

                IF wr_en = '1' THEN
                    bvalid_r <= '1';
                ELSIF S_AXI_BREADY = '1' AND bvalid_r = '1' THEN
                    bvalid_r <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS;

    --
    -- Registarski writeovi
    --
    reg_write : PROCESS (S_AXI_ACLK)
    BEGIN
        IF rising_edge(S_AXI_ACLK) THEN
            -- START i RESET su one-cycle impulsi
            start_p <= '0';
            soft_reset <= '0';

            IF S_AXI_ARESETN = '0' THEN
                reg_mode <= '0';
                reg_done <= '0';
                reg_x_start <= (OTHERS => '0');
                reg_x_last <= (OTHERS => '0');
                reg_x_step <= to_unsigned(1, COL_W);
                reg_width <= (OTHERS => '0');
                reg_row_base <= (OTHERS => '0');
                reg_hit_addr <= (OTHERS => '0');
            ELSE
                IF wr_en = '1' THEN
                    CASE awaddr_r(5 DOWNTO 2) IS
                        WHEN "0000" => -- CTRL
                            soft_reset <= S_AXI_WDATA(0);
                            start_p <= S_AXI_WDATA(1);
                            reg_mode <= S_AXI_WDATA(2);
                            IF S_AXI_WDATA(4) = '1' THEN -- write 1 to clear
                                reg_done <= '0';
                            END IF;
                        WHEN "0001" =>
                            reg_x_start <= unsigned(S_AXI_WDATA(COL_W - 1 DOWNTO 0));
                        WHEN "0010" =>
                            reg_width <= S_AXI_WDATA;
                        WHEN "0100" =>
                            reg_x_last <= unsigned(S_AXI_WDATA(COL_W - 1 DOWNTO 0));
                        WHEN "0101" =>
                            reg_x_step <= unsigned(S_AXI_WDATA(COL_W - 1 DOWNTO 0));
                        WHEN "1000" =>
                            reg_row_base <= unsigned(S_AXI_WDATA(ROW_W - 1 DOWNTO 0));
                        WHEN "1010" =>
                            reg_hit_addr <= unsigned(S_AXI_WDATA(HIT_AW - 1 DOWNTO 0));
                        WHEN OTHERS =>
                            NULL;
                    END CASE;
                END IF;

                -- Hardware setuje DONE; software ga clearuje.
                IF core_done = '1' THEN
                    reg_done <= '1';
                END IF;
            END IF;
        END IF;
    END PROCESS;

    --
    -- AXI4-Lite read kanal
    --
    S_AXI_ARREADY <= arready_r;
    S_AXI_RVALID <= rvalid_r;
    S_AXI_RDATA <= rdata_r;
    S_AXI_RRESP <= "00";

    rd_en <= arready_r AND S_AXI_ARVALID AND (NOT rvalid_r);

    read_ch : PROCESS (S_AXI_ACLK)
    BEGIN
        IF rising_edge(S_AXI_ACLK) THEN
            IF S_AXI_ARESETN = '0' THEN
                arready_r <= '0';
                rvalid_r <= '0';
                rdata_r <= (OTHERS => '0');
            ELSE
                IF arready_r = '0' AND S_AXI_ARVALID = '1' THEN
                    arready_r <= '1';
                    araddr_r <= S_AXI_ARADDR;
                ELSE
                    arready_r <= '0';
                END IF;

                IF rd_en = '1' THEN
                    rvalid_r <= '1';
                    rdata_r <= (OTHERS => '0');
                    CASE araddr_r(5 DOWNTO 2) IS
                        WHEN "0000" => -- CTRL
                            rdata_r(2) <= reg_mode;
                            rdata_r(4) <= reg_done;
                        WHEN "0001" =>
                            rdata_r(COL_W - 1 DOWNTO 0) <= STD_LOGIC_VECTOR(reg_x_start);
                        WHEN "0010" =>
                            rdata_r <= reg_width;
                        WHEN "0011" => -- RESULT
                            rdata_r <= core_result;
                        WHEN "0100" =>
                            rdata_r(COL_W - 1 DOWNTO 0) <= STD_LOGIC_VECTOR(reg_x_last);
                        WHEN "0101" =>
                            rdata_r(COL_W - 1 DOWNTO 0) <= STD_LOGIC_VECTOR(reg_x_step);
                        WHEN "0110" => -- HIT_COUNT
                            rdata_r(HIT_AW DOWNTO 0) <= core_hit_cnt;
                        WHEN "0111" => -- HIT_DATA
                            rdata_r(COL_W - 1 DOWNTO 0) <= core_hit_dat;
                        WHEN "1000" =>
                            rdata_r(ROW_W - 1 DOWNTO 0) <= STD_LOGIC_VECTOR(reg_row_base);
                        WHEN "1001" => -- STATUS
                            rdata_r(0) <= core_busy;
                        WHEN "1010" =>
                            rdata_r(HIT_AW - 1 DOWNTO 0) <= STD_LOGIC_VECTOR(reg_hit_addr);
                        WHEN OTHERS =>
                            NULL;
                    END CASE;
                ELSIF rvalid_r = '1' AND S_AXI_RREADY = '1' THEN
                    rvalid_r <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS;

    irq <= reg_done;

    --
    -- Dekodovanje za BRAM port A
    --
    -- PS ovdje samo vrsi upis,pa nema read-back muxa; row
    -- banke su write-only sa strane magistrale.
    -- bram_clk_a namjerno nije spojen (objasnjeno u zaglavlju)
    ps_en <= bram_en_a AND (bram_we_a(0) OR bram_we_a(1) OR bram_we_a(2) OR bram_we_a(3));
    ps_we <= '1';
    ps_adr <= bram_addr_a(PS_AW + 1 DOWNTO 2);
    bram_rddata_a <= (OTHERS => '0');

    --
    -- Jezgro
    --
    core_rst <= (NOT S_AXI_ARESETN) OR soft_reset;

    u_core : ENTITY work.vj_cascade_core
        GENERIC MAP(ROM_INIT_FILE => ROM_INIT_FILE)
        PORT MAP(
            clk => S_AXI_ACLK,
            rst => core_rst,
            start => start_p,
            mode_sweep => reg_mode,
            x_start => reg_x_start,
            x_last => reg_x_last,
            x_step => reg_x_step,
            row_base => reg_row_base,
            busy => core_busy,
            done => core_done,
            result => core_result,
            hit_count => core_hit_cnt,
            hit_rd_en => '1',
            hit_rd_addr => STD_LOGIC_VECTOR(reg_hit_addr),
            hit_rd_data => core_hit_dat,
            ps_en => ps_en,
            ps_we => ps_we,
            ps_addr => ps_adr,
            ps_din => bram_wrdata_a
        );

END ARCHITECTURE rtl;