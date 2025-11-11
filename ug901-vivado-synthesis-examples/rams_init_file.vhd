-- Initializing Block RAM from external data file
-- File: rams_init_file.vhd

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity rams_init_file is
 port(
  clk  : in  std_logic;
  we   : in  std_logic;
  addr : in  std_logic_vector(5 downto 0);
  din  : in  std_logic_vector(31 downto 0);
  dout : out std_logic_vector(31 downto 0)
 );
end rams_init_file;

architecture syn of rams_init_file is
 type RamType is array (0 to 63) of bit_vector(31 downto 0);

 impure function InitRamFromFile(RamFileName : in string) return RamType is
  FILE RamFile : text is in RamFileName;
  variable RamFileLine : line;
  variable RAM         : RamType;
 begin
  for I in RamType'range loop
   readline(RamFile, RamFileLine);
   read(RamFileLine, RAM(I));
  end loop;
  return RAM;
 end function;

 signal RAM : RamType := InitRamFromFile("rams_init_file.data");
begin
 process(clk)
 begin
  if clk'event and clk = '1' then
   if we = '1' then
    RAM(to_integer(unsigned(addr))) <= to_bitvector(din);
   end if;
   dout <= to_stdlogicvector(RAM(to_integer(unsigned(addr))));
  end if;
 end process;

end syn;
