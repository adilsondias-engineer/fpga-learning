-- Block RAM with Optional Output Registers
-- File: rams_pipeline.vhd
library IEEE;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

entity rams_pipeline is
 port(
  clk1, clk2   : in  std_logic;
  we, en1, en2 : in  std_logic;
  addr1        : in  std_logic_vector(9 downto 0);
  addr2        : in  std_logic_vector(9 downto 0);
  di           : in  std_logic_vector(15 downto 0);
  res1         : out std_logic_vector(15 downto 0);
  res2         : out std_logic_vector(15 downto 0)
 );
end rams_pipeline;

architecture beh of rams_pipeline is
 type ram_type is array (1023 downto 0) of std_logic_vector(15 downto 0);
 signal ram : ram_type;
 signal do1 : std_logic_vector(15 downto 0);
 signal do2 : std_logic_vector(15 downto 0);
begin
 process(clk1)
 begin
  if rising_edge(clk1) then
   if we = '1' then
    ram(to_integer(unsigned(addr1))) <= di;
   end if;
   do1 <= ram(to_integer(unsigned(addr1)));
  end if;
 end process;

 process(clk2)
 begin
  if rising_edge(clk2) then
   do2 <= ram(to_integer(unsigned(addr2)));
  end if;
 end process;

 process(clk1)
 begin
  if rising_edge(clk1) then
   if en1 = '1' then
    res1 <= do1;
   end if;
  end if;
 end process;

 process(clk2)
 begin
  if rising_edge(clk2) then
   if en2 = '1' then
    res2 <= do2;
   end if;
  end if;
 end process;

end beh;
