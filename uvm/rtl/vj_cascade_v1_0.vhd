--
-- vj_cascade_v1_0.vhd
-- IP top level za Viola-Jones kaskadni akcelerator.
-- Interfejsi:
--   S00_AXI   AXI4-Lite slave, kontrolni i statusni registri
--   BRAM_PORTA   BRAM port A, kojim upravlja AXI BRAM kontroler, prenosi
-- redove integralnih slika u row banke
--   irq   level-high interrupt, clearuje se upisom 1 u CTRL.DONE
--

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY vj_cascade_v1_0 IS
    GENERIC (
        ROM_INIT_FILE : STRING := "classifier_rom.mem";
        C_S00_AXI_DATA_WIDTH : INTEGER := 32;
        C_S00_AXI_ADDR_WIDTH : INTEGER := 6
    );
    PORT (
        irq : OUT STD_LOGIC;

        -- BRAM port A (ka AXI BRAM kontroleru)
        bram_clk_a : IN STD_LOGIC;
        bram_en_a : IN STD_LOGIC;
        bram_we_a : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
        bram_addr_a : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        bram_wrdata_a : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        bram_rddata_a : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);

        -- AXI4-Lite slave
        s00_axi_aclk : IN STD_LOGIC;
        s00_axi_aresetn : IN STD_LOGIC;
        s00_axi_awaddr : IN STD_LOGIC_VECTOR(C_S00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
        s00_axi_awprot : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
        s00_axi_awvalid : IN STD_LOGIC;
        s00_axi_awready : OUT STD_LOGIC;
        s00_axi_wdata : IN STD_LOGIC_VECTOR(C_S00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        s00_axi_wstrb : IN STD_LOGIC_VECTOR((C_S00_AXI_DATA_WIDTH/8) - 1 DOWNTO 0);
        s00_axi_wvalid : IN STD_LOGIC;
        s00_axi_wready : OUT STD_LOGIC;
        s00_axi_bresp : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
        s00_axi_bvalid : OUT STD_LOGIC;
        s00_axi_bready : IN STD_LOGIC;
        s00_axi_araddr : IN STD_LOGIC_VECTOR(C_S00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
        s00_axi_arprot : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
        s00_axi_arvalid : IN STD_LOGIC;
        s00_axi_arready : OUT STD_LOGIC;
        s00_axi_rdata : OUT STD_LOGIC_VECTOR(C_S00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        s00_axi_rresp : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
        s00_axi_rvalid : OUT STD_LOGIC;
        s00_axi_rready : IN STD_LOGIC
    );
END ENTITY vj_cascade_v1_0;

ARCHITECTURE arch_imp OF vj_cascade_v1_0 IS
BEGIN

    u_axi : ENTITY work.vj_cascade_v1_0_S00_AXI
        GENERIC MAP(
            ROM_INIT_FILE => ROM_INIT_FILE,
            C_S_AXI_DATA_WIDTH => C_S00_AXI_DATA_WIDTH,
            C_S_AXI_ADDR_WIDTH => C_S00_AXI_ADDR_WIDTH
        )
        PORT MAP(
            irq => irq,
            bram_clk_a => bram_clk_a,
            bram_en_a => bram_en_a,
            bram_we_a => bram_we_a,
            bram_addr_a => bram_addr_a,
            bram_wrdata_a => bram_wrdata_a,
            bram_rddata_a => bram_rddata_a,
            S_AXI_ACLK => s00_axi_aclk,
            S_AXI_ARESETN => s00_axi_aresetn,
            S_AXI_AWADDR => s00_axi_awaddr,
            S_AXI_AWPROT => s00_axi_awprot,
            S_AXI_AWVALID => s00_axi_awvalid,
            S_AXI_AWREADY => s00_axi_awready,
            S_AXI_WDATA => s00_axi_wdata,
            S_AXI_WSTRB => s00_axi_wstrb,
            S_AXI_WVALID => s00_axi_wvalid,
            S_AXI_WREADY => s00_axi_wready,
            S_AXI_BRESP => s00_axi_bresp,
            S_AXI_BVALID => s00_axi_bvalid,
            S_AXI_BREADY => s00_axi_bready,
            S_AXI_ARADDR => s00_axi_araddr,
            S_AXI_ARPROT => s00_axi_arprot,
            S_AXI_ARVALID => s00_axi_arvalid,
            S_AXI_ARREADY => s00_axi_arready,
            S_AXI_RDATA => s00_axi_rdata,
            S_AXI_RRESP => s00_axi_rresp,
            S_AXI_RVALID => s00_axi_rvalid,
            S_AXI_RREADY => s00_axi_rready
        );

END ARCHITECTURE arch_imp;