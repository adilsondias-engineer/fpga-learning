--
-- Writing to a file
-- Explicit open/close with the VHDL'93 FILE_OPEN and FILE_CLOSE procedures
--
-- filewrite_explicitopen.vhd
--
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_arith.ALL;
use IEEE.STD_LOGIC_TEXTIO.all;
use STD.TEXTIO.all;

entity filewrite_explicitopen is
 generic(
  data_width : integer := 4
 );
 port(
  clk : in  std_logic;
  di  : in  std_logic_vector(data_width - 1 downto 0);
  do  : out std_logic_vector(data_width - 1 downto 0)
 );
end filewrite_explicitopen;

architecture behavioral of filewrite_explicitopen is
 file results : text;
 constant base_const : std_logic_vector(data_width - 1 downto 0) := conv_std_logic_vector(3, data_width);
 constant new_const  : std_logic_vector(data_width - 1 downto 0) := base_const + "0100";
begin
 process(clk)
  variable txtline     : line;
  variable file_status : file_open_status;
 begin
  file_open(file_status, results, "explicit.dat", write_mode);
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
  file_close(results);
  if rising_edge(clk) then
   do <= di + new_const;
  end if;
 end process;

end behavioral;
