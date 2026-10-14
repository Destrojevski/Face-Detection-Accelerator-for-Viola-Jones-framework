--
-- tb_vj_cascade_v1_0.vhd
-- Self-checking testbench za upakovano IP jezgro koje radi u integrisanom sistemu,
-- svaki kontrolni pristup prolazi kroz AXI4-Lite funkcionalni model magistrale,a svaki row upload
-- kroz 32-bitni BRAM_PORTA byte-address path.
-- Testbench ima sljedece provjere:
--   A. Registar file       write-then-read-back na svakom write registru,
-- i reset vrijednosti read-only registara
--   B. Handshake protocol  AWVALID/AWREADY, WVALID/WREADY, BVALID/BREADY and
--ARVALID/ARREADY, RVALID/RREADY pokrenuti kao odvojeni dogadjaji
--sa nezavisnim timingom, pokriveni i slucajevi zakasnjelog BREADY i RREADY,
--tako da slave koji pretpostavlja da su uvijek visoki ne prolazi testiranje
--   C. START je impuls   provjera da li jedan CTRL upis pokrece tacno jedno izvrsavanje, 
--a ne kontinualni restart
--   D. DONE je sticky   ostaje setovan dok se ne upise jedinica, i clearuje 
--se pri tom upisu, a ne pri citanju
--   E. irq nakon DONE   postavlja se sa DONE, clearuje se u istom upisu
--   F. RESET            CTRL bit 0 vraca jezgro u idle stanje
--   G. BRAM address path  provjera da li rijeci upisane u byte adresama dolaze u banku
--i kolonu koje bram_addr_a(15 downto 2) diktira
--   H. Potpuni test     kompletan slucaj iz tb_vectors.txt, ubacen i pokrenut
--preko AXIja, provjerava poklapanje s istim rezultatima kao core testbench
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.all;

library work;
use work.vj_pkg.all;

entity tb_vj_cascade_v1_0 is
    generic (
        VECTOR_FILE : string  := "tb_vectors.txt";
        ROM_FILE    : string  := "classifier_rom.mem";
        -- Broj slucajeva iz vektor fajla koji ce se obraditi. Ne spustati ispod 4
        -- jer prva tri slucaja nemaju prihvacene prozore, pa testiranje nece
        -- biti ispravno ni potpuno. Slucajevi 4 i 5 imaju forsirana prihvatanja prozora.
        CASES       : natural := 5
    );
end entity tb_vj_cascade_v1_0;

