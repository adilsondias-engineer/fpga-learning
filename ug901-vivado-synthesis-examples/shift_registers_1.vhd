--  32-bit Shift Register
--  Rising edge clock
--  Active high clock enable
--  foor loop-based template
--  File: shift_registers_1.vhd

library ieee;
use ieee.std_logic_1164.all;
entity shift_registers_1 is
 generic(
  DEPTH : integer := 32
 );
 port(
  clk   : in  std_logic;
  clken : in  std_logic;
  SI    : in  std_logic;
  SO    : out std_logic
 );

end shift_registers_1;

architecture archi of shift_registers_1 is
 signal shreg : std_logic_vector(DEPTH - 1 downto 0);
begin
 process(clk)
 begin
  if rising_edge(clk) then
   if clken = '1' then
    for i in 0 to DEPTH - 2 loop
     shreg(i + 1) <= shreg(i);
    end loop;
    shreg(0) <= SI;
   end if;
  end if;
 end process;
 SO <= shreg(DEPTH - 1);
end archi;