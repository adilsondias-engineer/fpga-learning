-- Tristate Description Using Combinatorial Process
-- Implemented with an OBUFT (IO buffer)
-- File: tristates_1.vhd
--
library ieee;
use ieee.std_logic_1164.all;

entity tristates_1 is
 port(
  T : in  std_logic;
  I : in  std_logic;
  O : out std_logic
 );
end tristates_1;

architecture archi of tristates_1 is
begin
 process(I, T)
 begin
  if (T = '0') then
   O <= I;
  else
   O <= 'Z';
  end if;
 end process;

end archi; 
