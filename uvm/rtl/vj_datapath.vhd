--------------------------------------------------------------------------------
-- vj_datapath.vhd
-- Sve operacije cuvanja i aritmetike za Viola-Jones detektor lica.Sekvencira ih controlpath,
-- ovaj dio ne vrsi scheduling.
-- Struktura:
--
--   klasifikacioni ROM ---> unpack ---> adresna jedinica ---> bank array
--                            |                                 |
--                            v                                 v
--                    t = tt * vnf                   corner mux (registrovani)
--                            |                              |
--                            ----> tag pipeline --> rs = a-b-c+d
--                                                         |
--                                                    skaliranje tezina
--                                                    (-1 / <<1 / <<1 + x)
--                                                         |
--                                                    S akumulator
--                                                         |
--                                          sum = S<<12, poredjenje, alpha mux
--                                                         |
--                                                  stage_sum akumulator
--
-- Dva svojstva klasifikacionih podataka cine aritmetiku arhitekturno jeftinom:
-- svaka tezina se moze predstaviti kao 4096 * k gdje je k {-1, 2, 3}, pa se citava unutrasnja petlja
-- izvrsava na negaciji, pomjeranjima i sabiranjima, bez mnozenja
-- redovi i kolone pravougaonika su ograniceni 24x24 prozorom, pa se
-- "width * ry + rx" index referentnog modela pretvara u row-bank select
-- sa 9-bitnim sabiranjem kolone
--
-- Jedina preostala mnozenja su mean*mean i tree_thresh*vnf, oba se izvrsavaju
-- jednom po prozoru umjesto po slabom klasifikatoru.
--

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

LIBRARY work;
USE work.vj_pkg.ALL;
USE work.vj_stage_pkg.ALL;

ENTITY vj_datapath IS
    GENERIC (
        ROM_INIT_FILE : STRING := "classifier_rom.mem"
    );
    PORT (
        clk : IN STD_LOGIC;
        rst : IN STD_LOGIC;

        --PS write path u row banke
        ps_en : IN STD_LOGIC;
        ps_we : IN STD_LOGIC;
        ps_addr : IN STD_LOGIC_VECTOR(PS_AW - 1 DOWNTO 0);
        ps_din : IN STD_LOGIC_VECTOR(BANK_DW - 1 DOWNTO 0);

        -- kontrola
        x_pos : IN unsigned(COL_W - 1 DOWNTO 0);
        row_base : IN unsigned(ROW_W - 1 DOWNTO 0);

        ctl_pv_read : IN STD_LOGIC; -- izdavanje 8 window-corner citanja
        ctl_pv_capture : IN STD_LOGIC; -- latchovanje dva ciklusa kasnije
        ctl_var_calc : IN STD_LOGIC; -- mean, acc
        ctl_var_mul : IN STD_LOGIC; -- mean^2, acc*576
        ctl_var_final : IN STD_LOGIC; -- oduzimanje i "kick" kvadratnog korijena

        ctl_rom_en : IN STD_LOGIC;
        ctl_rom_addr : IN STD_LOGIC_VECTOR(CLS_AW - 1 DOWNTO 0);
        ctl_cls_latch : IN STD_LOGIC; -- cur_word <= rom_dout
        ctl_t_calc : IN STD_LOGIC; -- t <= tree_thresh * vnf

        ctl_rect_issue : IN STD_LOGIC;
        ctl_rect_k : IN STD_LOGIC_VECTOR(1 DOWNTO 0); -- 0,1,2
        ctl_rect_first : IN STD_LOGIC;
        ctl_rect_last : IN STD_LOGIC;

        ctl_stage_clr : IN STD_LOGIC; -- stage_sum <= 0
        ctl_stage_idx : IN unsigned(4 DOWNTO 0);

        ctl_res_accept : IN STD_LOGIC;
        ctl_res_reject : IN STD_LOGIC;
        ctl_hit_push : IN STD_LOGIC;

        --status
        dp_w2_en : OUT STD_LOGIC; -- trenutni klasifikator ima treci pravougaonik
        dp_vnf_ready : OUT STD_LOGIC; -- vnf validan od sljedeceg ciklusa
        dp_pipe_busy : OUT STD_LOGIC; -- rect pipeline nije ispraznjen
        dp_stage_rej : OUT STD_LOGIC; -- stage_sum*5 < thresh*2

        --rezultati
        result : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
        hit_clear : IN STD_LOGIC;
        hit_count : OUT STD_LOGIC_VECTOR(HIT_AW DOWNTO 0);
        hit_rd_en : IN STD_LOGIC;
        hit_rd_addr : IN STD_LOGIC_VECTOR(HIT_AW - 1 DOWNTO 0);
        hit_rd_data : OUT STD_LOGIC_VECTOR(COL_W - 1 DOWNTO 0)
    );
