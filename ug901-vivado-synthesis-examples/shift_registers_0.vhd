--  32-bit Shift Register
--  Rising edge clock
--  Active high clock enable
--  Concatenation-based template
--  File: shift_registers_0.vhd

library ieee;
use ieee.std_logic_1164.all;
entity shift_registers_0 is
 generic(
  DEPTH : integer := 32
 );
 port(
  clk   : in  std_logic;
  clken : in  std_logic;
  SI    : in  std_logic;
  SO    : out std_logic
 );

end shift_registers_0;

architecture archi of shift_registers_0 is
 signal shreg : std_logic_vector(DEPTH - 1 downto 0);
begin
 process(clk)
 begin
  if rising_edge(clk) then
   if clken = '1' then
    shreg <= shreg(DEPTH - 2 downto 0) & SI;
   end if;
  end if;
 end process;
 SO <= shreg(DEPTH - 1);
end archi;