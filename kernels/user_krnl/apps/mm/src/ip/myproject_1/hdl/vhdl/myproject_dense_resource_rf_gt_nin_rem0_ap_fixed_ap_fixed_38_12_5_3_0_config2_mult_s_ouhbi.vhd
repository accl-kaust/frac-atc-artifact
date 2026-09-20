-- ==============================================================
-- Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2020.2 (64-bit)
-- Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
-- ==============================================================
library ieee; 
use ieee.std_logic_1164.all; 
use ieee.std_logic_unsigned.all;

entity myproject_dense_resource_rf_gt_nin_rem0_ap_fixed_ap_fixed_38_12_5_3_0_config2_mult_s_ouhbi_rom is 
    generic(
             DWIDTH     : integer := 3; 
             AWIDTH     : integer := 8; 
             MEM_SIZE    : integer := 216
    ); 
    port (
          addr0      : in std_logic_vector(AWIDTH-1 downto 0); 
          ce0       : in std_logic; 
          q0         : out std_logic_vector(DWIDTH-1 downto 0);
          clk       : in std_logic
    ); 
end entity; 


architecture rtl of myproject_dense_resource_rf_gt_nin_rem0_ap_fixed_ap_fixed_38_12_5_3_0_config2_mult_s_ouhbi_rom is 

signal addr0_tmp : std_logic_vector(AWIDTH-1 downto 0); 
type mem_array is array (0 to MEM_SIZE-1) of std_logic_vector (DWIDTH-1 downto 0); 
signal mem : mem_array := (
    0 to 26=> "000", 27 to 53=> "001", 54 to 80=> "010", 81 to 107=> "011", 108 to 134=> "100", 135 to 161=> "101", 
    162 to 188=> "110", 189 to 215=> "111" );


begin 


memory_access_guard_0: process (addr0) 
begin
      addr0_tmp <= addr0;
--synthesis translate_off
      if (CONV_INTEGER(addr0) > mem_size-1) then
           addr0_tmp <= (others => '0');
      else 
           addr0_tmp <= addr0;
      end if;
--synthesis translate_on
end process;

p_rom_access: process (clk)  
begin 
    if (clk'event and clk = '1') then
        if (ce0 = '1') then 
            q0 <= mem(CONV_INTEGER(addr0_tmp)); 
        end if;
    end if;
end process;

end rtl;

Library IEEE;
use IEEE.std_logic_1164.all;

entity myproject_dense_resource_rf_gt_nin_rem0_ap_fixed_ap_fixed_38_12_5_3_0_config2_mult_s_ouhbi is
    generic (
        DataWidth : INTEGER := 3;
        AddressRange : INTEGER := 216;
        AddressWidth : INTEGER := 8);
    port (
        reset : IN STD_LOGIC;
        clk : IN STD_LOGIC;
        address0 : IN STD_LOGIC_VECTOR(AddressWidth - 1 DOWNTO 0);
        ce0 : IN STD_LOGIC;
        q0 : OUT STD_LOGIC_VECTOR(DataWidth - 1 DOWNTO 0));
end entity;

architecture arch of myproject_dense_resource_rf_gt_nin_rem0_ap_fixed_ap_fixed_38_12_5_3_0_config2_mult_s_ouhbi is
    component myproject_dense_resource_rf_gt_nin_rem0_ap_fixed_ap_fixed_38_12_5_3_0_config2_mult_s_ouhbi_rom is
        port (
            clk : IN STD_LOGIC;
            addr0 : IN STD_LOGIC_VECTOR;
            ce0 : IN STD_LOGIC;
            q0 : OUT STD_LOGIC_VECTOR);
    end component;



begin
    myproject_dense_resource_rf_gt_nin_rem0_ap_fixed_ap_fixed_38_12_5_3_0_config2_mult_s_ouhbi_rom_U :  component myproject_dense_resource_rf_gt_nin_rem0_ap_fixed_ap_fixed_38_12_5_3_0_config2_mult_s_ouhbi_rom
    port map (
        clk => clk,
        addr0 => address0,
        ce0 => ce0,
        q0 => q0);

end architecture;