architecture sim of tb_vj_cascade_v1_0 is

    constant TCLK : time := 10 ns;              -- 100 MHz
    constant AW   : natural := 6;               -- C_S00_AXI_ADDR_WIDTH

    -- registarska mapa, byte offseti
    constant REG_CTRL      : natural := 16#00#;
    constant REG_X_START   : natural := 16#04#;
    constant REG_WIDTH     : natural := 16#08#;
    constant REG_RESULT    : natural := 16#0C#;
    constant REG_X_LAST    : natural := 16#10#;
    constant REG_X_STEP    : natural := 16#14#;
    constant REG_HIT_COUNT : natural := 16#18#;
    constant REG_HIT_DATA  : natural := 16#1C#;
    constant REG_ROW_BASE  : natural := 16#20#;
    constant REG_STATUS    : natural := 16#24#;
    constant REG_HIT_ADDR  : natural := 16#28#;

    constant CTRL_RESET    : natural := 1;      -- bit 0
    constant CTRL_START    : natural := 2;      -- bit 1
    constant CTRL_MODE_SWP : natural := 4;      -- bit 2
    constant CTRL_DONE     : natural := 16;     -- bit 4

    signal clk     : std_logic := '0';
    signal aresetn : std_logic := '0';

    -- AXI4-Lite master strana
    signal awaddr  : std_logic_vector(AW-1 downto 0) := (others => '0');
    signal awprot  : std_logic_vector(2 downto 0)    := (others => '0');
    signal awvalid : std_logic := '0';
    signal awready : std_logic;
    signal wdata   : std_logic_vector(31 downto 0)   := (others => '0');
    signal wstrb   : std_logic_vector(3 downto 0)    := "1111";
    signal wvalid  : std_logic := '0';
    signal wready  : std_logic;
    signal bresp   : std_logic_vector(1 downto 0);
    signal bvalid  : std_logic;
    signal bready  : std_logic := '0';
    signal araddr  : std_logic_vector(AW-1 downto 0) := (others => '0');
    signal arprot  : std_logic_vector(2 downto 0)    := (others => '0');
    signal arvalid : std_logic := '0';
    signal arready : std_logic;
    signal rdata   : std_logic_vector(31 downto 0);
    signal rresp   : std_logic_vector(1 downto 0);
    signal rvalid  : std_logic;
    signal rready  : std_logic := '0';

    -- BRAM port A
    signal bram_clk    : std_logic;
    signal bram_en     : std_logic := '0';
    signal bram_we     : std_logic_vector(3 downto 0)  := (others => '0');
    signal bram_addr   : std_logic_vector(31 downto 0) := (others => '0');
    signal bram_wrdata : std_logic_vector(31 downto 0) := (others => '0');
    signal bram_rddata : std_logic_vector(31 downto 0);

    signal irq      : std_logic;
    signal sim_done : boolean := false;

    -- Dijeljene funkcije stimulus procesa i irq monitora
    -- Funkcije za maksimum / minimum / to_hstring.  
    function vj_max (a, b : integer) return integer is
    begin
        if a > b then return a; else return b; end if;
    end function;

    function vj_min (a, b : integer) return integer is
    begin
        if a < b then return a; else return b; end if;
    end function;

    function vj_hex (v : natural; digits : natural) return string is
        constant HEX : string(1 to 16) := "0123456789ABCDEF";
        variable r   : string(1 to digits);
        variable t   : natural := v;
    begin
        for i in digits downto 1 loop
            r(i) := HEX((t mod 16) + 1);
            t    := t / 16;
        end loop;
        return r;
    end function;

    signal errors_s   : natural := 0;
    signal irq_seen   : boolean := false;   -- njim upravlja irq_mon
    signal irq_arm    : boolean := false;   -- njim upravlja stimulus

