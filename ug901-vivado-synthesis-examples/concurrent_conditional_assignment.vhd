--
-- A concurrent conditional assignment (when-else)
--
-- File: concurrent_conditional_assignment.vhd
--
library ieee;
use ieee.std_logic_1164.all;

entity concurrent_conditional_assignment is
 generic(
  width : integer := 8);
 port(
  a, b, c, d : in  std_logic_vector(width - 1 downto 0);
  sel        : in  std_logic_vector(1 downto 0);
  T          : out std_logic_vector(width - 1 downto 0));
end concurrent_conditional_assignment;

architecture bhv of concurrent_conditional_assignment is
begin
 T <= a when sel = "00" else b when sel = "01" else c when sel = "10" else d;
end bhv;