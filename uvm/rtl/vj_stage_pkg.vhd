-- Promjenljive koje opisuju faze kaskade. Dovoljno male za ROM LUT tabele, pa ne koristimo BRAM za njih.

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

PACKAGE vj_stage_pkg IS

    CONSTANT NUM_STAGES : NATURAL := 25;
    CONSTANT NUM_CLASSIFIERS : NATURAL := 2913;
    CONSTANT STAGE_CNT_BW : NATURAL := 8;-- max 211 klasifikatora
    CONSTANT STAGE_THRESH_BW : NATURAL := 13;-- opsega -1290 do -766
    TYPE stage_cnt_rom_t IS ARRAY (0 TO NUM_STAGES - 1) OF unsigned(STAGE_CNT_BW - 1 DOWNTO 0);
    TYPE stage_thresh_rom_t IS ARRAY (0 TO NUM_STAGES - 1) OF signed(STAGE_THRESH_BW - 1 DOWNTO 0);
    CONSTANT STAGE_CNT_ROM : stage_cnt_rom_t := (
        0 => to_unsigned(9, STAGE_CNT_BW),
        1 => to_unsigned(16, STAGE_CNT_BW),
        2 => to_unsigned(27, STAGE_CNT_BW),
        3 => to_unsigned(32, STAGE_CNT_BW),
        4 => to_unsigned(52, STAGE_CNT_BW),
        5 => to_unsigned(53, STAGE_CNT_BW),
        6 => to_unsigned(62, STAGE_CNT_BW),
        7 => to_unsigned(72, STAGE_CNT_BW),
        8 => to_unsigned(83, STAGE_CNT_BW),
        9 => to_unsigned(91, STAGE_CNT_BW),
        10 => to_unsigned(99, STAGE_CNT_BW),
        11 => to_unsigned(115, STAGE_CNT_BW),
        12 => to_unsigned(127, STAGE_CNT_BW),
        13 => to_unsigned(135, STAGE_CNT_BW),
        14 => to_unsigned(136, STAGE_CNT_BW),
        15 => to_unsigned(137, STAGE_CNT_BW),
        16 => to_unsigned(159, STAGE_CNT_BW),
        17 => to_unsigned(155, STAGE_CNT_BW),
        18 => to_unsigned(169, STAGE_CNT_BW),
        19 => to_unsigned(196, STAGE_CNT_BW),
        20 => to_unsigned(197, STAGE_CNT_BW),
        21 => to_unsigned(181, STAGE_CNT_BW),
        22 => to_unsigned(199, STAGE_CNT_BW),
        23 => to_unsigned(211, STAGE_CNT_BW),
        24 => to_unsigned(200, STAGE_CNT_BW)
    );

    CONSTANT STAGE_THRESH_ROM : stage_thresh_rom_t := (
        0 => to_signed(-1290, STAGE_THRESH_BW),
        1 => to_signed(-1275, STAGE_THRESH_BW),
        2 => to_signed(-1191, STAGE_THRESH_BW),
        3 => to_signed(-1140, STAGE_THRESH_BW),
        4 => to_signed(-1122, STAGE_THRESH_BW),
        5 => to_signed(-1057, STAGE_THRESH_BW),
        6 => to_signed(-1029, STAGE_THRESH_BW),
        7 => to_signed(-994, STAGE_THRESH_BW),
        8 => to_signed(-983, STAGE_THRESH_BW),
        9 => to_signed(-933, STAGE_THRESH_BW),
        10 => to_signed(-990, STAGE_THRESH_BW),
        11 => to_signed(-951, STAGE_THRESH_BW),
        12 => to_signed(-912, STAGE_THRESH_BW),
        13 => to_signed(-947, STAGE_THRESH_BW),
        14 => to_signed(-877, STAGE_THRESH_BW),
        15 => to_signed(-899, STAGE_THRESH_BW),
        16 => to_signed(-920, STAGE_THRESH_BW),
        17 => to_signed(-868, STAGE_THRESH_BW),
        18 => to_signed(-829, STAGE_THRESH_BW),
        19 => to_signed(-821, STAGE_THRESH_BW),
        20 => to_signed(-839, STAGE_THRESH_BW),
        21 => to_signed(-849, STAGE_THRESH_BW),
        22 => to_signed(-833, STAGE_THRESH_BW),
        23 => to_signed(-862, STAGE_THRESH_BW),
        24 => to_signed(-766, STAGE_THRESH_BW)
    );

END PACKAGE vj_stage_pkg;