--
-- Register initialization
--   Specifying initial contents at circuit powes-up
--   Specifying an operational set/reset
--
-- File: VHDL_Language_Support/initial/initial_1.vhd
--
library ieee;
use ieee.std_logic_1164.all;

entity initial_1 is
 Port(
  clk, rst : in  std_logic;
  din      : in  std_logic;
  dout     : out std_logic
  );
end initial_1;

architecture behavioral of initial_1 is
 signal arb_onebit : std_logic := '1'; -- power-up to vcc
begin
 process(clk)
 begin
  if (rising_edge(clk)) then
   if rst = '1' then           -- local synchronous reset
    arb_onebit <= '0';
   else
    arb_onebit <= din;
   end if;
  end if;
 end process;

 dout <= arb_onebit;

end behavioral;