END ENTITY vj_datapath;
ARCHITECTURE rtl OF vj_datapath IS

    --
    -- Interfejs bank arraya
    --
    SIGNAL bk_rd_en : STD_LOGIC;
    SIGNAL bk_rd_sq : STD_LOGIC;
    SIGNAL bk_row_top : unsigned(ROW_W - 1 DOWNTO 0);
    SIGNAL bk_row_bot : unsigned(ROW_W - 1 DOWNTO 0);
    SIGNAL bk_col0 : unsigned(COL_W - 1 DOWNTO 0);
    SIGNAL bk_col1 : unsigned(COL_W - 1 DOWNTO 0);

    SIGNAL corner_a, corner_b, corner_c, corner_d : STD_LOGIC_VECTOR(BANK_DW - 1 DOWNTO 0);
    SIGNAL sq_a, sq_b, sq_c, sq_d : STD_LOGIC_VECTOR(BANK_DW - 1 DOWNTO 0);

    --
    -- Klasifikatorski ROM i otpakovani trenutni klasifikator
    --
    SIGNAL rom_dout : STD_LOGIC_VECTOR(CLS_DW - 1 DOWNTO 0);
    SIGNAL cur_word : STD_LOGIC_VECTOR(CLS_DW - 1 DOWNTO 0) := (OTHERS => '0');

    SIGNAL cur_r0, cur_r1, cur_r2 : rect_t;
    SIGNAL cur_w1_sel : STD_LOGIC;
    SIGNAL cur_w2_en : STD_LOGIC;
    SIGNAL cur_tt : signed(TT_W - 1 DOWNTO 0);
    SIGNAL cur_a1 : signed(ALPHA_W - 1 DOWNTO 0);
    SIGNAL cur_a2 : signed(ALPHA_W - 1 DOWNTO 0);

    --
    -- Normalizacija varijanse
    --
    SIGNAL p0, p1, p2, p3 : unsigned(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL q0, q1, q2, q3 : unsigned(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL mean_r : unsigned(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL acc_r : unsigned(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL mean_sq : unsigned(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL acc576 : unsigned(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL vnf : unsigned(VNF_W - 1 DOWNTO 0) := (OTHERS => '0');

    SIGNAL sqrt_start : STD_LOGIC := '0';
    SIGNAL sqrt_din : unsigned(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL sqrt_dout : unsigned(VNF_W - 1 DOWNTO 0);
    SIGNAL sqrt_busy : STD_LOGIC;
    SIGNAL sqrt_done_i : STD_LOGIC;
    SIGNAL vnf_ready_i : STD_LOGIC := '0';

    --
    -- Prag po klasifikatoru, racuna se jednom i prenosi kroz pipeline
    -- s pravougaonikom kojem pripada.
    --
    SIGNAL t_reg : signed(31 DOWNTO 0) := (OTHERS => '0');

    --
    -- Pipeline za pravougaonike.
    -- Tag putuje pri svakom citanju pravougaonika tako da aritmeticke faze ne
    -- trebaju vlastitu masinu stanja, prva resetuje akumulator karakteristika
    -- posljednja finalizuje slabi klasifikator
    --
    TYPE tag_t IS RECORD
        valid : STD_LOGIC;
        first : STD_LOGIC;
        last : STD_LOGIC;
        kcode : STD_LOGIC_VECTOR(1 DOWNTO 0);
        t : signed(31 DOWNTO 0);
        a1 : signed(ALPHA_W - 1 DOWNTO 0);
        a2 : signed(ALPHA_W - 1 DOWNTO 0);
    END RECORD;

    CONSTANT TAG_ZERO : tag_t := (
        valid => '0', first => '0', last => '0', kcode => "00",
        t => (OTHERS => '0'), a1 => (OTHERS => '0'), a2 => (OTHERS => '0'));

    SIGNAL tag_issue : tag_t;
    SIGNAL tag_d1, tag_d2, tag_d3, tag_d4 : tag_t := TAG_ZERO;

    SIGNAL rs_r : signed(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL s_acc : signed(31 DOWNTO 0) := (OTHERS => '0');

    SIGNAL stage_sum : signed(STAGE_SUM_W - 1 DOWNTO 0) := (OTHERS => '0');

    --
    -- Rezultati
    --
    SIGNAL result_r : signed(31 DOWNTO 0) := (OTHERS => '0');

    TYPE hit_ram_t IS ARRAY (0 TO HIT_DEPTH - 1) OF STD_LOGIC_VECTOR(COL_W - 1 DOWNTO 0);
    SIGNAL hit_ram : hit_ram_t := (OTHERS => (OTHERS => '0'));
    SIGNAL hit_wp : unsigned(HIT_AW DOWNTO 0) := (OTHERS => '0');

BEGIN

    --
    -- Memorije
    --
    u_banks : ENTITY work.vj_bank_array
        PORT MAP(
            clk => clk,
            ps_en => ps_en,
            ps_we => ps_we,
            ps_addr => ps_addr,
            ps_din => ps_din,
            rd_en => bk_rd_en,
            rd_sq => bk_rd_sq,
            row_top => bk_row_top,
            row_bot => bk_row_bot,
            row_base => row_base,
            col0 => bk_col0,
            col1 => bk_col1,
            corner_a => corner_a,
            corner_b => corner_b,
            corner_c => corner_c,
            corner_d => corner_d,
            sq_a => sq_a,
            sq_b => sq_b,
            sq_c => sq_c,
            sq_d => sq_d
        );

    u_rom : ENTITY work.vj_classifier_rom
        GENERIC MAP(INIT_FILE => ROM_INIT_FILE)
        PORT MAP(
            clk => clk,
            en => ctl_rom_en,
            addr => ctl_rom_addr,
            dout => rom_dout
        );

    u_sqrt : ENTITY work.vj_isqrt
        PORT MAP(
            clk => clk,
            rst => rst,
            start => sqrt_start,
            din => sqrt_din,
            dout => sqrt_dout,
            busy => sqrt_busy,
            done => sqrt_done_i
        );

    --
    -- Unpacking trenutnog klasifikatora
    --
    cur_r0 <= cls_rect(cur_word, 0);
    cur_r1 <= cls_rect(cur_word, 1);
    cur_r2 <= cls_rect(cur_word, 2);
    cur_w1_sel <= cls_w1_sel(cur_word);
    cur_w2_en <= cls_w2_en(cur_word);
    cur_tt <= cls_tree_thresh(cur_word);
    cur_a1 <= cls_alpha1(cur_word);
    cur_a2 <= cls_alpha2(cur_word);

    dp_w2_en <= cur_w2_en;

    --
    -- Adresna jedinica. Zbog ogranicenja polja pravougaonika 24x24 prozorom, the
    -- redovi biraju banku direktno a kolona postaje jedno 9-bitno sabiranje.
    --
    addr_mux : PROCESS (ctl_pv_read, ctl_rect_issue, ctl_rect_k,
        cur_r0, cur_r1, cur_r2, x_pos)
        VARIABLE r : rect_t;
    BEGIN
        IF ctl_pv_read = '1' THEN
            -- Cetiri coska 24x24 prozora: redovi 0 i 23,
            -- kolone x i x+23, u integralnim i kvadriranim integralnim slikama.
            bk_rd_en <= '1';
            bk_rd_sq <= '1';
            bk_row_top <= to_unsigned(0, ROW_W);
            bk_row_bot <= to_unsigned(WIN_SIZE - 1, ROW_W);
            bk_col0 <= x_pos;
            bk_col1 <= x_pos + to_unsigned(WIN_SIZE - 1, COL_W);
        ELSE
            CASE ctl_rect_k IS
                WHEN "00" => r := cur_r0;
                WHEN "01" => r := cur_r1;
                WHEN OTHERS => r := cur_r2;
            END CASE;
            bk_rd_en <= ctl_rect_issue;
            bk_rd_sq <= '0';
            bk_row_top <= r.y;
            bk_row_bot <= resize(r.y + r.h, ROW_W);
            bk_col0 <= resize(r.x, COL_W) + x_pos;
            bk_col1 <= resize(r.x, COL_W) + resize(r.w, COL_W) + x_pos;
        END IF;
    END PROCESS;

    --
    -- Variance normalisation factor (VNF)
    --   mean=p0 - p1 - p2 + p3
    --   vnf=(q0 - q1 - q2 + q3) * 576 - mean*mean
    --   vnf=(vnf/= 0) ? isqrt(vnf) : 1
    -- 576 = 2^9 + 2^6, kako bi cijena bila
    -- dva pomjeraca i sabirac umjesto mnozaca.
    --
    var_proc : PROCESS (clk)
        VARIABLE v : unsigned(31 DOWNTO 0);
    BEGIN
        IF rising_edge(clk) THEN
            sqrt_start <= '0';
            vnf_ready_i <= '0';

            IF rst = '1' THEN
                mean_r <= (OTHERS => '0');
                acc_r <= (OTHERS => '0');
                mean_sq <= (OTHERS => '0');
                acc576 <= (OTHERS => '0');
                vnf <= (OTHERS => '0');
            ELSE
                IF ctl_pv_capture = '1' THEN
                    p0 <= unsigned(corner_a);
                    p1 <= unsigned(corner_b);
                    p2 <= unsigned(corner_c);
                    p3 <= unsigned(corner_d);
                    q0 <= unsigned(sq_a);
                    q1 <= unsigned(sq_b);
                    q2 <= unsigned(sq_c);
                    q3 <= unsigned(sq_d);
                END IF;

                IF ctl_var_calc = '1' THEN
                    mean_r <= (p0 + p3) - (p1 + p2);
                    acc_r <= (q0 + q3) - (q1 + q2);
                END IF;

                -- Vlastiti ciklus: 32x32 mnozenje je najveca operacija u dizajnu
                -- i ne smije dijeliti takt sa oduzimanjem.
                IF ctl_var_mul = '1' THEN
                    mean_sq <= resize(mean_r * mean_r, 32);
                    acc576 <= shift_left(acc_r, 9) + shift_left(acc_r, 6);
                END IF;

                IF ctl_var_final = '1' THEN
                    v := acc576 - mean_sq;
                    IF v = 0 THEN
                        vnf <= to_unsigned(1, VNF_W);
                        vnf_ready_i <= '1';
                    ELSE
                        sqrt_din <= v;
                        sqrt_start <= '1';
                    END IF;
                END IF;

                IF sqrt_done_i = '1' THEN
                    vnf <= sqrt_dout;
                    vnf_ready_i <= '1';
                END IF;
            END IF;
        END IF;
    END PROCESS;

    -- High na jedan ciklus; vnf je validan u ciklusu nakon ovog.
    dp_vnf_ready <= vnf_ready_i;
    --
    -- Trenutni klasifikator i njegov prag
    --
    cls_proc : PROCESS (clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF rst = '1' THEN
                cur_word <= (OTHERS => '0');
                t_reg <= (OTHERS => '0');
            ELSE
                IF ctl_cls_latch = '1' THEN
                    cur_word <= rom_dout;
                END IF;
                IF ctl_t_calc = '1' THEN
                    -- t = tree_thresh * vnf
                    t_reg <= resize(cur_tt * signed('0' & STD_LOGIC_VECTOR(vnf)), 32);
                END IF;
            END IF;
        END IF;
    END PROCESS;

    --
    -- Generisanje tagova i pipeline
    --
    tag_gen : PROCESS (ctl_rect_issue, ctl_rect_first, ctl_rect_last,
        ctl_rect_k, cur_w1_sel, t_reg, cur_a1, cur_a2)
    BEGIN
        tag_issue.valid <= ctl_rect_issue;
        tag_issue.first <= ctl_rect_first;
        tag_issue.last <= ctl_rect_last;
        tag_issue.t <= t_reg;
        tag_issue.a1 <= cur_a1;
        tag_issue.a2 <= cur_a2;

        CASE ctl_rect_k IS
            WHEN "00" =>
                -- weight[0] je -4096 za sve klasifikatore u kaskadi
                tag_issue.kcode <= KCODE_NEG1;
            WHEN "01" =>
                IF cur_w1_sel = '1' THEN
                    tag_issue.kcode <= KCODE_3; -- 12288
                ELSE
                    tag_issue.kcode <= KCODE_2; --  8192
                END IF;
            WHEN OTHERS =>
                tag_issue.kcode <= KCODE_2; -- weight[2] je uvijek 8192
        END CASE;
    END PROCESS;

    pipe : PROCESS (clk)
        VARIABLE rs : signed(31 DOWNTO 0);
        VARIABLE term : signed(31 DOWNTO 0);
        VARIABLE base : signed(31 DOWNTO 0);
        VARIABLE sumv : signed(31 DOWNTO 0);
        VARIABLE alph : signed(ALPHA_W - 1 DOWNTO 0);
    BEGIN
        IF rising_edge(clk) THEN
            IF rst = '1' THEN
                tag_d1 <= TAG_ZERO;
                tag_d2 <= TAG_ZERO;
                tag_d3 <= TAG_ZERO;
                tag_d4 <= TAG_ZERO;
                rs_r <= (OTHERS => '0');
                s_acc <= (OTHERS => '0');
                stage_sum <= (OTHERS => '0');
            ELSE
                -- Dvije faze kasnjenja kako bi se uvazio uticaj BRAM output registra i
                -- registrovanog 25:1 coskovnog muxa.
                tag_d1 <= tag_issue;
                tag_d2 <= tag_d1;

                -- razlika 4 coska. optimizovano kao (a+d)-(b+c) tako da je
                -- sabiracko stablo u dva nivoa umjesto u tri.
                rs := (signed(corner_a) + signed(corner_d))
                    - (signed(corner_b) + signed(corner_c));
                rs_r <= rs;
                tag_d3 <= tag_d2;

                -- primjena tezine i akumulacija.
                -- za k = {-1, 2, 3}: negacija, shift, ili shift-and-add.
                CASE tag_d3.kcode IS
                    WHEN KCODE_NEG1 => term := - rs_r;
                    WHEN KCODE_2 => term := shift_left(rs_r, 1);
                    WHEN OTHERS => term := shift_left(rs_r, 1) + rs_r;
                END CASE;

                IF tag_d3.first = '1' THEN
                    base := (OTHERS => '0');
                ELSE
                    base := s_acc;
                END IF;

                IF tag_d3.valid = '1' THEN
                    s_acc <= base + term;
                END IF;
                tag_d4 <= tag_d3;

                -- finalizacija slabog klasifikatora.
                IF ctl_stage_clr = '1' THEN
                    stage_sum <= (OTHERS => '0');
                ELSIF tag_d4.valid = '1' AND tag_d4.last = '1' THEN
                    -- izvlacenje zajednickog faktora 4096 iz svake tezine.
                    sumv := shift_left(s_acc, WEIGHT_SHIFT);
                    IF sumv >= tag_d4.t THEN
                        alph := tag_d4.a2;
                    ELSE
                        alph := tag_d4.a1;
                    END IF;
                    stage_sum <= stage_sum + resize(alph, STAGE_SUM_W);
                END IF;
            END IF;
        END IF;
    END PROCESS;

    dp_pipe_busy <= tag_issue.valid OR tag_d1.valid OR tag_d2.valid
        OR tag_d3.valid OR tag_d4.valid;

    --
    -- Prag faze: stage_sum * 5 < stage_thresh * 2
    -- (cjelobrojna forma faktora 0.4)
    --
    stage_cmp : PROCESS (stage_sum, ctl_stage_idx)
        VARIABLE lhs, rhs : signed(31 DOWNTO 0);
    BEGIN
        lhs := shift_left(resize(stage_sum, 32), 2) + resize(stage_sum, 32);
        rhs := shift_left(resize(STAGE_THRESH_ROM(to_integer(ctl_stage_idx)), 32), 1);
        IF lhs < rhs THEN
            dp_stage_rej <= '1';
        ELSE
            dp_stage_rej <= '0';
        END IF;
    END PROCESS;

    --
    -- Registar rezultata i bafer za pogotke
    --
    res_proc : PROCESS (clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF rst = '1' THEN
                result_r <= (OTHERS => '0');
                hit_wp <= (OTHERS => '0');
            ELSE
                IF ctl_res_accept = '1' THEN
                    result_r <= to_signed(1, 32);
                ELSIF ctl_res_reject = '1' THEN
                    -- odbijanje na fazi i vraca -i 
                    result_r <= to_signed(0, 32) - signed(resize(ctl_stage_idx, 32));
                END IF;

                IF hit_clear = '1' THEN
                    hit_wp <= (OTHERS => '0');
                ELSIF ctl_hit_push = '1' AND hit_wp(HIT_AW) = '0' THEN
                    hit_ram(to_integer(hit_wp(HIT_AW - 1 DOWNTO 0)))
                    <= STD_LOGIC_VECTOR(x_pos);
                    hit_wp <= hit_wp + 1;
                END IF;

                IF hit_rd_en = '1' THEN
                    hit_rd_data <= hit_ram(to_integer(unsigned(hit_rd_addr)));
                END IF;
            END IF;
        END IF;
    END PROCESS;

    result <= STD_LOGIC_VECTOR(result_r);
    hit_count <= STD_LOGIC_VECTOR(hit_wp);

END ARCHITECTURE rtl;