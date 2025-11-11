--
-- Recursive component instantiation
--
-- instantiation_recursive.vhd
--
library ieee;
use ieee.std_logic_1164.all;
library unisim;
use unisim.vcomponents.all;

entity instantiation_recursive is
 generic(
  sh_st : integer := 4
 );
 port(
  CLK : in  std_logic;
  DI  : in  std_logic;
  DO  : out std_logic
 );
end entity instantiation_recursive;

architecture recursive of instantiation_recursive is
 component instantiation_recursive
  generic(
   sh_st : integer);
  port(
   CLK : in  std_logic;
   DI  : in  std_logic;
   DO  : out std_logic);
 end component;
 signal tmp : std_logic;
begin
 GEN_FD_LAST : if sh_st = 1 generate
  inst_fd : FD port map(D => DI, C => CLK, Q => DO);
 end generate;
 GEN_FD_INTERM : if sh_st /= 1 generate
  inst_fd : FD port map(D => DI, C => CLK, Q => tmp);
  inst_sstage : instantiation_recursive
   generic map(sh_st => sh_st - 1)
   port map(DI => tmp, CLK => CLK, DO => DO);
 end generate;
end recursive;
