-- Variable and signal assignment in a process
-- variable_in_process.vhd
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity variable_in_process is
 port(
  A, B    : in  std_logic_vector(3 downto 0);
  ADD_SUB : in  std_logic;
  S       : out std_logic_vector(3 downto 0)
 );
end variable_in_process;

architecture archi of variable_in_process is
begin
 process(A, B, ADD_SUB)
  variable AUX : std_logic_vector(3 downto 0);
 begin
  if ADD_SUB = '1' then
   AUX := A + B;
  else
   AUX := A - B;
  end if;
  S <= AUX;
 end process;
end archi;