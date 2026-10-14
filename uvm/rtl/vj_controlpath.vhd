--
-- vj_controlpath.vhd
--
-- Control path za Viola-Jones detektor lica.Sadrzi sve brojace
-- (stage index, classifier-within-stage, global classifier index, window x)
-- i pravi kontrolne signale koje datapath koristi. Ne sadrzi aritmetiku s podacima slike
-- Petlja po slabim klasifikatorima je sljedeca:
--   ST_R0 : kreiranje pravougaonika 0, racunanje t = tree_thresh * vnf,
--  prefetch ROM rijeci za sljedeci klasifikator
--   ST_R1 : kreiranje pravougaonika 1. 81% klasifikatora ima samo dva pravougaonika
--  pa je ovaj posljednji pa se prefetched rijec latchuje ovdje i vracamo se u ST_R0
--   ST_R2 : samo za 19% klasifikatora sa trecim pravougaonikom
-- Slabi klasifikator kosta dva ciklusa, tri ako ima treci pravougaonik.
-- Faze 0 i 1 uopste nemaju klasifikatore sa tri pravougaonika, i jako mali procenat prozora prodje fazu 1
-- prosjek je 2.015 ciklusa.
-- Aritmeticke faze imaju ustaljenu sekvencu: tag koji se prenosi sa
-- svakim citanjem pravougaonika govori kada treba resetovati akumulator za karakteristike i
-- kada je slabi klasifikator zavrsen.FSM mora samo da prestaje s obradom klasifatora na kraju faze
-- i da saceka da dp_pipe_busy padne prije testiranja praga faze testing 
--
-- Dva rezima rada:
--   mode_sweep = '0'  jedan prozor kao za VP, za mjerenje kasnjenja jednog prozora
--   mode_sweep = '1'  IP pomjera x od x_start do x_end samostalno i biljezi pogotke
--                     sto rezultuje time da je jedan red slike = 1 prekid
--

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

LIBRARY work;
USE work.vj_pkg.ALL;
USE work.vj_stage_pkg.ALL;

ENTITY vj_controlpath IS
    PORT (
        clk : IN STD_LOGIC;
        rst : IN STD_LOGIC;

        --komande / status
        start : IN STD_LOGIC; -- one-cycle impuls
        mode_sweep : IN STD_LOGIC;
        x_start : IN unsigned(COL_W - 1 DOWNTO 0);
        x_last : IN unsigned(COL_W - 1 DOWNTO 0);
        x_step : IN unsigned(COL_W - 1 DOWNTO 0);
        busy : OUT STD_LOGIC;
        done : OUT STD_LOGIC; -- one-cycle impuls

        -- u datapath
        x_pos : OUT unsigned(COL_W - 1 DOWNTO 0);

        ctl_pv_read : OUT STD_LOGIC;
        ctl_pv_capture : OUT STD_LOGIC;
        ctl_var_calc : OUT STD_LOGIC;
        ctl_var_mul : OUT STD_LOGIC;
        ctl_var_final : OUT STD_LOGIC;

        ctl_rom_en : OUT STD_LOGIC;
        ctl_rom_addr : OUT STD_LOGIC_VECTOR(CLS_AW - 1 DOWNTO 0);
        ctl_cls_latch : OUT STD_LOGIC;
        ctl_t_calc : OUT STD_LOGIC;

        ctl_rect_issue : OUT STD_LOGIC;
        ctl_rect_k : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
        ctl_rect_first : OUT STD_LOGIC;
        ctl_rect_last : OUT STD_LOGIC;

        ctl_stage_clr : OUT STD_LOGIC;
        ctl_stage_idx : OUT unsigned(4 DOWNTO 0);

        ctl_res_accept : OUT STD_LOGIC;
        ctl_res_reject : OUT STD_LOGIC;
        ctl_hit_push : OUT STD_LOGIC;
        hit_clear : OUT STD_LOGIC;

        -- iz datapatha
        dp_w2_en : IN STD_LOGIC;
        dp_vnf_ready : IN STD_LOGIC;
        dp_pipe_busy : IN STD_LOGIC;
        dp_stage_rej : IN STD_LOGIC
    );
