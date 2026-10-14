--
-- tb_vj_cascade_core.vhd
-- Self-checking testbench za Viola-Jones jezgro.
-- Za sve slucajeve testbench:
--   1. ucitava 25 redova integralne slike u banke 0..24 i dva reda kvadrirane integralne
--      slike u banke 25 i 26, kroz PS write port
--   2. pokrece sve prozore u modu A i poredi registar
--      rezultata s referencom
--   3. ponovo pokrece citav red u modu B ai provjerava da li
--      hit buffer sadrzi prozore prihvacene u referenci
--

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE STD.TEXTIO.ALL;

LIBRARY work;
USE work.vj_pkg.ALL;

ENTITY tb_vj_cascade_core IS
    GENERIC (
        VECTOR_FILE : STRING := "tb_vectors.txt";
        ROM_FILE : STRING := "classifier_rom.mem"
    );
END ENTITY tb_vj_cascade_core;

ARCHITECTURE sim OF tb_vj_cascade_core IS

    CONSTANT TCLK : TIME := 10 ns; -- 100 MHz
    CONSTANT NUM_STAGES_TB : NATURAL := 25;

    SIGNAL clk : STD_LOGIC := '0';
    SIGNAL rst : STD_LOGIC := '1';

    SIGNAL start : STD_LOGIC := '0';
    SIGNAL mode_sweep : STD_LOGIC := '0';
    SIGNAL x_start : unsigned(COL_W - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL x_last : unsigned(COL_W - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL x_step : unsigned(COL_W - 1 DOWNTO 0) := to_unsigned(1, COL_W);
    SIGNAL row_base : unsigned(ROW_W - 1 DOWNTO 0) := (OTHERS => '0');

    SIGNAL busy : STD_LOGIC;
    SIGNAL done : STD_LOGIC;
    SIGNAL result : STD_LOGIC_VECTOR(31 DOWNTO 0);

    SIGNAL hit_count : STD_LOGIC_VECTOR(HIT_AW DOWNTO 0);
    SIGNAL hit_rd_en : STD_LOGIC := '0';
    SIGNAL hit_rd_addr : STD_LOGIC_VECTOR(HIT_AW - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL hit_rd_data : STD_LOGIC_VECTOR(COL_W - 1 DOWNTO 0);

    SIGNAL ps_en : STD_LOGIC := '0';
    SIGNAL ps_we : STD_LOGIC := '0';
    SIGNAL ps_addr : STD_LOGIC_VECTOR(PS_AW - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL ps_din : STD_LOGIC_VECTOR(BANK_DW - 1 DOWNTO 0) := (OTHERS => '0');

    SIGNAL sim_done : BOOLEAN := false;

    -- racunanje kasnjenja
    SIGNAL cycle_count : NATURAL := 0;

BEGIN

    clk <= '0' WHEN sim_done ELSE
        NOT clk AFTER TCLK/2;

    cycle_counter : PROCESS (clk)
    BEGIN
        IF rising_edge(clk) THEN
            cycle_count <= cycle_count + 1;
        END IF;
    END PROCESS;

    dut : ENTITY work.vj_cascade_core
        GENERIC MAP(ROM_INIT_FILE => ROM_FILE)
        PORT MAP(
            clk => clk,
            rst => rst,
            start => start,
            mode_sweep => mode_sweep,
            x_start => x_start,
            x_last => x_last,
            x_step => x_step,
            row_base => row_base,
            busy => busy,
            done => done,
            result => result,
            hit_count => hit_count,
            hit_rd_en => hit_rd_en,
            hit_rd_addr => hit_rd_addr,
            hit_rd_data => hit_rd_data,
            ps_en => ps_en,
            ps_we => ps_we,
            ps_addr => ps_addr,
            ps_din => ps_din
        );

    stimulus : PROCESS

        CONSTANT MAX_WIN : NATURAL := 128;
        TYPE int_arr_t IS ARRAY (0 TO MAX_WIN - 1) OF INTEGER;

        FILE vf : text;
        VARIABLE l : line;

        VARIABLE n_cases, width, nwin : INTEGER;
        VARIABLE v, xv, ev : INTEGER;

        VARIABLE win_x : int_arr_t;
        VARIABLE win_exp : int_arr_t;

        VARIABLE errors : NATURAL := 0;
        VARIABLE checks : NATURAL := 0;
        VARIABLE accepts : NATURAL := 0;
        VARIABLE t0, t1 : NATURAL;
        VARIABLE lat_sum : NATURAL := 0;
        VARIABLE lat_max : NATURAL := 0;
        VARIABLE lat_min : NATURAL := NATURAL'high;
        VARIABLE exp_hits : NATURAL := 0;
        VARIABLE got : NATURAL := 0;
        VARIABLE idx : NATURAL := 0;
        -- kasnjenje zavisno od dubine kaskade sto odredjuje
        -- realni throughput: priblizno 81% prozora se zaustavlja na fazi 0
        TYPE lat_arr_t IS ARRAY (0 TO NUM_STAGES_TB) OF NATURAL;
        VARIABLE lat_by_depth : lat_arr_t := (OTHERS => 0);
        VARIABLE cnt_by_depth : lat_arr_t := (OTHERS => 0);
        VARIABLE depth : NATURAL;


        PROCEDURE ps_write (bank : NATURAL; col : NATURAL; val : INTEGER) IS
        BEGIN
            WAIT UNTIL rising_edge(clk);
            ps_en <= '1';
            ps_we <= '1';
            ps_addr <= STD_LOGIC_VECTOR(to_unsigned(bank, 5)) &
                STD_LOGIC_VECTOR(to_unsigned(col, BANK_AW));
            ps_din <= STD_LOGIC_VECTOR(to_signed(val, BANK_DW));
            WAIT UNTIL rising_edge(clk);
            ps_en <= '0';
            ps_we <= '0';
        END PROCEDURE;


        PROCEDURE run_window (x : NATURAL; cycles : OUT NATURAL) IS
            VARIABLE c0 : NATURAL;
        BEGIN
            WAIT UNTIL rising_edge(clk);
            mode_sweep <= '0';
            x_start <= to_unsigned(x, COL_W);
            x_last <= to_unsigned(x, COL_W);
            x_step <= to_unsigned(1, COL_W);
            WAIT UNTIL rising_edge(clk);
            c0 := cycle_count;
            start <= '1';
            WAIT UNTIL rising_edge(clk);
            start <= '0';
            LOOP
                WAIT UNTIL rising_edge(clk);
                EXIT WHEN done = '1';
            END LOOP;
            cycles := cycle_count - c0;
        END PROCEDURE;

        PROCEDURE run_sweep (x0 : NATURAL; xn : NATURAL; step : NATURAL) IS
        BEGIN
            WAIT UNTIL rising_edge(clk);
            mode_sweep <= '1';
            x_start <= to_unsigned(x0, COL_W);
            x_last <= to_unsigned(xn, COL_W);
            x_step <= to_unsigned(step, COL_W);
            WAIT UNTIL rising_edge(clk);
            start <= '1';
            WAIT UNTIL rising_edge(clk);
            start <= '0';
            LOOP
                WAIT UNTIL rising_edge(clk);
                EXIT WHEN done = '1';
            END LOOP;
        END PROCEDURE;

    BEGIN
        rst <= '1';
        FOR i IN 0 TO 9 LOOP WAIT UNTIL rising_edge(clk);
        END LOOP;
        rst <= '0';
        WAIT UNTIL rising_edge(clk);

        file_open(vf, VECTOR_FILE, read_mode);
        readline(vf, l);
        read(l, n_cases);

        REPORT "=== Viola-Jones cascade core: " & INTEGER'image(n_cases)
            & " test cases ===";

        FOR c IN 1 TO n_cases LOOP
            readline(vf, l);
            read(l, width);
            read(l, nwin);

            ASSERT nwin <= MAX_WIN
            REPORT "testbench MAX_WIN too small" SEVERITY failure;

            -- ucitavanje 25 redova integralne slike u banke 0..24 
            row_base <= (OTHERS => '0');
            FOR r IN 0 TO INT_ROWS - 1 LOOP
                FOR j IN 0 TO width - 1 LOOP
                    readline(vf, l);
                    read(l, v);
                    ps_write(r, j, v);
                END LOOP;
            END LOOP;

            -- kvadrirana integralna, logicki redovi 0 i 23
            FOR j IN 0 TO width - 1 LOOP
                readline(vf, l);
                read(l, v);
                ps_write(SQ0_BANK, j, v);
            END LOOP;
            FOR j IN 0 TO width - 1 LOOP
                readline(vf, l);
                read(l, v);
                ps_write(SQ23_BANK, j, v);
            END LOOP;

            -- citanje liste prozora
            FOR w IN 0 TO nwin - 1 LOOP
                readline(vf, l);
                read(l, xv);
                read(l, ev);
                win_x(w) := xv;
                win_exp(w) := ev;
            END LOOP;

            --
            -- Mod A: jedan prozor po pokretanju, kao VP.
            -- Tu se mjeri kasnjenje jednog prozora.
            --
            FOR w IN 0 TO nwin - 1 LOOP
                run_window(win_x(w), t1);
                checks := checks + 1;
                lat_sum := lat_sum + t1;
                IF t1 > lat_max THEN
                    lat_max := t1;
                END IF;
                IF t1 < lat_min THEN
                    lat_min := t1;
                END IF;

                IF to_integer(signed(result)) /= win_exp(w) THEN
                    errors := errors + 1;
                    REPORT "case " & INTEGER'image(c)
                        & " width " & INTEGER'image(width)
                        & " x=" & INTEGER'image(win_x(w))
                        & ": expected " & INTEGER'image(win_exp(w))
                        & ", got " & INTEGER'image(to_integer(signed(result)))
                        SEVERITY error;
                END IF;
                IF win_exp(w) = 1 THEN
                    accepts := accepts + 1;
                    depth := NUM_STAGES_TB;
                ELSE
                    depth := - win_exp(w);
                END IF;
                lat_by_depth(depth) := lat_by_depth(depth) + t1;
                cnt_by_depth(depth) := cnt_by_depth(depth) + 1;
            END LOOP;

            --
            -- Mod B: jezgro samostalno pomjera x i biljezi hitove.Provjerava se 
            -- da li hit buffer sadrzi tacno prihvacene prozore po redu.
            --
            exp_hits := 0;
            idx := 0;
            FOR w IN 0 TO nwin - 1 LOOP
                IF win_exp(w) = 1 THEN
                    exp_hits := exp_hits + 1;
                END IF;
            END LOOP;

            run_sweep(win_x(0), win_x(nwin - 1), win_x(1) - win_x(0));

            got := to_integer(unsigned(hit_count));
            IF got /= exp_hits THEN
                errors := errors + 1;
                REPORT "case " & INTEGER'image(c)
                    & " sweep: expected " & INTEGER'image(exp_hits)
                    & " hits, got " & INTEGER'image(got)
                    SEVERITY error;
            ELSE
                FOR w IN 0 TO nwin - 1 LOOP
                    IF win_exp(w) = 1 THEN
                        WAIT UNTIL rising_edge(clk);
                        hit_rd_en <= '1';
                        hit_rd_addr <= STD_LOGIC_VECTOR(to_unsigned(idx, HIT_AW));
                        WAIT UNTIL rising_edge(clk);
                        hit_rd_en <= '0';
                        WAIT UNTIL rising_edge(clk);
                        IF to_integer(unsigned(hit_rd_data)) /= win_x(w) THEN
                            errors := errors + 1;
                            REPORT "case " & INTEGER'image(c)
                                & " sweep hit " & INTEGER'image(idx)
                                & ": expected x=" & INTEGER'image(win_x(w))
                                & ", got x="
                                & INTEGER'image(to_integer(unsigned(hit_rd_data)))
                                SEVERITY error;
                        END IF;
                        idx := idx + 1;
                    END IF;
                END LOOP;
            END IF;
            checks := checks + 1;
            REPORT "case " & INTEGER'image(c) & " (width "
                & INTEGER'image(width) & ", " & INTEGER'image(nwin)
                & " windows, " & INTEGER'image(exp_hits) & " accepts): done";

        END LOOP;

        file_close(vf);

        ------------------------------------------------------------------
        REPORT "================ SUMMARY ================";
        REPORT "checks   : " & INTEGER'image(checks);
        REPORT "accepts  : " & INTEGER'image(accepts);
        REPORT "errors   : " & INTEGER'image(errors);
        REPORT "window latency (cycles): min " & INTEGER'image(lat_min)
            & "  max " & INTEGER'image(lat_max);
        REPORT "latency by cascade depth (stages evaluated - cycles):";
        FOR d IN 0 TO NUM_STAGES_TB LOOP
            IF cnt_by_depth(d) > 0 THEN
                REPORT "   rejected at stage " & INTEGER'image(d)
                    & " : " & INTEGER'image(lat_by_depth(d) / cnt_by_depth(d))
                    & " cycles  (" & INTEGER'image(cnt_by_depth(d))
                    & " windows)";
            END IF;
        END LOOP;
        IF errors = 0 THEN
            REPORT "RESULT : PASS";
                ELSE
                REPORT "RESULT: FAIL" SEVERITY error;
        END IF;
        REPORT "=========================================";

        sim_done <= true;
        WAIT;
    END PROCESS;

END ARCHITECTURE sim;