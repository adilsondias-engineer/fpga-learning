-- Concurrent selection assignment in VHDL
--
-- concurrent_selected_assignment.vhd
--
library ieee;
use ieee.std_logic_1164.all;

entity concurrent_selected_assignment is
 generic(
  width : integer := 8);
 port(
  a, b, c, d : in  std_logic_vector(width - 1 downto 0);
  sel        : in  std_logic_vector(1 downto 0);
  T          : out std_logic_vector(width - 1 downto 0));
end concurrent_selected_assignment;

architecture bhv of concurrent_selected_assignment is
begin
 with sel select T <=
  a when "00",
  b when "01",
  c when "10",
  d when others;
end bhv;
