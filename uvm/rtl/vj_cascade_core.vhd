--
-- vj_cascade_core.vhd
-- Control path + datapath. Jezgro za jedan testbench i target za 
-- AXI4-Lite wrapper wrapovanje;
--

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

LIBRARY work;
USE work.vj_pkg.ALL;

ENTITY vj_cascade_core IS
    GENERIC (
        ROM_INIT_FILE : STRING := "classifier_rom.mem"
    );
    PORT (
        clk : IN STD_LOGIC;
        rst : IN STD_LOGIC;

        -- upravljanje
        start : IN STD_LOGIC;
        mode_sweep : IN STD_LOGIC;
        x_start : IN unsigned(COL_W - 1 DOWNTO 0);
        x_last : IN unsigned(COL_W - 1 DOWNTO 0);
        x_step : IN unsigned(COL_W - 1 DOWNTO 0);
        row_base : IN unsigned(ROW_W - 1 DOWNTO 0);

        busy : OUT STD_LOGIC;
        done : OUT STD_LOGIC;
        result : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);

        -- citanje pogodaka/hitova za mod B
        hit_count : OUT STD_LOGIC_VECTOR(HIT_AW DOWNTO 0);
        hit_rd_en : IN STD_LOGIC;
        hit_rd_addr : IN STD_LOGIC_VECTOR(HIT_AW - 1 DOWNTO 0);
        hit_rd_data : OUT STD_LOGIC_VECTOR(COL_W - 1 DOWNTO 0);

        --PS write path u row banke
        ps_en : IN STD_LOGIC;
        ps_we : IN STD_LOGIC;
        ps_addr : IN STD_LOGIC_VECTOR(PS_AW - 1 DOWNTO 0);
        ps_din : IN STD_LOGIC_VECTOR(BANK_DW - 1 DOWNTO 0)
    );
END ENTITY vj_cascade_core;
ARCHITECTURE rtl OF vj_cascade_core IS

    SIGNAL x_pos : unsigned(COL_W - 1 DOWNTO 0);

    SIGNAL c_pv_read, c_pv_capture : STD_LOGIC;
    SIGNAL c_var_calc, c_var_mul, c_var_final : STD_LOGIC;
    SIGNAL c_rom_en, c_cls_latch, c_t_calc : STD_LOGIC;
    SIGNAL c_rom_addr : STD_LOGIC_VECTOR(CLS_AW - 1 DOWNTO 0);
    SIGNAL c_rect_issue, c_rect_first, c_rect_last : STD_LOGIC;
    SIGNAL c_rect_k : STD_LOGIC_VECTOR(1 DOWNTO 0);
    SIGNAL c_stage_clr : STD_LOGIC;
    SIGNAL c_stage_idx : unsigned(4 DOWNTO 0);
    SIGNAL c_res_accept, c_res_reject : STD_LOGIC;
    SIGNAL c_hit_push, c_hit_clear : STD_LOGIC;

    SIGNAL s_w2_en, s_vnf_ready, s_pipe_busy, s_stage_rej : STD_LOGIC;

BEGIN

    u_cp : ENTITY work.vj_controlpath
        PORT MAP(
            clk => clk,
            rst => rst,
            start => start,
            mode_sweep => mode_sweep,
            x_start => x_start,
            x_last => x_last,
            x_step => x_step,
            busy => busy,
            done => done,
            x_pos => x_pos,
            ctl_pv_read => c_pv_read,
            ctl_pv_capture => c_pv_capture,
            ctl_var_calc => c_var_calc,
            ctl_var_mul => c_var_mul,
            ctl_var_final => c_var_final,
            ctl_rom_en => c_rom_en,
            ctl_rom_addr => c_rom_addr,
            ctl_cls_latch => c_cls_latch,
            ctl_t_calc => c_t_calc,
            ctl_rect_issue => c_rect_issue,
            ctl_rect_k => c_rect_k,
            ctl_rect_first => c_rect_first,
            ctl_rect_last => c_rect_last,
            ctl_stage_clr => c_stage_clr,
            ctl_stage_idx => c_stage_idx,
            ctl_res_accept => c_res_accept,
            ctl_res_reject => c_res_reject,
            ctl_hit_push => c_hit_push,
            hit_clear => c_hit_clear,
            dp_w2_en => s_w2_en,
            dp_vnf_ready => s_vnf_ready,
            dp_pipe_busy => s_pipe_busy,
            dp_stage_rej => s_stage_rej
        );

    u_dp : ENTITY work.vj_datapath
        GENERIC MAP(ROM_INIT_FILE => ROM_INIT_FILE)
        PORT MAP(
            clk => clk,
            rst => rst,
            ps_en => ps_en,
            ps_we => ps_we,
            ps_addr => ps_addr,
            ps_din => ps_din,
            x_pos => x_pos,
            row_base => row_base,
            ctl_pv_read => c_pv_read,
            ctl_pv_capture => c_pv_capture,
            ctl_var_calc => c_var_calc,
            ctl_var_mul => c_var_mul,
            ctl_var_final => c_var_final,
            ctl_rom_en => c_rom_en,
            ctl_rom_addr => c_rom_addr,
            ctl_cls_latch => c_cls_latch,
            ctl_t_calc => c_t_calc,
            ctl_rect_issue => c_rect_issue,
            ctl_rect_k => c_rect_k,
            ctl_rect_first => c_rect_first,
            ctl_rect_last => c_rect_last,
            ctl_stage_clr => c_stage_clr,
            ctl_stage_idx => c_stage_idx,
            ctl_res_accept => c_res_accept,
            ctl_res_reject => c_res_reject,
            ctl_hit_push => c_hit_push,
            dp_w2_en => s_w2_en,
            dp_vnf_ready => s_vnf_ready,
            dp_pipe_busy => s_pipe_busy,
            dp_stage_rej => s_stage_rej,
            result => result,
            hit_clear => c_hit_clear,
            hit_count => hit_count,
            hit_rd_en => hit_rd_en,
            hit_rd_addr => hit_rd_addr,
            hit_rd_data => hit_rd_data
        );

END ARCHITECTURE rtl;