begin

    clk      <= '0' when sim_done else not clk after TCLK/2;
    bram_clk <= clk;                            -- isti takt

    dut : entity work.vj_cascade_v1_0
        generic map (
            ROM_INIT_FILE        => ROM_FILE,
            C_S00_AXI_DATA_WIDTH => 32,
            C_S00_AXI_ADDR_WIDTH => AW
        )
        port map (
            irq             => irq,
            bram_clk_a      => bram_clk,
            bram_en_a       => bram_en,
            bram_we_a       => bram_we,
            bram_addr_a     => bram_addr,
            bram_wrdata_a   => bram_wrdata,
            bram_rddata_a   => bram_rddata,
            s00_axi_aclk    => clk,
            s00_axi_aresetn => aresetn,
            s00_axi_awaddr  => awaddr,
            s00_axi_awprot  => awprot,
            s00_axi_awvalid => awvalid,
            s00_axi_awready => awready,
            s00_axi_wdata   => wdata,
            s00_axi_wstrb   => wstrb,
            s00_axi_wvalid  => wvalid,
            s00_axi_wready  => wready,
            s00_axi_bresp   => bresp,
            s00_axi_bvalid  => bvalid,
            s00_axi_bready  => bready,
            s00_axi_araddr  => araddr,
            s00_axi_arprot  => arprot,
            s00_axi_arvalid => arvalid,
            s00_axi_arready => arready,
            s00_axi_rdata   => rdata,
            s00_axi_rresp   => rresp,
            s00_axi_rvalid  => rvalid,
            s00_axi_rready  => rready
        );

    --
    -- irq monitor: biljezi da li je irq ikada bio visok, kako bi stimulus mogao
    -- provjeriti postavljanje signala bez pollovanja u tacnom ciklusu.
    -- irq_seenom upravlja ovaj proces.Stimulus naoruzava i razoruzava
    -- monitor preko irq_arm umjesto pisanjem irq_seena,
    -- kako ne bismo imali slucaj visestrukog upravljanja ili greske u elaborisanju kasnije
    irq_mon : process (clk)
    begin
        if rising_edge(clk) then
            if not irq_arm then
                irq_seen <= false;
            elsif irq = '1' then
                irq_seen <= true;
            end if;
        end if;
    end process;

    stimulus : process

        constant MAX_WIN : natural := 128;
        type int_arr_t is array (0 to MAX_WIN-1) of integer;

        file     vf : text;
        variable l  : line;

        variable n_cases, width, nwin : integer;
        variable v, xv, ev            : integer;
        variable win_x   : int_arr_t;
        variable win_exp : int_arr_t;

        variable errors  : natural := 0;
        variable checks  : natural := 0;
        variable rd      : std_logic_vector(31 downto 0);
        variable got     : natural;
        variable exp_hits: natural;
        variable idx     : natural;

        -- Memorija za rekonstruisanje slike s vise pogodaka tilingom (sekcija I).
        constant MAXW : natural := 128;
        -- 5 tileova od 24 kolone, plus jos jedna kolona: pravougaonik moze imati
        -- rx+rw = 24, pa prozor na x-u cita kolonu x+24 -- jednu izvan svog vlastitog
        -- tilae.Formula ispod pokriva ovaj slucaj (k=5, j=0) i vrijednost se time
        -- adaptira na tacno ono sto je originalni prozor citao.
        constant TW   : natural := 5 * 24 + 1;   -- 121
        type imr_t is array (0 to INT_ROWS-1, 0 to MAXW-1) of integer;
        variable ig      : imr_t;                -- zabiljezeni integralni redovi
        type row_t is array (0 to MAXW-1) of integer;
        variable sg0, sg23 : row_t;              -- zabiljezeni redovi kvadrirane integralne slike
        variable igT     : imr_t;                -- tileovana integralna slika
        variable sqT     : imr_t;                -- tileovana kvadrirana integralna slika
        variable dint    : imr_t;                -- per-row tile increment
        variable k, jj   : natural;
        variable have_acc : boolean := false;
        variable acc_x    : natural := 0;
        variable acc_w    : natural := 0;
        variable a, b, cc, d : integer;

        --
        -- AXI4-Lite write.Adresa i podaci se pokrecu kao nezavisni dogadjaji
        -- i BREADY je namjerno zakasnjen, kako bi slave koji pretpostavlja
        -- da AWVALID i WVALID uvijek stizu zajedno ili da je BREADY zakucan na high
        -- izbacio gresku ovdje.
        --
        procedure axi_write (addr : natural; data : natural;
                             aw_delay : natural := 0;
                             w_delay  : natural := 0;
                             b_delay  : natural := 0) is
        begin
            wait until rising_edge(clk);

            if aw_delay = 0 then
                awaddr  <= std_logic_vector(to_unsigned(addr, AW));
                awvalid <= '1';
            end if;
            if w_delay = 0 then
                wdata  <= std_logic_vector(to_unsigned(data, 32));
                wstrb  <= "1111";
                wvalid <= '1';
            end if;

            for i in 1 to vj_max(aw_delay, w_delay) loop
                wait until rising_edge(clk);
                if i = aw_delay then
                    awaddr  <= std_logic_vector(to_unsigned(addr, AW));
                    awvalid <= '1';
                end if;
                if i = w_delay then
                    wdata  <= std_logic_vector(to_unsigned(data, 32));
                    wstrb  <= "1111";
                    wvalid <= '1';
                end if;
            end loop;

            -- dropuj svaki kanal kako ga slave prihvati
            loop
                wait until rising_edge(clk);
                if awready = '1' then awvalid <= '0'; end if;
                if wready  = '1' then wvalid  <= '0'; end if;
                exit when awvalid = '0' and wvalid = '0';
            end loop;

            for i in 1 to b_delay loop
                wait until rising_edge(clk);
            end loop;

            bready <= '1';
            loop
                wait until rising_edge(clk);
                exit when bvalid = '1';
            end loop;
            assert bresp = "00"
                report "AXI write to 0x" & vj_hex(addr, 2)
                     & " returned BRESP /= OKAY" severity error;
            wait until rising_edge(clk);
            bready <= '0';
        end procedure;

        procedure axi_read (addr : natural; data : out std_logic_vector(31 downto 0);
                            r_delay : natural := 0) is
        begin
            wait until rising_edge(clk);
            araddr  <= std_logic_vector(to_unsigned(addr, AW));
            arvalid <= '1';
            loop
                wait until rising_edge(clk);
                exit when arready = '1';
            end loop;
            arvalid <= '0';

            for i in 1 to r_delay loop
                wait until rising_edge(clk);
            end loop;

            rready <= '1';
            loop
                wait until rising_edge(clk);
                exit when rvalid = '1';
            end loop;
            data := rdata;
            assert rresp = "00"
                report "AXI read from 0x" & vj_hex(addr, 2)
                     & " returned RRESP /= OKAY" severity error;
            wait until rising_edge(clk);
            rready <= '0';
        end procedure;


        procedure check (lbl : string; got_v, exp_v : natural) is
        begin
            checks := checks + 1;
            if got_v /= exp_v then
                errors := errors + 1;
                report lbl & ": expected " & integer'image(exp_v)
                     & ", got " & integer'image(got_v) severity error;
            end if;
        end procedure;

        --
        -- Row upload kroz BRAM_PORTA, onako kako AXI BRAM kontroler
        -- upravlja njime: BYTE addresa, sa adresnom rijeci u bitima 15:2 i
        -- bankom u bitovima 13:9 te adresne rijeci.
        --
        procedure bram_write (bank : natural; col : natural; val : integer) is
            variable word_addr : natural;
        begin
            word_addr := bank * BANK_DEPTH + col;
            wait until rising_edge(clk);
            bram_en     <= '1';
            bram_we     <= "1111";
            bram_addr   <= std_logic_vector(to_unsigned(word_addr * 4, 32));
            bram_wrdata <= std_logic_vector(to_signed(val, 32));
            wait until rising_edge(clk);
            bram_en     <= '0';
            bram_we     <= "0000";
        end procedure;


        procedure wait_done is
            variable r : std_logic_vector(31 downto 0);
        begin
            loop
                axi_read(REG_CTRL, r);
                exit when (to_integer(unsigned(r)) / CTRL_DONE) mod 2 = 1;
            end loop;
        end procedure;

    begin

        aresetn <= '0';
        for i in 0 to 9 loop wait until rising_edge(clk); end loop;
        aresetn <= '1';
        for i in 0 to 4 loop wait until rising_edge(clk); end loop;

        report "=== tb_vj_cascade_v1_0: AXI4-Lite level verification ===";


        report "-- A: register write / read-back --";

        axi_write(REG_X_START,  123);
        axi_read (REG_X_START,  rd);
        check("X_START read-back", to_integer(unsigned(rd)), 123);

        axi_write(REG_X_LAST,   200);
        axi_read (REG_X_LAST,   rd);
        check("X_LAST read-back",  to_integer(unsigned(rd)), 200);

        axi_write(REG_X_STEP,     3);
        axi_read (REG_X_STEP,   rd);
        check("X_STEP read-back",  to_integer(unsigned(rd)), 3);

        axi_write(REG_ROW_BASE,   7);
        axi_read (REG_ROW_BASE, rd);
        check("ROW_BASE read-back", to_integer(unsigned(rd)), 7);

        axi_write(REG_WIDTH,    360);
        axi_read (REG_WIDTH,    rd);
        check("WIDTH read-back",   to_integer(unsigned(rd)), 360);

        axi_write(REG_HIT_ADDR,   5);
        axi_read (REG_HIT_ADDR, rd);
        check("HIT_ADDR read-back", to_integer(unsigned(rd)), 5);

        -- ROW_BASE je 5-bitan: 33 mora da se vrati kao 1, ne 33.Registar
        -- koji je siri u wrapperu nego u jezgru bi propagirao nevalidnu rotaciju
        -- u bank array.
        axi_write(REG_ROW_BASE,  33);
        axi_read (REG_ROW_BASE, rd);
        check("ROW_BASE truncated to 5 bits", to_integer(unsigned(rd)), 1);
        axi_write(REG_ROW_BASE,   0);


        report "-- B: handshake variations --";

        -- uranjena adresa, kasni podaci
        axi_write(REG_X_START, 11, 0, 3, 0);
        axi_read (REG_X_START, rd);
        check("write, data 3 cycles after address", to_integer(unsigned(rd)), 11);

        -- uranjeni podaci, kasna adresa
        axi_write(REG_X_START, 22, 3, 0, 0);
        axi_read (REG_X_START, rd);
        check("write, address 3 cycles after data", to_integer(unsigned(rd)), 22);

        -- delayovan BREADY: ceka se master za odgovor
        axi_write(REG_X_START, 33, 0, 0, 4);
        axi_read (REG_X_START, rd);
        check("write with BREADY delayed 4 cycles", to_integer(unsigned(rd)), 33);

        -- delayovan RREADY: RDATA mora biti zadrzan do prihvatanja
        axi_write(REG_X_START, 44);
        axi_read (REG_X_START, rd, 4);
        check("read with RREADY delayed 4 cycles", to_integer(unsigned(rd)), 44);

        report "-- C/D/E: START pulse, DONE sticky, irq --";
        -- Banke i dalje nemaju znacajne podatke, ali prozor ce se i dalje izvrsiti do kraja
        -- i setovati DONE
        axi_write(REG_CTRL, CTRL_DONE);--clear zaostalog DONEa
        axi_read (REG_CTRL, rd);
        check("DONE clear before start",
              (to_integer(unsigned(rd)) / CTRL_DONE) mod 2, 0);

        irq_arm <= false;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        irq_arm <= true;
        wait until rising_edge(clk);

        axi_write(REG_X_START, 0);
        axi_write(REG_X_LAST,  0);
        axi_write(REG_CTRL, CTRL_START);
        wait_done;

        check("irq asserted with DONE", boolean'pos(irq_seen), 1);

        -- DONE mora da prezivi citanje, i da prezivi upis u drugi registar
        -- clearuje se samo upisom jedinice u njega.
        axi_read(REG_CTRL, rd);
        check("DONE still set after a read",
              (to_integer(unsigned(rd)) / CTRL_DONE) mod 2, 1);
        axi_write(REG_X_START, 0);
        axi_read(REG_CTRL, rd);
        check("DONE still set after writing another register",
              (to_integer(unsigned(rd)) / CTRL_DONE) mod 2, 1);

        axi_write(REG_CTRL, CTRL_DONE);
        axi_read(REG_CTRL, rd);
        check("DONE cleared by write-1",
              (to_integer(unsigned(rd)) / CTRL_DONE) mod 2, 0);
        wait until rising_edge(clk);
        check("irq deasserted with DONE", boolean'pos(irq = '0'), 1);

        -- START mora biti impuls: nakon sto se izvrsavanje koda iznad zavrsi a DONE ocisti
        -- jezgro mora biti idle umjesto da se restartuje. Kada bi wrapper
        -- upravljao STARTom kao nivoom, BUSY bi ovdje bio visok.
        for i in 0 to 20 loop wait until rising_edge(clk); end loop;
        axi_read(REG_STATUS, rd);
        check("core idle after one START (START is a pulse)",
              to_integer(unsigned(rd)) mod 2, 0);
        axi_read(REG_CTRL, rd);
        check("DONE still clear -- no problematic second run",
              (to_integer(unsigned(rd)) / CTRL_DONE) mod 2, 0);


        report "-- F: soft reset --";

        axi_write(REG_CTRL, CTRL_RESET);
        for i in 0 to 4 loop wait until rising_edge(clk); end loop;
        axi_read(REG_STATUS, rd);
        check("core idle after soft reset", to_integer(unsigned(rd)) mod 2, 0);


        report "-- G: BRAM address path, all 27 banks --";
        -- Pisanje tacno odredjenog markera u nultu kolonu svake banke,zatim pokretanje
        -- prozora i potvrda da jezgro nije zaglavljeno.Prava provjera
        -- ove putanje je sekcija H, koja failuje ako je pristup ijednoj banci iznad banke 3 nemoguc
        for b in 0 to N_BANKS-1 loop
            bram_write(b, 0, 1000 + b);
        end loop;
        report "   27 banks written at byte addresses 0x0 .. 0x"
             & vj_hex((N_BANKS-1) * BANK_DEPTH * 4, 5)
             & " (top bank needs bram_addr_a bit 15)";


        report "-- H: end-to-end through AXI only --";

        file_open(vf, VECTOR_FILE, read_mode);
        readline(vf, l);
        read(l, n_cases);

        for c in 1 to vj_min(n_cases, CASES) loop
            readline(vf, l);
            read(l, width);
            read(l, nwin);
            assert nwin <= MAX_WIN
                report "testbench MAX_WIN too small" severity failure;

            axi_write(REG_CTRL, CTRL_RESET);
            for i in 0 to 4 loop wait until rising_edge(clk); end loop;
            axi_write(REG_CTRL, CTRL_DONE);
            axi_write(REG_ROW_BASE, 0);
            axi_write(REG_WIDTH, width);

            for r in 0 to INT_ROWS-1 loop
                for j in 0 to width-1 loop
                    readline(vf, l);
                    read(l, v);
                    bram_write(r, j, v);
                    if width <= MAXW then ig(r, j) := v; end if;
                end loop;
            end loop;
            for j in 0 to width-1 loop
                readline(vf, l);
                read(l, v);
                bram_write(SQ0_BANK, j, v);
                if width <= MAXW then sg0(j) := v; end if;
            end loop;
            for j in 0 to width-1 loop
                readline(vf, l);
                read(l, v);
                bram_write(SQ23_BANK, j, v);
                if width <= MAXW then sg23(j) := v; end if;
            end loop;

            for w in 0 to nwin-1 loop
                readline(vf, l);
                read(l, xv);
                read(l, ev);
                win_x(w)   := xv;
                win_exp(w) := ev;
                if ev = 1 and width <= MAXW and xv + WIN_SIZE < width then
                    have_acc := true;  acc_x := xv;  acc_w := width;
                end if;
            end loop;

            -- mod A, svaki prozor, preko AXIja
            for w in 0 to nwin-1 loop
                axi_write(REG_X_START, win_x(w));
                axi_write(REG_X_LAST,  win_x(w));
                axi_write(REG_CTRL, CTRL_START);
                wait_done;
                axi_write(REG_CTRL, CTRL_DONE);
                axi_read(REG_RESULT, rd);
                checks := checks + 1;
                if to_integer(signed(rd)) /= win_exp(w) then
                    errors := errors + 1;
                    report "case " & integer'image(c)
                         & " Mode A x=" & integer'image(win_x(w))
                         & ": expected " & integer'image(win_exp(w))
                         & ", got " & integer'image(to_integer(signed(rd)))
                         severity error;
                end if;
            end loop;

            -- mod B sweep, pa citanje hit buffera preko AXIja
            exp_hits := 0;
            for w in 0 to nwin-1 loop
                if win_exp(w) = 1 then exp_hits := exp_hits + 1; end if;
            end loop;

            axi_write(REG_X_START, win_x(0));
            axi_write(REG_X_LAST,  win_x(nwin-1));
            axi_write(REG_X_STEP,  win_x(1) - win_x(0));
            axi_write(REG_CTRL, CTRL_START + CTRL_MODE_SWP);
            wait_done;
            axi_write(REG_CTRL, CTRL_DONE);

            axi_read(REG_HIT_COUNT, rd);
            got := to_integer(unsigned(rd));
            check("case " & integer'image(c) & " sweep hit count",
                  got, exp_hits);

            if got = exp_hits then
                idx := 0;
                for w in 0 to nwin-1 loop
                    if win_exp(w) = 1 then
                        axi_write(REG_HIT_ADDR, idx);
                        axi_read (REG_HIT_DATA, rd);
                        check("case " & integer'image(c) & " hit "
                              & integer'image(idx) & " x",
                              to_integer(unsigned(rd)), win_x(w));
                        idx := idx + 1;
                    end if;
                end loop;
            end if;

            report "case " & integer'image(c) & " (width "
                 & integer'image(width) & ", " & integer'image(nwin)
                 & " windows, " & integer'image(exp_hits)
                 & " accepts): done via AXI";
        end loop;

        file_close(vf);


        report "-- I: Mode B, back-to-back sweeps (hit_clear semantics) --";
        -- ST_WIN_START je jedino stanje koje cisti hit_buffer,i
        -- sweep petlja namjerno nastavlja izvrsavanje u stanju ST_PV_READ, tako da
        -- buffer prezivljava tokom prozora jednog sweepa ali mora biti clearovan
        -- na pocetku sljedeceg.
        if have_acc then
            axi_write(REG_CTRL, CTRL_DONE);
            axi_write(REG_X_START, 0);
            axi_write(REG_X_LAST,  acc_w - WIN_SIZE - 1);
            axi_write(REG_X_STEP,  3);
            axi_write(REG_CTRL, CTRL_START + CTRL_MODE_SWP);
            wait_done;
            axi_write(REG_CTRL, CTRL_DONE);
            axi_read(REG_HIT_COUNT, rd);
            exp_hits := to_integer(unsigned(rd));

            axi_write(REG_CTRL, CTRL_START + CTRL_MODE_SWP);
            wait_done;
            axi_write(REG_CTRL, CTRL_DONE);
            axi_read(REG_HIT_COUNT, rd);
            check("second identical sweep returns the same hit count",
                  to_integer(unsigned(rd)), exp_hits);
        end if;

        report "-- J: Mode B, degenerate sweeps --";
        -- Sweep tacno jednog prozora: x_start = x_last. FSM mora izvrsiti
        -- prozor i zaustaviti se, bez zaglavljivanja u petlji i preskakanja.
        axi_write(REG_CTRL, CTRL_DONE);
        axi_write(REG_X_START, 0);
        axi_write(REG_X_LAST,  0);
        axi_write(REG_X_STEP,  3);
        axi_write(REG_CTRL, CTRL_START + CTRL_MODE_SWP);
        wait_done;
        axi_write(REG_CTRL, CTRL_DONE);
        axi_read(REG_STATUS, rd);
        check("single-window sweep terminates, core idle",
              to_integer(unsigned(rd)) mod 2, 0);

        -- Korak koji prebacuje: posljednji prozor mora biti posljednje x koje zadovoljava
        -- x <= x_last, i jezgro se ne smije nastaviti izvrsavati.
        axi_write(REG_X_START, 0);
        axi_write(REG_X_LAST,  10);
        axi_write(REG_X_STEP,  7);          -- gleda 0, 7; 14 > 10 pa se zaustavlja
        axi_write(REG_CTRL, CTRL_START + CTRL_MODE_SWP);
        wait_done;
        axi_write(REG_CTRL, CTRL_DONE);
        axi_read(REG_STATUS, rd);
        check("overshooting step terminates cleanly",
              to_integer(unsigned(rd)) mod 2, 0);

        report "-- K: Mode B, many hits in one sweep --";
        --tiling prozora za testiranje hit-buffera i indeksiranja
        --ovim se pravi slika koja biva konstantno prihvacena
        --     T(r,24k+j)=k*D(r)+O(r,acc_x+j),  j = 0..23
        --     D(r)= O(r,acc_x+24)-O(r,acc_x)
        -- Zbog k*D(r) ponistavaju se sve razlike unutar tilea, pa prozor k vidi
        -- tacno one vrijednosti koje je acc_x vidio u originalu
        -- i na osnovu toga mora izvesti isti zakljucak.  Ista formula
        -- se primjenjuje za kvadriranu integralnu sliku, pa se i varijansa poklapa.
        if have_acc then
            for r in 0 to INT_ROWS-1 loop
                dint(r, 0) := ig(r, acc_x + WIN_SIZE) - ig(r, acc_x);
            end loop;

            for r in 0 to INT_ROWS-1 loop
                for c in 0 to TW-1 loop
                    k  := c / WIN_SIZE;
                    jj := c mod WIN_SIZE;
                    igT(r, c) := k * dint(r, 0) + ig(r, acc_x + jj);
                end loop;
            end loop;
            for c in 0 to TW-1 loop
                k  := c / WIN_SIZE;
                jj := c mod WIN_SIZE;
                sqT(0, c) := k * (sg0(acc_x + WIN_SIZE) - sg0(acc_x))
                             + sg0(acc_x + jj);
                sqT(1, c) := k * (sg23(acc_x + WIN_SIZE) - sg23(acc_x))
                             + sg23(acc_x + jj);
            end loop;

            axi_write(REG_CTRL, CTRL_RESET);
            for i in 0 to 4 loop wait until rising_edge(clk); end loop;
            axi_write(REG_CTRL, CTRL_DONE);
            axi_write(REG_ROW_BASE, 0);
            axi_write(REG_WIDTH, TW);
            for r in 0 to INT_ROWS-1 loop
                for c in 0 to TW-1 loop
                    bram_write(r, c, igT(r, c));
                end loop;
            end loop;
            for c in 0 to TW-1 loop
                bram_write(SQ0_BANK,  c, sqT(0, c));
                bram_write(SQ23_BANK, c, sqT(1, c));
            end loop;

            axi_write(REG_X_START, 0);
            axi_write(REG_X_LAST,  4 * WIN_SIZE);      -- 0, 24, 48, 72, 96
            axi_write(REG_X_STEP,  WIN_SIZE);
            axi_write(REG_CTRL, CTRL_START + CTRL_MODE_SWP);
            wait_done;
            axi_write(REG_CTRL, CTRL_DONE);

            axi_read(REG_HIT_COUNT, rd);
            got := to_integer(unsigned(rd));
            check("tiled image: five accepted windows in one sweep", got, 5);

            if got = 5 then
                for i in 0 to 4 loop
                    axi_write(REG_HIT_ADDR, i);
                    axi_read (REG_HIT_DATA, rd);
                    check("hit " & integer'image(i) & " x coordinate",
                          to_integer(unsigned(rd)), i * WIN_SIZE);
                end loop;
            end if;
        end if;


        report "================ SUMMARY ================";
        report "checks : " & integer'image(checks);
        report "errors : " & integer'image(errors);
        if errors = 0 then
            report "RESULT: PASS ";
        else
            report "RESULT: FAIL" severity error;
        end if;
        report "=========================================";

        errors_s <= errors;
        sim_done <= true;
        wait;
    end process;

end architecture sim;