END ENTITY vj_controlpath;
ARCHITECTURE rtl OF vj_controlpath IS

    TYPE state_t IS (
        ST_IDLE,
        ST_WIN_START,
        ST_PV_READ, ST_PV_W1, ST_PV_CAP,
        ST_VAR_CALC, ST_VAR_MUL, ST_VAR_FIN, ST_VAR_WAIT,
        ST_STAGE_INIT, ST_STAGE_LATCH,
        ST_R0, ST_R1, ST_R2,
        ST_DRAIN, ST_STAGE_EVAL,
        ST_REJECT, ST_ACCEPT,
        ST_WIN_END, ST_DONE
    );

    SIGNAL state : state_t := ST_IDLE;

    SIGNAL stage_i : unsigned(4 DOWNTO 0) := (OTHERS => '0'); -- 0..24
    SIGNAL cls_j : unsigned(7 DOWNTO 0) := (OTHERS => '0'); -- unutar faze
    SIGNAL n_cls : unsigned(7 DOWNTO 0) := (OTHERS => '0'); -- velicina faze
    SIGNAL haar : unsigned(CLS_AW - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL x_reg : unsigned(COL_W - 1 DOWNTO 0) := (OTHERS => '0');

    -- Kombinaciono, neregistrovano: ctl_rom_en se assertuje u istom ciklusu u kome je potrebna
    -- adresa, pa bi registrovana adresa unijela kasnjenje za jedan ciklus
    -- i fetchovala prethodni klasifikator.
    SIGNAL rom_addr_i : unsigned(CLS_AW - 1 DOWNTO 0);

    -- true kad je klasifikator koji je trenutno u obradi posljednji u svojoj fazi
    SIGNAL last_in_stage : BOOLEAN;

BEGIN

    x_pos <= x_reg;
    ctl_stage_idx <= stage_i;
    ctl_rom_addr <= STD_LOGIC_VECTOR(rom_addr_i);
    busy <= '0' WHEN state = ST_IDLE ELSE
        '1';

    last_in_stage <= (cls_j + 1 >= n_cls);

    -- ST_STAGE_INIT fetchuje prvi klasifikator faze; ST_R0 prefetchuje
    -- sljedeci tako da se on vec nalazi u ROM izlaznom registru kada se
    -- obradi posljednji pravougaonik trenutnog klasifikatora.
    rom_addr_i <= haar + 1 WHEN state = ST_R0 ELSE
        haar;

    --
    -- Dekodovanje kombinacionih izlaza
    --
    outputs : PROCESS (state, dp_w2_en)
    BEGIN
        ctl_pv_read <= '0';
        ctl_pv_capture <= '0';
        ctl_var_calc <= '0';
        ctl_var_mul <= '0';
        ctl_var_final <= '0';
        ctl_rom_en <= '0';
        ctl_cls_latch <= '0';
        ctl_t_calc <= '0';
        ctl_rect_issue <= '0';
        ctl_rect_k <= "00";
        ctl_rect_first <= '0';
        ctl_rect_last <= '0';
        ctl_stage_clr <= '0';
        ctl_res_accept <= '0';
        ctl_res_reject <= '0';
        ctl_hit_push <= '0';
        hit_clear <= '0';
        done <= '0';

        CASE state IS
            WHEN ST_WIN_START =>
                -- bafer sa hitovima se cisti tek na pocetku sweepa
                hit_clear <= '1';

            WHEN ST_PV_READ =>
                ctl_pv_read <= '1';

            WHEN ST_PV_CAP =>
                ctl_pv_capture <= '1';

            WHEN ST_VAR_CALC =>
                ctl_var_calc <= '1';

            WHEN ST_VAR_MUL =>
                ctl_var_mul <= '1';

            WHEN ST_VAR_FIN =>
                ctl_var_final <= '1';

            WHEN ST_STAGE_INIT =>
                ctl_stage_clr <= '1';
                ctl_rom_en <= '1'; -- fetching prvog klasifikatora faze
            WHEN ST_STAGE_LATCH =>
                ctl_cls_latch <= '1';

            WHEN ST_R0 =>
                ctl_rect_issue <= '1';
                ctl_rect_k <= "00";
                ctl_rect_first <= '1';
                ctl_rect_last <= '0'; -- svaki klasifikator ima najmanje 2 pravougaonika
                ctl_t_calc <= '1';
                ctl_rom_en <= '1'; -- prefetch sljedeceg klasifikatora

            WHEN ST_R1 =>
                ctl_rect_issue <= '1';
                ctl_rect_k <= "01";
                ctl_rect_first <= '0';
                IF dp_w2_en = '0' THEN
                    ctl_rect_last <= '1';
                    ctl_cls_latch <= '1'; -- uzimanje prefetchovane rijeci
                END IF;

            WHEN ST_R2 =>
                ctl_rect_issue <= '1';
                ctl_rect_k <= "10";
                ctl_rect_first <= '0';
                ctl_rect_last <= '1';
                ctl_cls_latch <= '1';

            WHEN ST_REJECT =>
                ctl_res_reject <= '1';

            WHEN ST_ACCEPT =>
                ctl_res_accept <= '1';
                ctl_hit_push <= '1';

            WHEN ST_DONE =>
                done <= '1';

            WHEN OTHERS =>
                NULL;
        END CASE;
    END PROCESS;

    --
    -- Registar stanja i brojaci
    --
    fsm : PROCESS (clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF rst = '1' THEN
                state <= ST_IDLE;
                stage_i <= (OTHERS => '0');
                cls_j <= (OTHERS => '0');
                n_cls <= (OTHERS => '0');
                haar <= (OTHERS => '0');
                x_reg <= (OTHERS => '0');
            ELSE
                CASE state IS

                    WHEN ST_IDLE =>
                        IF start = '1' THEN
                            x_reg <= x_start;
                            state <= ST_WIN_START;
                        END IF;

                    WHEN ST_WIN_START =>
                        -- novi prozor: restart kaskade
                        stage_i <= (OTHERS => '0');
                        cls_j <= (OTHERS => '0');
                        haar <= (OTHERS => '0');
                        state <= ST_PV_READ;

                        --
                        -- Normalizacija varijanse.Ocitanim coskovima trebaju dva
                        -- ciklusa da se pojave (BRAM output registar + registrovani
                        -- mux za coskove), odatle eksplicitni wait.
                        --
                    WHEN ST_PV_READ => state <= ST_PV_W1;
                    WHEN ST_PV_W1 => state <= ST_PV_CAP;
                    WHEN ST_PV_CAP => state <= ST_VAR_CALC;
                    WHEN ST_VAR_CALC => state <= ST_VAR_MUL;
                    WHEN ST_VAR_MUL => state <= ST_VAR_FIN;
                    WHEN ST_VAR_FIN => state <= ST_VAR_WAIT;

                    WHEN ST_VAR_WAIT =>
                        IF dp_vnf_ready = '1' THEN
                            state <= ST_STAGE_INIT;
                        END IF;

                        --
                        -- Faza kaskade
                        --
                    WHEN ST_STAGE_INIT =>
                        n_cls <= STAGE_CNT_ROM(to_integer(stage_i));
                        cls_j <= (OTHERS => '0');
                        state <= ST_STAGE_LATCH;

                    WHEN ST_STAGE_LATCH =>
                        state <= ST_R0;

                        --
                        -- Slabi klasifikator: dva takta, tri sa trecim pravougaonikom
                        --
                    WHEN ST_R0 =>
                        state <= ST_R1;

                    WHEN ST_R1 =>
                        IF dp_w2_en = '1' THEN
                            state <= ST_R2;
                        ELSE
                            haar <= haar + 1;
                            cls_j <= cls_j + 1;
                            IF last_in_stage THEN
                                state <= ST_DRAIN;
                            ELSE
                                state <= ST_R0;
                            END IF;
                        END IF;

                    WHEN ST_R2 =>
                        haar <= haar + 1;
                        cls_j <= cls_j + 1;
                        IF last_in_stage THEN
                            state <= ST_DRAIN;
                        ELSE
                            state <= ST_R0;
                        END IF;

                        --
                        -- Praznjenje pipelinea za aritmetiku prije testiranja praga faza
                        --
                    WHEN ST_DRAIN =>
                        IF dp_pipe_busy = '0' THEN
                            state <= ST_STAGE_EVAL;
                        END IF;

                    WHEN ST_STAGE_EVAL =>
                        IF dp_stage_rej = '1' THEN
                            state <= ST_REJECT;
                        ELSIF stage_i = NUM_STAGES - 1 THEN
                            state <= ST_ACCEPT;
                        ELSE
                            stage_i <= stage_i + 1;
                            state <= ST_STAGE_INIT;
                        END IF;

                    WHEN ST_REJECT => state <= ST_WIN_END;
                    WHEN ST_ACCEPT => state <= ST_WIN_END;

                        --
                        -- Naredni prozor ili kraj detekcije
                        --
                    WHEN ST_WIN_END =>
                        IF mode_sweep = '1' AND (x_reg + x_step) <= x_last THEN
                            x_reg <= x_reg + x_step;
                            stage_i <= (OTHERS => '0');
                            cls_j <= (OTHERS => '0');
                            haar <= (OTHERS => '0');
                            state <= ST_PV_READ;
                        ELSE
                            state <= ST_DONE;
                        END IF;

                    WHEN ST_DONE =>
                        state <= ST_IDLE;

                END CASE;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE rtl;