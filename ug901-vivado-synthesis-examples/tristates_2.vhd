-- Tristate Description Using Concurrent Assignment
-- File: tristates_2.vhd
--
library ieee;
use ieee.std_logic_1164.all;

entity tristates_2 is
 port(
  T : in  std_logic;
  I : in  std_logic;
  O : out std_logic
 );
end tristates_2;

architecture archi of tristates_2 is
begin
 O <= I when (T = '0') else 'Z';
end archi;
