--
-- Writing to a file. Implicit open/close
--/filewrite_implicitopen.vhd
--
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_arith.ALL;
use IEEE.STD_LOGIC_TEXTIO.all;
use STD.TEXTIO.all;

entity filewrite_implicitopen is
 generic(
  data_width : integer := 4
 );
 port(
  clk : in  std_logic;
  di  : in  std_logic_vector(data_width - 1 downto 0);
  do  : out std_logic_vector(data_width - 1 downto 0)
 );
end filewrite_implicitopen;

architecture behavioral of filewrite_implicitopen is
 file results : text open write_mode is "implicit.dat";
 constant base_const : std_logic_vector(data_width - 1 downto 0) := conv_std_logic_vector(3, data_width);
 constant new_const  : std_logic_vector(data_width - 1 downto 0) := base_const + "0100";
begin
 process(clk)
  variable txtline : LINE;
 begin
  write(txtline, string'("--------------------"));
  writeline(results, txtline);
  write(txtline, string'("Base Const: "));
  write(txtline, base_const);
  writeline(results, txtline);
  write(txtline, string'("New  Const: "));
  write(txtline, new_const);
  writeline(results, txtline);
  write(txtline, string'("--------------------"));
  writeline(results, txtline);
  if rising_edge(clk) then
   do <= di + new_const;
  end if;
 end process;

end behavioral;
