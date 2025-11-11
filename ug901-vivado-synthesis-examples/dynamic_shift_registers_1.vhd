-- 32-bit dynamic shift register.
-- File:dynamic_shift_registers_1.vhd
-- 32-bit dynamic shift register.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

entity dynamic_shift_register_1 is
 generic(
  DEPTH     : integer := 32;
  SEL_WIDTH : integer := 5
 );
 port(
  CLK : in  std_logic;
  SI  : in  std_logic;
  CE  : in  std_logic;
  A   : in  std_logic_vector(SEL_WIDTH - 1 downto 0);
  DO  : out std_logic
 );

end dynamic_shift_register_1;

architecture rtl of dynamic_shift_register_1 is
 type SRL_ARRAY is array (DEPTH - 1 downto 0) of std_logic;

 signal SRL_SIG : SRL_ARRAY;

begin
 process(CLK)
 begin
  if rising_edge(CLK) then
   if CE = '1' then
    SRL_SIG <= SRL_SIG(DEPTH - 2 downto 0) & SI;
   end if;
  end if;
 end process;

 DO <= SRL_SIG(conv_integer(A));

end rtl;
