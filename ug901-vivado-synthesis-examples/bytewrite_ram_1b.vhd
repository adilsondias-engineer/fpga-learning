-- Single-Port BRAM with Byte Write Enable
--  Read-First mode
--  Single-process description
--  Compact description of the write with a for-loop statement
--  Column width and number of columns easily configurable
-- bytewrite_ram_1b.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
entity bytewrite_ram_1b is
 generic(
  SIZE       : integer := 1024;
  ADDR_WIDTH : integer := 10;
  COL_WIDTH  : integer := 8;
  NB_COL     : integer := 4);

 port(
  clk  : in  std_logic;
  we   : in  std_logic_vector(NB_COL - 1 downto 0);
  addr : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
  di   : in  std_logic_vector(NB_COL * COL_WIDTH - 1 downto 0);
  do   : out std_logic_vector(NB_COL * COL_WIDTH - 1 downto 0));

end bytewrite_ram_1b;
architecture behavioral of bytewrite_ram_1b is
 type ram_type is array (SIZE - 1 downto 0) of std_logic_vector(NB_COL * COL_WIDTH - 1 downto 0);
 signal RAM : ram_type := (others => (others => '0'));

begin
 process(clk)
 begin
  if rising_edge(clk) then
   do <= RAM(conv_integer(addr));
   for i in 0 to NB_COL - 1 loop
    if we(i) = '1' then
     RAM(conv_integer(addr))((i + 1) * COL_WIDTH - 1 downto i * COL_WIDTH) <= di((i + 1) * COL_WIDTH - 1 downto i * COL_WIDTH);
    end if;
   end loop;
  end if;
 end process;

end behavioral;
